#!/usr/bin/env bash

owm_source "lib/daemon.sh"

owm_cli_daemon() {
	case "${1:-}" in
		-h|--help|help)
			echo "Usage: omarchy-workspace-manager daemon"
			echo "Starts the event loop for monitor changes."
			;;
		*)
			owm_daemon_run
			;;
	esac
}
