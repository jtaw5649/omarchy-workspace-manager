#!/usr/bin/env bash
# CLI dispatcher for checkpoint operations.

owm_source "lib/checkpoints.sh"

owm_cli_checkpoints_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager checkpoints <command> [options]

Commands:
  diff   Compare persisted workspace assignments with expected layout
  help   Show this help message
USAGE
}

owm_cli_checkpoints_diff_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager checkpoints diff [OPTIONS]

Options:
      --expected <PATH>  Path to expected checkpoint (default config/paired.json)
      --actual <PATH>    Path to actual checkpoint (default ~/.config/hypr/workspace_manager.conf)
      --json             Emit diff as JSON
  -h, --help             Show this help message
USAGE
}

owm_cli_checkpoints_diff() {
	local expected_path
	expected_path="$(owm_checkpoints_default_expected)"
	local actual_path
	actual_path="$(owm_checkpoints_default_actual)"
	local json_output=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--expected)
			expected_path="$2"
			shift 2
			;;
		--expected=*)
			expected_path="${1#*=}"
			shift
			;;
		--actual)
			actual_path="$2"
			shift 2
			;;
		--actual=*)
			actual_path="${1#*=}"
			shift
			;;
		--json)
			json_output=1
			shift
			;;
		-h | --help)
			owm_cli_checkpoints_diff_usage
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

	owm_checkpoints_diff "$expected_path" "$actual_path" "$json_output"
}

owm_cli_checkpoints() {
	if [[ $# -eq 0 ]]; then
		owm_cli_checkpoints_usage
		return 1
	fi

	local subcommand="$1"
	shift || true

	case "$subcommand" in
	help | -h | --help)
		owm_cli_checkpoints_usage
		;;
	diff)
		owm_cli_checkpoints_diff "$@"
		;;
	*)
		owm_die "unknown checkpoints command '$subcommand'"
		;;
	esac
}
