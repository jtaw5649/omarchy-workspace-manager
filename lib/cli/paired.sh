#!/usr/bin/env bash

owm_source "lib/paired.sh"

owm_cli_paired_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager paired <command> [args]

Commands:
  switch <N>      Switch both monitors to paired workspace N
  cycle <dir>     Cycle to next|prev paired workspace
  move-window <N> Move focused window to paired workspace N (stays on current workspace)
USAGE
}

owm_cli_paired() {
	[[ $# -gt 0 ]] || { owm_cli_paired_usage; return 1; }

	local cmd="$1"; shift
	owm_paired_load_config

	case "$cmd" in
		switch)
			[[ $# -gt 0 ]] || owm_die "workspace number required"
			owm_paired_switch "$1"
			;;
		cycle)
			[[ $# -gt 0 ]] || owm_die "direction required (next|prev)"
			owm_paired_cycle "$1"
			;;
		move-window)
			[[ $# -gt 0 ]] || owm_die "workspace number required"
			owm_paired_move_window "$1"
			;;
		-h|--help|help)
			owm_cli_paired_usage
			;;
		*)
			owm_die "unknown command: $cmd"
			;;
	esac
}
