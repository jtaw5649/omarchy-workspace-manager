#!/usr/bin/env bash

owm_source "lib/paired.sh"

owm_daemon_rebalance() {
	for ((i = 1; i <= OWM_PAIRED_OFFSET; i++)); do
		hyprctl dispatch moveworkspacetomonitor "$i" "$OWM_PAIRED_PRIMARY"
		hyprctl dispatch moveworkspacetomonitor "$((i + OWM_PAIRED_OFFSET))" "$OWM_PAIRED_SECONDARY"
	done
}

owm_daemon_run() {
	owm_paired_load_config

	local socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
	[[ -S "$socket" ]] || owm_die "Hyprland socket not found"

	owm_daemon_rebalance

	socat -U - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
		case "$line" in
			monitoradded*|monitorremoved*)
				owm_daemon_rebalance
				;;
		esac
	done
}
