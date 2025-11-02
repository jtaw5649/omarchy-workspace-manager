#!/usr/bin/env bash
# CLI dispatcher for setup operations.

owm_source "lib/setup.sh"

owm_cli_setup_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager setup <command> [options]

Commands:
  install     Generate Hyprland keybinding and autostart fragments
  uninstall   Remove generated fragments
  help        Show this help message
USAGE
}

owm_cli_setup_install_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager setup install [OPTIONS]

Options:
      --base-dir <DIR>        Destination directory for generated fragments
      --bindings-path <PATH>  Override bindings fragment path
      --autostart-path <PATH> Override autostart fragment path
      --yes                   Overwrite existing files without confirmation
  -h, --help                  Show this help message
USAGE
}

owm_cli_setup_uninstall_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager setup uninstall [OPTIONS]

Options:
      --base-dir <DIR>        Destination directory for generated fragments
      --bindings-path <PATH>  Override bindings fragment path
      --autostart-path <PATH> Override autostart fragment path
      --yes                   Remove files without confirmation
  -h, --help                  Show this help message
USAGE
}

owm_cli_setup_install() {
	local base_dir=""
	local bindings_path=""
	local autostart_path=""
	local force=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--base-dir)
			base_dir="$2"
			shift 2
			;;
		--base-dir=*)
			base_dir="${1#*=}"
			shift
			;;
		--bindings-path)
			bindings_path="$2"
			shift 2
			;;
		--bindings-path=*)
			bindings_path="${1#*=}"
			shift
			;;
		--autostart-path)
			autostart_path="$2"
			shift 2
			;;
		--autostart-path=*)
			autostart_path="${1#*=}"
			shift
			;;
		--yes)
			force=1
			shift
			;;
		-h | --help)
			owm_cli_setup_install_usage
			return 0
			;;
		--)
			shift
			break
			;;
		-*)
			owm_die "unknown option '$1'"
			;;
		*)
			owm_die "unexpected argument '$1'"
			;;
		esac
	done

	if [[ $# -gt 0 ]]; then
		owm_die "unexpected argument '$1'"
	fi

	if [[ -n "$base_dir" ]]; then
		export OWM_SETUP_BASE_DIR="$base_dir"
	fi
	if [[ -n "$bindings_path" ]]; then
		export OWM_SETUP_BINDINGS_PATH="$bindings_path"
	fi
	if [[ -n "$autostart_path" ]]; then
		export OWM_SETUP_AUTOSTART_PATH="$autostart_path"
	fi
	if ((force == 1)); then
		export OWM_SETUP_FORCE=1
	fi

	owm_setup_install
}

owm_cli_setup_uninstall() {
	local base_dir=""
	local bindings_path=""
	local autostart_path=""
	local force=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--base-dir)
			base_dir="$2"
			shift 2
			;;
		--base-dir=*)
			base_dir="${1#*=}"
			shift
			;;
		--bindings-path)
			bindings_path="$2"
			shift 2
			;;
		--bindings-path=*)
			bindings_path="${1#*=}"
			shift
			;;
		--autostart-path)
			autostart_path="$2"
			shift 2
			;;
		--autostart-path=*)
			autostart_path="${1#*=}"
			shift
			;;
		--yes)
			force=1
			shift
			;;
		-h | --help)
			owm_cli_setup_uninstall_usage
			return 0
			;;
		--)
			shift
			break
			;;
		-*)
			owm_die "unknown option '$1'"
			;;
		*)
			owm_die "unexpected argument '$1'"
			;;
		esac
	done

	if [[ $# -gt 0 ]]; then
		owm_die "unexpected argument '$1'"
	fi

	if [[ -n "$base_dir" ]]; then
		export OWM_SETUP_BASE_DIR="$base_dir"
	fi
	if [[ -n "$bindings_path" ]]; then
		export OWM_SETUP_BINDINGS_PATH="$bindings_path"
	fi
	if [[ -n "$autostart_path" ]]; then
		export OWM_SETUP_AUTOSTART_PATH="$autostart_path"
	fi
	if ((force == 1)); then
		export OWM_SETUP_FORCE=1
	fi

	owm_setup_uninstall
}

owm_cli_setup() {
	if [[ $# -eq 0 ]]; then
		owm_cli_setup_usage
		return 1
	fi

	local subcommand="$1"
	shift || true

	case "$subcommand" in
	help | -h | --help)
		owm_cli_setup_usage
		;;
	install)
		owm_cli_setup_install "$@"
		;;
	uninstall)
		owm_cli_setup_uninstall "$@"
		;;
	*)
		owm_die "unknown setup command '$subcommand'"
		;;
	esac
}
