#!/usr/bin/env bash
# CLI dispatcher for daemon operations.

owm_source "lib/daemon.sh"

owm_cli_daemon_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager daemon [OPTIONS]

Options:
      --poll-interval <SECONDS>  Polling interval for monitor checks (default 0.2s)
      --primary <NAME>           Override primary monitor identifier
      --secondary <NAME>         Override secondary monitor identifier
      --offset <NUMBER>          Override paired workspace offset (default 10)
  -h, --help                     Show this help message
USAGE
}

owm_cli_daemon() {
	local poll_interval=""
	local primary_override=""
	local secondary_override=""
	local offset_override=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--poll-interval)
			poll_interval="$2"
			shift 2
			;;
		--poll-interval=*)
			poll_interval="${1#*=}"
			shift
			;;
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
		-h | --help)
			owm_cli_daemon_usage
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

	if [[ -n "$primary_override" ]]; then
		export OWM_DAEMON_PRIMARY_OVERRIDE="$primary_override"
	fi
	if [[ -n "$secondary_override" ]]; then
		export OWM_DAEMON_SECONDARY_OVERRIDE="$secondary_override"
	fi
	if [[ -n "$offset_override" ]]; then
		export OWM_DAEMON_OFFSET_OVERRIDE="$offset_override"
	fi

	if [[ -n "$poll_interval" ]]; then
		owm_daemon_run "$poll_interval"
	else
		owm_daemon_run
	fi
}
