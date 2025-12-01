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
		'[.[] | select(.windows > 0) | .id | if . > $off then . - $off else . end] | unique | .[]')

	local output=""
	local occupied_list=" ${occupied//$'\n'/ } "

	for i in 1 2 3 4 5; do
		local is_active=false is_occupied=false
		[[ "$i" -eq "$active_normalized" ]] && is_active=true
		[[ "$occupied_list" == *" $i "* ]] && is_occupied=true

		if $is_active; then
			if $is_occupied; then
				# Active + has windows: bright rounded square
				output+="<span foreground='#ffffff'>󱓻</span> "
			else
				# Active + no windows: dim rounded square
				output+="<span foreground='#666666'>󱓻</span> "
			fi
		else
			if $is_occupied; then
				# Inactive + has windows: mid-bright number
				output+="<span foreground='#aaaaaa'>$i</span> "
			else
				# Inactive + no windows: dim number
				output+="<span foreground='#666666'>$i</span> "
			fi
		fi
	done

	# Trim trailing space
	output="${output% }"

	# JSON-safe fields
	local text_json tooltip_json
	text_json=$(printf '%s' "$output" | jq -Rs .)
	tooltip_json=$(printf 'Active: %s' "$active_normalized" | jq -Rs .)

	printf '{"text":%s,"tooltip":%s,"class":"workspaces","markup":true}\n' \
		"$text_json" "$tooltip_json" 2>/dev/null || true
}

owm_cli_waybar() {
	# Avoid SIGPIPE noise when Waybar or socat closes the pipe
	trap '' PIPE

	owm_paired_load_config

	case "${1:-}" in
		-h|--help|help)
			cat <<'USAGE'
Usage: omarchy-workspace-manager waybar

Outputs JSON for Waybar custom module with inline pango styling.
Active workspaces show a square, inactive show numbers.
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
