#!/usr/bin/env bash
# Core bootstrap for the Omarchy Workspace Manager shell migration.
# Resolves project roots, exports shared paths, and provides common helpers.

set -euo pipefail
IFS=$'\n\t'

_owm_resolve_root() {
	local source="${BASH_SOURCE[0]}"
	while [[ -L "$source" ]]; do
		local dir
		dir="$(cd -P -- "$(dirname -- "$source")" && pwd)"
		source="$(readlink "$source")"
		[[ "$source" != /* ]] && source="$dir/$source"
	done
	local script_dir
	script_dir="$(cd -P -- "$(dirname -- "$source")" && pwd)"
	cd -P -- "$script_dir/.." >/dev/null && pwd
}

if [[ -z "${OWM_ROOT:-}" ]]; then
	OWM_ROOT="$(_owm_resolve_root)"
	export OWM_ROOT
fi

export OWM_CONFIG_PATH="${OWM_CONFIG_PATH:-$OWM_ROOT/config/paired.json}"
export OWM_STATE_DIR="${OWM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-workspace-manager}"
export OWM_LOG_DIR="${OWM_LOG_DIR:-$OWM_STATE_DIR/logs}"
export OWM_RUNTIME_DIR="${OWM_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}/omarchy-workspace-manager}"
export OWM_BIN_DIR="${OWM_BIN_DIR:-$OWM_ROOT/bin}"
export OWM_TEMPLATES_DIR="${OWM_TEMPLATES_DIR:-$OWM_ROOT/config}"

owm_require_command() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		owm_die "required command '$cmd' not found in PATH"
	fi
}

owm_ensure_dir() {
	local path="$1"
	mkdir -p -- "$path"
}

owm_now_iso_8601() {
	if date -u '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
		date -u '+%Y-%m-%dT%H:%M:%SZ'
	else
		date '+%Y-%m-%dT%H:%M:%SZ'
	fi
}

owm_json_escape() {
	local raw="$1"
	raw=${raw//\\/\\\\}
	raw=${raw//\"/\\\"}
	raw=${raw//$'\n'/\\n}
	raw=${raw//$'\r'/\\r}
	raw=${raw//$'\t'/\\t}
	printf '%s' "$raw"
}

owm_log() {
	local level="$1"
	shift || true
	local message="$*"
	local timestamp
	timestamp="$(owm_now_iso_8601)"
	case "$level" in
	DEBUG)
		[[ "${OWM_DEBUG:-0}" == "1" ]] || return 0
		;;
	INFO)
		[[ "${OWM_DEBUG:-0}" == "1" ]] || return 0
		;;
	WARN | ERROR) ;;
	*)
		level="INFO"
		[[ "${OWM_DEBUG:-0}" == "1" ]] || return 0
		;;
	esac
	if [[ "${OWM_LOG_JSON:-0}" == "1" || "${OWM_LOG_FORMAT:-}" == "json" ]]; then
		local escaped
		escaped="$(owm_json_escape "$message")"
		printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' "$timestamp" "$level" "$escaped" >&2
	else
		printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >&2
	fi
}

owm_info() {
	owm_log "INFO" "$*"
}
owm_warn() {
	owm_log "WARN" "$*"
}
owm_error() {
	owm_log "ERROR" "$*"
}
owm_debug() {
	owm_log "DEBUG" "$*"
}

owm_die() {
	local message="$*"
	owm_error "$message"
	exit 1
}

owm_source() {
	local relative_path="$1"
	# shellcheck disable=SC1090
	source "$OWM_ROOT/$relative_path"
}

owm_validate_runtime() {
	local hypr_bin
	if [[ -n "${OWM_HYPRCTL_BIN:-}" ]]; then
		hypr_bin="$OWM_HYPRCTL_BIN"
	elif [[ -n "${OWM_HYPRCTL:-}" ]]; then
		hypr_bin="$OWM_HYPRCTL"
	else
		hypr_bin="hyprctl"
	fi

	local -a required=("bash" "jq" "$hypr_bin")
	local cmd
	for cmd in "${required[@]}"; do
		owm_require_command "$cmd"
	done
	owm_ensure_dir "$OWM_RUNTIME_DIR"
	owm_ensure_dir "$OWM_STATE_DIR"
	owm_ensure_dir "$OWM_LOG_DIR"
}
