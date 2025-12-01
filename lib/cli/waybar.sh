#!/usr/bin/env bash

owm_source "lib/paired.sh"

declare -g OWM_COLOR_BRIGHT OWM_COLOR_MID OWM_COLOR_DIM

owm_waybar_dim_color() {
	local hex="$1" factor="$2"
	local r=$((16#${hex:1:2})) g=$((16#${hex:3:2})) b=$((16#${hex:5:2}))
	printf '#%02x%02x%02x' $((r * factor / 100)) $((g * factor / 100)) $((b * factor / 100))
}

owm_waybar_load_theme_colors() {
	local fg=$(grep -oP '@define-color foreground \K#[0-9a-fA-F]{6}' "$HOME/.config/omarchy/current/theme/waybar.css")
	OWM_COLOR_BRIGHT="$fg"
	OWM_COLOR_MID=$(owm_waybar_dim_color "$fg" 65)
	OWM_COLOR_DIM=$(owm_waybar_dim_color "$fg" 40)
}

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
			output+="<span foreground='$OWM_COLOR_BRIGHT'>󱓻</span> "
		elif $is_occupied; then
			output+="<span foreground='$OWM_COLOR_MID'>$i</span> "
		else
			output+="<span foreground='$OWM_COLOR_DIM'>$i</span> "
		fi
	done

	# Trim trailing space
	output="${output% }"

	# JSON-safe text field
	local text_json
	text_json=$(printf '%s' "$output" | jq -Rs .)

	printf '{"text":%s,"class":"workspaces","markup":true}\n' \
		"$text_json" 2>/dev/null || true
}

owm_cli_waybar() {
	# Avoid SIGPIPE noise when Waybar or socat closes the pipe
	trap '' PIPE

	owm_paired_load_config
	owm_waybar_load_theme_colors

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
