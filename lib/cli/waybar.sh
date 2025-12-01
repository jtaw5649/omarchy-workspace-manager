#!/usr/bin/env bash

owm_source "lib/paired.sh"

owm_waybar_get_state() {
	local active_ws=$(hyprctl activeworkspace -j | jq -r '.id')
	local normalized=$(owm_paired_normalize "$active_ws")
	local workspaces=$(hyprctl workspaces -j | jq -r --argjson off "$OWM_PAIRED_OFFSET" \
		'[.[].id | if . > $off then . - $off else . end] | unique | sort | map(tostring) | join(" ")')
	printf '{"text":"%s","tooltip":"Workspaces: %s","class":"ws-%s","alt":"%s"}\n' \
		"$normalized" "$workspaces" "$normalized" "$workspaces"
}

owm_cli_waybar() {
	owm_paired_load_config

	case "${1:-}" in
		-h|--help|help)
			cat <<'USAGE'
Usage: omarchy-workspace-manager waybar

Outputs JSON for Waybar custom module.
USAGE
			return 0
			;;
	esac

	owm_waybar_get_state

	local socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
	[[ -S "$socket" ]] || owm_die "Hyprland socket not found"

	socat -U - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
		case "$line" in
			workspace*|focusedmon*|createworkspace*|destroyworkspace*)
				owm_waybar_get_state
				;;
		esac
	done
}
