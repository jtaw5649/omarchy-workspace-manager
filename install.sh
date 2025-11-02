#!/usr/bin/env bash
set -euo pipefail

OWM_INSTALL_TEMP_ROOT=""

owm_install_bootstrap_remote() {
	local temp_dir tarball_url archive_dir fetch_cmd
	if [[ -n "${OWM_INSTALL_TARBALL_URL:-}" ]]; then
		tarball_url="$OWM_INSTALL_TARBALL_URL"
	else
		tarball_url="https://github.com/jtaw5649/omarchy-workspace-manager/archive/refs/heads/master.tar.gz"
	fi

	temp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t owm_install)"
	if [[ -z "$temp_dir" ]]; then
		echo "error: unable to create temporary directory" >&2
		return 1
	fi

	if command -v curl >/dev/null 2>&1; then
		fetch_cmd=(curl -fsSL "$tarball_url")
	elif command -v wget >/dev/null 2>&1; then
		fetch_cmd=(wget -qO- "$tarball_url")
	else
		echo "error: curl or wget is required to download installer payload" >&2
		return 1
	fi

	if ! "${fetch_cmd[@]}" | tar -xz -C "$temp_dir"; then
		echo "error: failed to download and extract installer payload" >&2
		return 1
	fi

	archive_dir="$(find "$temp_dir" -maxdepth 1 -mindepth 1 -type d -name 'omarchy-workspace-manager*' | head -n 1)"
	if [[ -z "$archive_dir" ]]; then
		archive_dir="$temp_dir"
	fi

	if [[ ! -f "$archive_dir/install.sh" ]]; then
		echo "error: installer payload missing install.sh" >&2
		return 1
	fi

	OWM_INSTALL_TEMP_ROOT="$temp_dir"
	printf '%s\n' "$archive_dir"
}

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
	SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
fi

if [[ -z "$SCRIPT_DIR" && -n "${OWM_INSTALL_ROOT:-}" && -d "$OWM_INSTALL_ROOT" ]]; then
	SCRIPT_DIR="$(cd -- "$OWM_INSTALL_ROOT" >/dev/null 2>&1 && pwd -P)"
fi

if [[ -z "$SCRIPT_DIR" ]]; then
	SCRIPT_DIR="$(owm_install_bootstrap_remote)" || exit 1
fi

if [[ -z "$SCRIPT_DIR" ]]; then
	echo "error: unable to determine installer directory" >&2
	exit 1
fi

if [[ -n "$OWM_INSTALL_TEMP_ROOT" ]]; then
	cleanup_owm_install() {
		rm -rf "$OWM_INSTALL_TEMP_ROOT"
	}
	trap cleanup_owm_install EXIT
fi

export OWM_INSTALL_ROOT="$SCRIPT_DIR"
export OWM_INSTALL_DEST="${OWM_INSTALL_DEST:-$HOME/.local/share/omarchy-workspace-manager}"
export OWM_INSTALL_BIN_DIR="${OWM_INSTALL_BIN_DIR:-$HOME/.local/bin}"
export OWM_INSTALL_CONFIG_DIR="${OWM_INSTALL_CONFIG_DIR:-$HOME/.config/omarchy-workspace-manager}"

owm_install_detect_version() {
	if [[ -n "${OWM_INSTALL_VERSION:-}" ]]; then
		printf '%s\n' "$OWM_INSTALL_VERSION"
	elif [[ -f "$OWM_INSTALL_ROOT/version" ]]; then
		tr -d '[:space:]' <"$OWM_INSTALL_ROOT/version"
	elif [[ -f "$OWM_INSTALL_ROOT/VERSION" ]]; then
		tr -d '[:space:]' <"$OWM_INSTALL_ROOT/VERSION"
	else
		date '+dev-%Y%m%d%H%M%S'
	fi
}

OWM_INSTALL_VERSION="$(owm_install_detect_version)"
export OWM_INSTALL_VERSION

# shellcheck source=install/helpers/all.sh
source "$OWM_INSTALL_ROOT/install/helpers/all.sh"
# shellcheck source=install/preflight/all.sh
source "$OWM_INSTALL_ROOT/install/preflight/all.sh"
# shellcheck source=install/packaging/all.sh
source "$OWM_INSTALL_ROOT/install/packaging/all.sh"
# shellcheck source=install/config/all.sh
source "$OWM_INSTALL_ROOT/install/config/all.sh"
# shellcheck source=install/post-install/all.sh
source "$OWM_INSTALL_ROOT/install/post-install/all.sh"

owm_install_ensure_dir "$OWM_INSTALL_DEST"
owm_install_ensure_dir "$OWM_INSTALL_BIN_DIR"
owm_install_ensure_dir "$OWM_INSTALL_CONFIG_DIR"

owm_install_preflight
owm_install_stage_files "$OWM_INSTALL_VERSION"
owm_install_configure_paired
owm_install_apply_config
owm_install_restart_daemon
owm_install_summary
