#!/usr/bin/env bash

owm_source "lib/setup.sh"

owm_cli_setup_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager setup <command>

Commands:
  install          Generate Hyprland fragments
  uninstall        Remove generated fragments
  migrate-windows  Move secondary windows to paired primary workspaces
USAGE
}

owm_cli_setup() {
	case "${1:-}" in
		install)
			owm_setup_install
			;;
		uninstall)
			owm_setup_uninstall
			;;
		migrate-windows)
			owm_setup_migrate_windows
			;;
		-h|--help|help|"")
			owm_cli_setup_usage
			;;
		*)
			owm_die "unknown command: $1"
			;;
	esac
}
