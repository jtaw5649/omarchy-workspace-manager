#!/usr/bin/env bash
# Daemon utilities for monitoring Hyprland state changes.

owm_source "lib/dispatch.sh"

declare -g -A OWM_DAEMON_LAST_DPMS=()
declare -g -A OWM_DAEMON_LAST_DISABLED=()
OWM_DAEMON_NEEDS_DISPATCH=0
OWM_DAEMON_NEEDS_RELOAD=0
OWM_DAEMON_LAST_DISPATCH=0
OWM_DAEMON_DISPATCH_THROTTLE_MS=500

owm_daemon_snapshot_signature() {
	local monitors_json="$1"
	printf '%s\n' "$monitors_json" |
		jq -c 'sort_by(.name) | map({name, description, dpms: (if has("dpmsStatus") then .dpmsStatus else true end), disabled: (if has("disabled") then .disabled else false end)})'
}

owm_daemon_now_ms() {
	local now
	if now="$(date +%s%3N 2>/dev/null)"; then
		printf '%s\n' "$now"
	else
		now="$(date +%s 2>/dev/null || printf '0')"
		printf '%s\n' "$((now * 1000))"
	fi
}

owm_daemon_guard_sync() {
	local monitors_json="$1"
	local needs_dispatch=0
	local needs_reload=0
	local -A seen=()

	while IFS=$'\t' read -r name dpms disabled; do
		[[ -n "$name" ]] || continue
		seen["$name"]=1
		local dpms_str="$dpms"
		local disabled_str="$disabled"
		local last_dpms="${OWM_DAEMON_LAST_DPMS[$name]-}"
		local last_disabled="${OWM_DAEMON_LAST_DISABLED[$name]-}"
		if [[ -z "$last_dpms" ]]; then
			needs_dispatch=1
			needs_reload=1
		elif [[ "$dpms_str" != "$last_dpms" || "$disabled_str" != "$last_disabled" ]]; then
			needs_dispatch=1
			needs_reload=1
		fi
		OWM_DAEMON_LAST_DPMS["$name"]="$dpms_str"
		OWM_DAEMON_LAST_DISABLED["$name"]="$disabled_str"
	done < <(printf '%s\n' "$monitors_json" | jq -r '.[] | [.name, (if has("dpmsStatus") then (.dpmsStatus|tostring) else "true" end), (if has("disabled") then (.disabled|tostring) else "false" end)] | @tsv')

	for existing in "${!OWM_DAEMON_LAST_DPMS[@]}"; do
		if [[ -z "${seen[$existing]:-}" ]]; then
			needs_dispatch=1
			needs_reload=1
			unset "OWM_DAEMON_LAST_DPMS[$existing]"
			unset "OWM_DAEMON_LAST_DISABLED[$existing]"
		fi
	done

	OWM_DAEMON_NEEDS_DISPATCH="$needs_dispatch"
	OWM_DAEMON_NEEDS_RELOAD="$needs_reload"
}

owm_daemon_reload_hypr() {
	local hyprctl="${OWM_DAEMON_HYPRCTL:-}"
	if [[ -z "$hyprctl" ]]; then
		hyprctl="$(command -v hyprctl || true)"
	fi
	if [[ -n "$hyprctl" ]]; then
		"$hyprctl" reload >/dev/null 2>&1 || owm_warn "hyprctl reload failed after monitor update"
	fi
}

owm_daemon_rebalance_state() {
	local monitors_json="$1"

	local primary_monitor="$OWM_PAIRED_PRIMARY"
	local secondary_monitor="$OWM_PAIRED_SECONDARY"

	readarray -t inactive_monitors < <(printf '%s\n' "$monitors_json" | jq -r '.[] | select(((if has("dpmsStatus") then .dpmsStatus else true end) == false) or ((.disabled // false) == true)) | .name')

	declare -A monitor_present=()
	while IFS= read -r name; do
		[[ -n "$name" ]] && monitor_present["$name"]=1
	done < <(printf '%s\n' "$monitors_json" | jq -r '.[].name')

	if [[ -n "$secondary_monitor" && -z "${monitor_present[$secondary_monitor]:-}" ]]; then
		inactive_monitors+=("$secondary_monitor")
	fi

	local active_monitor
	active_monitor="$(printf '%s\n' "$monitors_json" | jq -r '[.[] | select(((if has("dpmsStatus") then .dpmsStatus else true end) == true) and ((.disabled // false) == false))] | sort_by(.id) | .[0].name // empty')"
	if [[ -z "$active_monitor" ]]; then
		active_monitor="$primary_monitor"
	fi
	if [[ -z "$active_monitor" ]]; then
		owm_debug "no active monitor available for rebalance"
		return 0
	fi

	owm_debug "rebalance targeting active monitor $active_monitor from (${inactive_monitors[*]})"

	local offset="${OWM_PAIRED_OFFSET:-}"
	if ! [[ "$offset" =~ ^[0-9]+$ ]] || ((offset <= 0)); then
		offset=10
	fi

	local clients_json
	if ! clients_json="$(owm_hypr_get_json clients)"; then
		return 0
	fi

	declare -A inactive_lookup=()
	local monitor
	for monitor in "${inactive_monitors[@]}"; do
		inactive_lookup["$monitor"]=1
	done

	local windows_moved=0
	while IFS=$'\t' read -r address workspace_id monitor_name; do
		[[ -n "$address" && -n "$workspace_id" ]] || continue
		if ! [[ "$workspace_id" =~ ^-?[0-9]+$ ]]; then
			continue
		fi

		local normalized_workspace
		normalized_workspace="$(owm_paired_normalize_workspace "$workspace_id" "$offset")"
		if [[ -z "$normalized_workspace" ]]; then
			normalized_workspace="$workspace_id"
		fi

		local needs_workspace_change=0
		if [[ "$normalized_workspace" != "$workspace_id" ]]; then
			needs_workspace_change=1
		elif ((workspace_id > offset)); then
			needs_workspace_change=1
			normalized_workspace=$((workspace_id - offset))
		fi

		local monitor_inactive=0
		if [[ -n "$monitor_name" && -n "${inactive_lookup[$monitor_name]:-}" ]]; then
			monitor_inactive=1
		elif ((workspace_id > offset)) && [[ -n "$secondary_monitor" && -n "${inactive_lookup[$secondary_monitor]:-}" ]]; then
			monitor_inactive=1
		fi

		if ((monitor_inactive == 0)) && ((needs_workspace_change == 0)); then
			continue
		fi

		owm_hypr_dispatch focuswindow "address:$address"

		if ((monitor_inactive == 1)); then
			local target_monitor="$active_monitor"
			if [[ -n "$primary_monitor" ]]; then
				target_monitor="$primary_monitor"
			fi
			owm_hypr_dispatch movewindow "mon:$target_monitor"
		fi

		if ((needs_workspace_change == 1)); then
			owm_hypr_dispatch movetoworkspacesilent "$normalized_workspace"
		fi

		windows_moved=1
	done < <(printf '%s\n' "$clients_json" | jq -r '.[] | [.address, (if .workspace != null and .workspace.id != null then .workspace.id else (.workspaceID // empty) end), (.monitor // "")] | @tsv')

	if ((windows_moved == 1)); then
		owm_waybar_refresh
	fi
}

owm_daemon_cleanup() {
	local pid_file="${OWM_DAEMON_PID_FILE:-}"
	trap - INT TERM EXIT
	if [[ -n "$pid_file" ]]; then
		rm -f -- "$pid_file"
	fi
	unset OWM_DAEMON_PID_FILE
	exit 0
}

owm_daemon_run() {
	local poll_interval="${1:-${OWM_POLL_INTERVAL:-0.2}}"
	local pid_file="${OWM_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}/omarchy-workspace-manager}/daemon.pid"

	owm_ensure_dir "$(dirname -- "$pid_file")"

	if [[ -f "$pid_file" ]]; then
		local existing_pid
		existing_pid="$(<"$pid_file")"
		if [[ -n "$existing_pid" && "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
			owm_warn "daemon already running with pid $existing_pid; refusing second instance"
			return 0
		fi
		owm_warn "removing stale daemon pid file for pid ${existing_pid:-unknown}"
		rm -f -- "$pid_file"
	fi

	printf '%s\n' "$$" >"$pid_file"
	OWM_DAEMON_PID_FILE="$pid_file"
	trap owm_daemon_cleanup INT TERM EXIT

	owm_paired_load_config "${OWM_DAEMON_PRIMARY_OVERRIDE:-}" "${OWM_DAEMON_SECONDARY_OVERRIDE:-}" "${OWM_DAEMON_OFFSET_OVERRIDE:-}"
	owm_dispatch_run 0
	OWM_DAEMON_LAST_DISPATCH="$(owm_daemon_now_ms)"

	local last_signature=""

	while true; do
		local monitors_json
		if ! monitors_json="$(owm_hypr_get_json monitors)"; then
			owm_warn "hyprctl monitors failed; retrying after pause"
			sleep "$poll_interval"
			continue
		fi

		owm_daemon_guard_sync "$monitors_json"
		local needs_dispatch="$OWM_DAEMON_NEEDS_DISPATCH"
		local needs_reload="$OWM_DAEMON_NEEDS_RELOAD"

		local signature
		signature="$(owm_daemon_snapshot_signature "$monitors_json")"
		owm_debug "monitor signature $signature"

		if [[ -z "$last_signature" || "$signature" != "$last_signature" ]]; then
			owm_debug "detected monitor topology change; redispatching"
			needs_dispatch=1
			needs_reload=1
		fi

		if ((needs_reload == 1)); then
			owm_daemon_reload_hypr
		fi

		if ((needs_dispatch == 1)); then
			local now_ms throttled
			now_ms="$(owm_daemon_now_ms)"
			throttled=0
			if [[ "$OWM_DAEMON_LAST_DISPATCH" =~ ^[0-9]+$ ]]; then
				local delta=$((now_ms - OWM_DAEMON_LAST_DISPATCH))
				if ((delta < OWM_DAEMON_DISPATCH_THROTTLE_MS)); then
					throttled=1
					owm_debug "Skipping dispatch (${OWM_DAEMON_DISPATCH_THROTTLE_MS}ms throttle window)"
				fi
			fi
			if ((throttled == 0)); then
				owm_dispatch_run 0
				OWM_DAEMON_LAST_DISPATCH="$now_ms"
				if [[ "${OWM_DAEMON_AUTO_CONFIG:-0}" == "1" ]]; then
					owm_daemon_regenerate_config
				fi
				if [[ "${OWM_DAEMON_AUTO_MOVE:-1}" == "1" ]]; then
					owm_daemon_rebalance_state "$monitors_json"
				fi
				last_signature="$signature"
			fi
		fi

		sleep "$poll_interval"
	done
}

owm_daemon_regenerate_config() {
	local base_dir="${OWM_CONFIG_DIR:-$OWM_ROOT/config}"
	local binary="${OWM_BIN_DIR:-$OWM_ROOT/bin}/omarchy-workspace-manager"

	if [[ ! -x "$binary" ]]; then
		owm_warn "cannot regenerate config; missing $binary"
		return
	fi

	if ! "$binary" setup install --base-dir "$base_dir" --yes >/dev/null 2>&1; then
		owm_warn "config regeneration via setup install failed"
	else
		owm_debug "regenerated hypr config fragments after monitor change"
	fi

	if command -v hyprctl >/dev/null 2>&1; then
		hyprctl reload >/dev/null 2>&1 || owm_warn "hyprctl reload failed after config regeneration"
	fi
}
