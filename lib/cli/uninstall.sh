#!/usr/bin/env bash
# CLI dispatcher for uninstall operations.

owm_cli_uninstall_usage() {
	cat <<'USAGE'
Usage: omarchy-workspace-manager uninstall [--help]

Removes Omarchy Workspace Manager files by delegating to scripts/uninstall.sh.
USAGE
}

owm_cli_uninstall() {
	if [[ $# -gt 0 ]]; then
		case "$1" in
		-h | --help)
			owm_cli_uninstall_usage
			return 0
			;;
		*)
			owm_die "unexpected argument '$1'"
			;;
		esac
	fi

	local uninstall_script="$OWM_ROOT/scripts/uninstall.sh"
	if [[ ! -x "$uninstall_script" ]]; then
		owm_die "uninstall script missing at $uninstall_script"
	fi

	exec "$uninstall_script"
}
