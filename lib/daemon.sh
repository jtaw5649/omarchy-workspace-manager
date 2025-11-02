#!/usr/bin/env bash
# Daemon utilities for monitoring Hyprland state changes.

owm_source "lib/dispatch.sh"

declare -g -A OWM_DAEMON_LAST_DPMS=()
declare -g -A OWM_DAEMON_LAST_DISABLED=()
declare -g -A OWM_DAEMON_LAST_RECOVER=()
OWM_DAEMON_NEEDS_DISPATCH=0
OWM_DAEMON_NEEDS_RELOAD=0
OWM_DAEMON_LAST_DISPATCH=0
OWM_DAEMON_DISPATCH_THROTTLE_MS=500
OWM_DAEMON_LAST_SIGNATURE=""

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

owm_daemon_managed_monitor() {
	local name="$1"
	[[ "$name" == "$OWM_PAIRED_PRIMARY" || "$name" == "$OWM_PAIRED_SECONDARY" ]]
}

owm_daemon_attempt_recover_monitor() {
	local identifier="$1"
	local reason="${2:-unknown}"
	[[ -n "$identifier" ]] || return 1
	local now_ms
	now_ms="$(owm_daemon_now_ms)"
	local last="${OWM_DAEMON_LAST_RECOVER[$identifier]-0}"
	if [[ "$last" =~ ^[0-9]+$ && $((now_ms - last)) -lt 2000 ]]; then
		return 0
	fi
	OWM_DAEMON_LAST_RECOVER["$identifier"]="$now_ms"
	owm_info "attempting monitor recovery for '$identifier' (reason: $reason)"
	if ! owm_hyprctl keyword monitor "$identifier,preferred,auto,1" >/dev/null 2>&1; then
		owm_warn "monitor recovery via hyprctl keyword monitor for '$identifier' failed"
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
		if [[ "$dpms_str" == "false" || "$dpms_str" == "0" || "$disabled_str" == "true" ]]; then
			if owm_daemon_managed_monitor "$name"; then
				owm_daemon_attempt_recover_monitor "$name" "dpms"
			fi
		fi
	done < <(printf '%s\n' "$monitors_json" | jq -r '.[] | [.name, (if has("dpmsStatus") then (.dpmsStatus|tostring) else "true" end), (if has("disabled") then (.disabled|tostring) else "false" end)] | @tsv')

	for existing in "${!OWM_DAEMON_LAST_DPMS[@]}"; do
		if [[ -z "${seen[$existing]:-}" ]]; then
			needs_dispatch=1
			needs_reload=1
			if owm_daemon_managed_monitor "$existing"; then
				owm_daemon_attempt_recover_monitor "$existing" "missing"
			fi
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
	local -a dispatch_commands=()
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

		if ((monitor_inactive == 1)); then
			local target_monitor="$active_monitor"
			if [[ -n "$primary_monitor" ]]; then
				target_monitor="$primary_monitor"
			fi
			dispatch_commands+=("$(owm_hypr_build_dispatch movewindow "mon:${target_monitor},address:$address")")
		fi

		if ((needs_workspace_change == 1)); then
			dispatch_commands+=("$(owm_hypr_build_dispatch movetoworkspacesilent "${normalized_workspace},address:$address")")
		fi

		windows_moved=1
	done < <(printf '%s\n' "$clients_json" | jq -r '.[] | [.address, (if .workspace != null and .workspace.id != null then .workspace.id else (.workspaceID // empty) end), (.monitor // "")] | @tsv')

	if ((windows_moved == 1)); then
		if ((${#dispatch_commands[@]} > 0)); then
			owm_hypr_dispatch_batch "${dispatch_commands[@]}"
		fi
		owm_waybar_refresh
	fi
}

owm_daemon_socket_path() {
	local signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
	if [[ -z "$signature" ]]; then
		return 1
	fi
	local runtime="${XDG_RUNTIME_DIR:-/tmp}"
	printf '%s/hypr/%s/.socket2.sock\n' "$runtime" "$signature"
}

owm_daemon_trigger_dispatch() {
	local monitors_json="$1"
	local reason="${2:-event}"
	local now_ms
	now_ms="$(owm_daemon_now_ms)"
	if [[ "$OWM_DAEMON_LAST_DISPATCH" =~ ^[0-9]+$ ]]; then
		local delta=$((now_ms - OWM_DAEMON_LAST_DISPATCH))
		if ((delta < OWM_DAEMON_DISPATCH_THROTTLE_MS)); then
			owm_debug "skipping dispatch for $reason (${OWM_DAEMON_DISPATCH_THROTTLE_MS}ms throttle window)"
			return 0
		fi
	fi

	owm_dispatch_run 0
	OWM_DAEMON_LAST_DISPATCH="$now_ms"

	if [[ "${OWM_DAEMON_AUTO_CONFIG:-0}" == "1" ]]; then
		owm_daemon_regenerate_config
	fi
	if [[ "${OWM_DAEMON_AUTO_MOVE:-1}" == "1" ]]; then
		owm_daemon_rebalance_state "$monitors_json"
	fi
}

owm_daemon_refresh_state() {
	local reason="${1:-event}"
	local monitors_json
	if ! monitors_json="$(owm_hypr_get_json monitors)"; then
		owm_warn "hyprctl monitors failed during $reason; retrying later"
		return 1
	fi

	owm_daemon_guard_sync "$monitors_json"
	local needs_dispatch="$OWM_DAEMON_NEEDS_DISPATCH"
	local needs_reload="$OWM_DAEMON_NEEDS_RELOAD"

	local signature
	signature="$(owm_daemon_snapshot_signature "$monitors_json")"
	if [[ -z "$OWM_DAEMON_LAST_SIGNATURE" || "$signature" != "$OWM_DAEMON_LAST_SIGNATURE" ]]; then
		owm_debug "monitor topology change detected via $reason"
		needs_dispatch=1
		needs_reload=1
	fi

	if ((needs_reload == 1)); then
		owm_daemon_reload_hypr
	fi
	if ((needs_dispatch == 1)); then
		owm_daemon_trigger_dispatch "$monitors_json" "$reason"
	fi

	OWM_DAEMON_LAST_SIGNATURE="$signature"
	return 0
}

owm_daemon_handle_monitor_event() {
	local event="$1"
	local payload="$2"

	local monitor_id=""
	local monitor_name=""
	local monitor_desc=""

	case "$event" in
	monitoraddedv2 | monitorremovedv2)
		if [[ -n "$payload" ]]; then
			IFS=',' read -r monitor_id monitor_name monitor_desc <<<"$payload"
			monitor_id="${monitor_id:-}"
			monitor_name="${monitor_name:-}"
			if [[ "$monitor_desc" == "$monitor_name" ]]; then
				monitor_desc=""
			fi
		fi
		;;
	monitoradded | monitorremoved)
		monitor_name="$payload"
		;;
	esac

	local matched_role=""
	if owm_paired_monitor_matches primary "$monitor_id" "$monitor_name" "$monitor_desc"; then
		matched_role="primary"
	elif owm_paired_monitor_matches secondary "$monitor_id" "$monitor_name" "$monitor_desc"; then
		matched_role="secondary"
	fi

	local summary="id=${monitor_id:-<none>} name=${monitor_name:-<none>}"
	if [[ -n "$monitor_desc" ]]; then
		summary+=", desc=${monitor_desc}"
	fi

	if [[ -n "$matched_role" ]]; then
		owm_info "monitor event [$event] matched $matched_role ($summary)"
	else
		owm_debug "monitor event [$event] ignored (unmanaged output) ($summary)"
	fi

	owm_daemon_refresh_state "event:$event:${matched_role:-unmanaged}"
}

owm_daemon_handle_event() {
	local message="$1"
	[[ -n "$message" ]] || return 0
	local event="${message%%>>*}"
	local payload=""
	if [[ "$message" == *">>"* ]]; then
		payload="${message#*>>}"
	fi
	case "$event" in
	monitoradded | monitoraddedv2 | monitorremoved | monitorremovedv2)
		owm_daemon_handle_monitor_event "$event" "$payload"
		return
		;;
	workspace | workspacev2 | focusedmon | focusedmonv2 | configreloaded | createworkspace | destroyworkspace | moveworkspace | moveworkspacev2 | activespecial | activespecialv2 | activewindow | activewindowv2 | dpms)
		owm_debug "event[$event] $payload"
		owm_daemon_refresh_state "event:$event"
		;;
	*)
		owm_debug "ignoring event[$event]"
		;;
	esac
}

owm_daemon_events_forever() {
	local socket_path
	socket_path="$(owm_daemon_socket_path)" || {
		owm_warn "HYPRLAND_INSTANCE_SIGNATURE not set; cannot listen for events"
		return 1
	}
	if [[ ! -S "$socket_path" ]]; then
		owm_warn "Hyprland event socket not found at $socket_path"
		return 1
	fi
	if ! command -v socat >/dev/null 2>&1; then
		owm_warn "socat not available; event listener disabled"
		return 1
	fi

	owm_info "listening for Hyprland events on $socket_path"

	while true; do
		coproc HYPR_EVENTS { socat -U UNIX-CONNECT:"$socket_path" -; }
		if [[ -z "${HYPR_EVENTS_PID:-}" ]]; then
			return 1
		fi
		while IFS= read -r line <&"${HYPR_EVENTS[0]}"; do
			[[ -n "$line" ]] || continue
			owm_daemon_handle_event "$line"
		done
		local read_status=$?
		kill "$HYPR_EVENTS_PID" 2>/dev/null || true
		wait "$HYPR_EVENTS_PID" 2>/dev/null || true
		if ((read_status == 0)); then
			owm_debug "event stream closed; reconnecting"
		else
			owm_warn "event stream interrupted (status $read_status); reconnecting in 1s"
		fi
		sleep 1
	done
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
	OWM_DAEMON_LAST_DISPATCH=0
	OWM_DAEMON_LAST_SIGNATURE=""
	owm_daemon_refresh_state "startup"

	if ! owm_daemon_events_forever; then
		owm_die "Hyprland event stream unavailable; ensure socat is installed and Hyprland is running"
	fi
}
