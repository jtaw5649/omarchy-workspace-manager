#!/usr/bin/env bash
# Hyprland helpers for Omarchy Workspace Manager.

owm_hyprctl_bin() {
	if [[ -n "${OWM_HYPRCTL_BIN:-}" ]]; then
		printf '%s' "$OWM_HYPRCTL_BIN"
	elif [[ -n "${OWM_HYPRCTL:-}" ]]; then
		printf '%s' "$OWM_HYPRCTL"
	else
		printf '%s' "hyprctl"
	fi
}

owm_hyprctl() {
	local bin
	bin="$(owm_hyprctl_bin)"
	"$bin" "$@"
}

owm_hypr_dispatch() {
	owm_hyprctl dispatch "$@"
}

owm_hypr_focused_monitor() {
	local json
	if ! json="$(owm_hypr_get_json monitors)"; then
		return 1
	fi
	if [[ -z "$json" || "$json" == "null" ]]; then
		return 1
	fi

	local monitor
	monitor="$(printf '%s\n' "$json" | jq -r '
		def pick_name($m):
			if ($m.name // "") != "" then $m.name
			elif ($m.description // "") != "" then $m.description
			else ""
			end;
		([.[] | select((.focused? // false) == true)] | first) // ([.[]] | sort_by(.id // 0) | first)
		| (pick_name(.)) // ""
	')"

	if [[ -n "$monitor" ]]; then
		printf '%s\n' "$monitor"
	else
		return 1
	fi
}

owm_hypr_get_json() {
	local resource="$1"
	shift || true
	owm_hyprctl "$resource" "$@" -j
}

owm_hypr_active_workspace_id() {
	local json
	if ! json="$(owm_hypr_get_json activeworkspace)"; then
		return 1
	fi
	if [[ -z "$json" || "$json" == "null" ]]; then
		return 1
	fi
	printf '%s\n' "$json" | jq -r 'if has("id") then .id else empty end'
}

owm_hypr_active_window() {
	local json
	if ! json="$(owm_hypr_get_json activewindow)"; then
		return 1
	fi
	if [[ -z "$json" || "$json" == "null" ]]; then
		return 1
	fi
	printf '%s\n' "$json"
}
