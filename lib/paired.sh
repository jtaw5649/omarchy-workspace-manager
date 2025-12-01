#!/usr/bin/env bash

declare -g OWM_PAIRED_PRIMARY=""
declare -g OWM_PAIRED_SECONDARY=""
declare -g OWM_PAIRED_OFFSET=10

owm_paired_load_config() {
	[[ -f "$OWM_CONFIG_PATH" ]] || owm_die "config not found: $OWM_CONFIG_PATH"
	OWM_PAIRED_PRIMARY="$(jq -r '.primary_monitor // empty' "$OWM_CONFIG_PATH")"
	OWM_PAIRED_SECONDARY="$(jq -r '.secondary_monitor // empty' "$OWM_CONFIG_PATH")"
	OWM_PAIRED_OFFSET="$(jq -r '.paired_offset // 10' "$OWM_CONFIG_PATH")"
	[[ -n "$OWM_PAIRED_PRIMARY" && -n "$OWM_PAIRED_SECONDARY" ]] || owm_die "monitors not configured"
}

owm_paired_normalize() { echo $(( (($1 - 1) % OWM_PAIRED_OFFSET) + 1 )); }

owm_paired_switch() {
	local normalized=$(owm_paired_normalize "$1")
	local secondary_ws=$((normalized + OWM_PAIRED_OFFSET))
	hyprctl --batch "dispatch focusmonitor $OWM_PAIRED_SECONDARY ; dispatch workspace $secondary_ws ; dispatch focusmonitor $OWM_PAIRED_PRIMARY ; dispatch workspace $normalized"
}

owm_paired_cycle() {
	local direction="$1"
	local active=$(hyprctl activeworkspace -j | jq -r '.id')
	local base=$(owm_paired_normalize "$active")
	local target

	case "$direction" in
		next) target=$(( (base % OWM_PAIRED_OFFSET) + 1 )) ;;
		prev) target=$(( ((base - 2 + OWM_PAIRED_OFFSET) % OWM_PAIRED_OFFSET) + 1 )) ;;
		*) owm_die "direction must be 'next' or 'prev'" ;;
	esac
	owm_paired_switch "$target"
}

owm_paired_move_window() {
	local normalized=$(owm_paired_normalize "$1")
	local active_ws=$(hyprctl activeworkspace -j | jq -r '.id')
	local target_ws="$normalized"

	((active_ws > OWM_PAIRED_OFFSET)) && target_ws=$((normalized + OWM_PAIRED_OFFSET))
	hyprctl dispatch movetoworkspacesilent "$target_ws"
	owm_paired_switch "$normalized"
}
