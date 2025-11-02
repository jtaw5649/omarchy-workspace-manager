#!/usr/bin/env bash
# CLI dispatcher for paired workspace operations.

owm_source "lib/paired.sh"

owm_cli_paired_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager paired <command> [options]

Commands:
  switch       Synchronise both monitors to the paired workspace index
  cycle        Cycle to the next or previous paired workspace
  move-window  Move the focused window to the paired workspace index
  explain      Explain how paired workspaces are resolved
  help         Show this help message
USAGE
}

owm_cli_paired_switch_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager paired switch [OPTIONS] <WORKSPACE>

Options:
      --primary <NAME>      Override the primary monitor identifier
      --secondary <NAME>    Override the secondary monitor identifier
      --offset <NUMBER>     Override the paired workspace offset (default 10)
      --no-waybar           Skip Waybar refresh
  -h, --help                Show this help message
USAGE
}

owm_cli_paired_cycle_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager paired cycle [OPTIONS] <DIRECTION>

Arguments:
  <DIRECTION>  next | prev

Options:
      --primary <NAME>      Override the primary monitor identifier
      --secondary <NAME>    Override the secondary monitor identifier
      --offset <NUMBER>     Override the paired workspace offset (default 10)
      --no-waybar           Skip Waybar refresh
  -h, --help                Show this help message
USAGE
}

owm_cli_paired_move_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager paired move-window [OPTIONS] <WORKSPACE>

Options:
      --primary <NAME>      Override the primary monitor identifier
      --secondary <NAME>    Override the secondary monitor identifier
      --offset <NUMBER>     Override the paired workspace offset (default 10)
      --no-waybar           Skip Waybar refresh
  -h, --help                Show this help message
USAGE
}

owm_cli_paired_explain_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager paired explain [OPTIONS]

Options:
      --primary <NAME>      Override the primary monitor identifier
      --secondary <NAME>    Override the secondary monitor identifier
      --offset <NUMBER>     Override the paired workspace offset (default 10)
      --no-waybar           Skip Waybar refresh
      --json                Emit JSON payload
  -h, --help                Show this help message
USAGE
}

owm_cli_paired_switch() {
	local primary_override=""
	local secondary_override=""
	local offset_override=""
	local no_waybar=0
	local workspace=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--primary)
			primary_override="$2"
			shift 2
			;;
		--primary=*)
			primary_override="${1#*=}"
			shift
			;;
		--secondary)
			secondary_override="$2"
			shift 2
			;;
		--secondary=*)
			secondary_override="${1#*=}"
			shift
			;;
		--offset)
			offset_override="$2"
			shift 2
			;;
		--offset=*)
			offset_override="${1#*=}"
			shift
			;;
		--no-waybar)
			no_waybar=1
			shift
			;;
		-h | --help)
			owm_cli_paired_switch_usage
			return 0
			;;
		--)
			shift
			continue
			;;
		-*)
			owm_die "unknown option '$1'"
			;;
		*)
			if [[ -z "$workspace" ]]; then
				workspace="$1"
			else
				owm_die "unexpected argument '$1'"
			fi
			shift
			continue
			;;
		esac
	done

	if [[ -z "$workspace" ]]; then
		owm_die "workspace argument is required"
	fi

	owm_paired_load_config "$primary_override" "$secondary_override" "$offset_override"
	owm_paired_switch "$workspace" "$no_waybar"
}

owm_cli_paired_cycle() {
	local primary_override=""
	local secondary_override=""
	local offset_override=""
	local no_waybar=0
	local direction=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--primary)
			primary_override="$2"
			shift 2
			;;
		--primary=*)
			primary_override="${1#*=}"
			shift
			;;
		--secondary)
			secondary_override="$2"
			shift 2
			;;
		--secondary=*)
			secondary_override="${1#*=}"
			shift
			;;
		--offset)
			offset_override="$2"
			shift 2
			;;
		--offset=*)
			offset_override="${1#*=}"
			shift
			;;
		--no-waybar)
			no_waybar=1
			shift
			;;
		-h | --help)
			owm_cli_paired_cycle_usage
			return 0
			;;
		--)
			shift
			continue
			;;
		-*)
			owm_die "unknown option '$1'"
			;;
		*)
			if [[ -z "$direction" ]]; then
				direction="$1"
			else
				owm_die "unexpected argument '$1'"
			fi
			shift
			continue
			;;
		esac
	done

	if [[ -z "$direction" ]]; then
		owm_die "direction argument is required"
	fi

	case "$direction" in
	next | prev) ;;
	*) owm_die "direction must be 'next' or 'prev'" ;;
	esac

	owm_paired_load_config "$primary_override" "$secondary_override" "$offset_override"
	owm_paired_cycle "$direction" "$no_waybar"
}

owm_cli_paired_move_window() {
	local primary_override=""
	local secondary_override=""
	local offset_override=""
	local no_waybar=0
	local workspace=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--primary)
			primary_override="$2"
			shift 2
			;;
		--primary=*)
			primary_override="${1#*=}"
			shift
			;;
		--secondary)
			secondary_override="$2"
			shift 2
			;;
		--secondary=*)
			secondary_override="${1#*=}"
			shift
			;;
		--offset)
			offset_override="$2"
			shift 2
			;;
		--offset=*)
			offset_override="${1#*=}"
			shift
			;;
		--no-waybar)
			no_waybar=1
			shift
			;;
		-h | --help)
			owm_cli_paired_move_usage
			return 0
			;;
		--)
			shift
			continue
			;;
		-*)
			owm_die "unknown option '$1'"
			;;
		*)
			if [[ -z "$workspace" ]]; then
				workspace="$1"
			else
				owm_die "unexpected argument '$1'"
			fi
			shift
			continue
			;;
		esac
	done

	if [[ -z "$workspace" ]]; then
		owm_die "workspace argument is required"
	fi

	owm_paired_load_config "$primary_override" "$secondary_override" "$offset_override"
	owm_paired_move_window "$workspace" "$no_waybar"
}

owm_cli_paired_explain() {
	local primary_override=""
	local secondary_override=""
	local offset_override=""
	local json_output=0
	local no_waybar=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--primary)
			primary_override="$2"
			shift 2
			;;
		--primary=*)
			primary_override="${1#*=}"
			shift
			;;
		--secondary)
			secondary_override="$2"
			shift 2
			;;
		--secondary=*)
			secondary_override="${1#*=}"
			shift
			;;
		--offset)
			offset_override="$2"
			shift 2
			;;
		--offset=*)
			offset_override="${1#*=}"
			shift
			;;
		--no-waybar)
			no_waybar=1
			shift
			;;
		--json)
			json_output=1
			shift
			;;
		-h | --help)
			owm_cli_paired_explain_usage
			return 0
			;;
		--)
			shift
			continue
			;;
		-*)
			owm_die "unknown option '$1'"
			;;
		*)
			owm_die "unexpected argument '$1'"
			;;
		esac
	done

	owm_paired_load_config "$primary_override" "$secondary_override" "$offset_override"
	owm_paired_explain "$json_output"
}

owm_cli_paired() {
	if [[ $# -eq 0 ]]; then
		owm_cli_paired_usage
		return 1
	fi

	local subcommand="$1"
	shift || true

	case "$subcommand" in
	help | -h | --help)
		owm_cli_paired_usage
		;;
	switch)
		owm_cli_paired_switch "$@"
		;;
	cycle)
		owm_cli_paired_cycle "$@"
		;;
	move-window)
		owm_cli_paired_move_window "$@"
		;;
	explain)
		owm_cli_paired_explain "$@"
		;;
	*)
		owm_die "unknown paired command '$subcommand'"
		;;
	esac
}
