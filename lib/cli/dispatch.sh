#!/usr/bin/env bash
# CLI dispatcher for workspace dispatch operations.

owm_source "lib/dispatch.sh"

owm_cli_dispatch_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager dispatch [OPTIONS]

Options:
      --primary <NAME>      Override the primary monitor identifier
      --secondary <NAME>    Override the secondary monitor identifier
      --offset <NUMBER>     Override the paired workspace offset (default 10)
      --dry-run             Print planned assignments without executing
  -h, --help                Show this help message
USAGE
}

owm_cli_dispatch() {
	local primary_override=""
	local secondary_override=""
	local offset_override=""
	local dry_run=0

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
		--dry-run)
			dry_run=1
			shift
			;;
		-h | --help)
			owm_cli_dispatch_usage
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

	owm_dispatch_run "$dry_run" "$primary_override" "$secondary_override" "$offset_override"
}
