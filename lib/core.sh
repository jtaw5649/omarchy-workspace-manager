#!/usr/bin/env bash
set -euo pipefail

_owm_resolve_root() {
	local source="${BASH_SOURCE[0]}"
	while [[ -L "$source" ]]; do
		local dir="$(cd -P "$(dirname "$source")" && pwd)"
		source="$(readlink "$source")"
		[[ "$source" != /* ]] && source="$dir/$source"
	done
	cd -P "$(dirname "$source")/.." && pwd
}

OWM_ROOT="${OWM_ROOT:-$(_owm_resolve_root)}"
OWM_CONFIG_PATH="${OWM_CONFIG_PATH:-$OWM_ROOT/config/paired.json}"
export OWM_ROOT OWM_CONFIG_PATH

owm_die() { printf 'error: %s\n' "$*" >&2; exit 1; }
owm_source() { source "$OWM_ROOT/$1"; }
