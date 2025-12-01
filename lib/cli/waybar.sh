#!/usr/bin/env bash

owm_source "lib/paired.sh"

owm_waybar_get_state() {
	local active_ws
	active_ws=$(hyprctl activeworkspace -j | jq -r '.id')
	local active_normalized
	active_normalized=$(owm_paired_normalize "$active_ws")

	# Get workspaces that have windows (occupied)
	local occupied
	occupied=$(hyprctl workspaces -j | jq -r --argjson off "$OWM_PAIRED_OFFSET" \
		'[.[].id | if . > $off then . - $off else . end] | unique | .[]')

	local output=""
	local occupied_list=" $occupied "

	for i in 1 2 3 4 5; do
		local class="empty"
		if [[ "$i" -eq "$active_normalized" ]]; then
			class="active"
		elif [[ "$occupied_list" == *" $i "* ]]; then
			class="occupied"
		fi
		output+="<span class='$class'>$i</span> "
	done

	# Trim trailing space
	output="${output% }"

	printf '{"text":"%s","tooltip":"Active: %s","class":"workspaces"}\n' \
		"$output" "$active_normalized"
}

owm_cli_waybar() {
	owm_paired_load_config

	case "${1:-}" in
		-h|--help|help)
			cat <<'USAGE'
Usage: omarchy-workspace-manager waybar

Outputs JSON for Waybar custom module with pango markup.
Classes: active, occupied, empty
USAGE
			return 0
			;;
	esac

	owm_waybar_get_state

	local socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
	[[ -S "$socket" ]] || owm_die "Hyprland socket not found"

	socat -U - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
		case "$line" in
			workspace*|focusedmon*|createworkspace*|destroyworkspace*|openwindow*|closewindow*|movewindow*)
				owm_waybar_get_state
				;;
		esac
	done
}
