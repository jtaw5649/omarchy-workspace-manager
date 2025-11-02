#!/usr/bin/env bash
set -euo pipefail

log() {
	printf '[uninstall] %s\n' "$*"
}

warn() {
	printf '[uninstall][warn] %s\n' "$*" >&2
}

die() {
	warn "$*"
	exit 1
}

resolve_path() {
	local src="$1"
	if command -v realpath >/dev/null 2>&1; then
		realpath "$src"
	elif command -v readlink >/dev/null 2>&1; then
		readlink -f "$src"
	else
		local dir
		dir="$(cd "$(dirname "$src")" && pwd -P)"
		echo "$dir/$(basename "$src")"
	fi
}

SCRIPT_PATH="$(resolve_path "${BASH_SOURCE[0]:-$0}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT=""
if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
fi
IS_REPO_EXEC=0
if [[ -n "$REPO_ROOT" ]]; then
	IS_REPO_EXEC=1
fi

INSTALL_DEST="${OWM_UNINSTALL_DEST:-$HOME/.local/share/omarchy-workspace-manager}"
BIN_DIR="${OWM_UNINSTALL_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${OWM_UNINSTALL_CONFIG_DIR:-$HOME/.config/omarchy-workspace-manager}"
HYPR_BINDINGS="${OWM_UNINSTALL_HYPR_BINDINGS:-$HOME/.config/hypr/bindings.conf}"
HYPR_AUTOSTART="${OWM_UNINSTALL_HYPR_AUTOSTART:-$HOME/.config/hypr/autostart.conf}"
HYPR_WORKSPACE_CFG="${OWM_UNINSTALL_HYPR_WORKSPACE_CONF:-$HOME/.config/hypr/workspace_manager.conf}"
HYPR_MAIN="${OWM_UNINSTALL_HYPR_MAIN:-$HOME/.config/hypr/hyprland.conf}"

list_known_binaries() {
	local path real
	if [[ -e "$BIN_DIR/omarchy-workspace-manager" ]]; then
		real="$(resolve_path "$BIN_DIR/omarchy-workspace-manager")"
		printf '%s\n' "$real"
		if [[ "$real" != "$BIN_DIR/omarchy-workspace-manager" ]]; then
			printf '%s\n' "$BIN_DIR/omarchy-workspace-manager"
		fi
	fi
	if [[ -d "$INSTALL_DEST" ]]; then
		while IFS= read -r -d '' path; do
			real="$(resolve_path "$path")"
			printf '%s\n' "$real"
			if [[ "$real" != "$path" ]]; then
				printf '%s\n' "$path"
			fi
		done < <(find -L "$INSTALL_DEST" -maxdepth 3 -type f -name 'omarchy-workspace-manager' -print0 2>/dev/null || true)
	fi
	if ((IS_REPO_EXEC == 1)) && [[ -n "$REPO_ROOT" ]]; then
		local repo_bin="$REPO_ROOT/bin/omarchy-workspace-manager"
		if [[ -e "$repo_bin" ]]; then
			local resolved_repo
			resolved_repo="$(resolve_path "$repo_bin")"
			printf '%s\n%s\n' "$resolved_repo" "$repo_bin"
		fi
	fi
}

any_artifacts_present() {
	[[ -e "$BIN_DIR/omarchy-workspace-manager" ]] && return 0
	[[ -d "$INSTALL_DEST" ]] && return 0
	[[ -d "$CONFIG_DIR" ]] && return 0
	if [[ -f "$HYPR_BINDINGS" ]] && grep -q '# BEGIN OMARCHY_WORKSPACE_MANAGER' "$HYPR_BINDINGS"; then
		return 0
	fi
	if [[ -f "$HYPR_AUTOSTART" ]] && grep -q '# BEGIN OMARCHY_WORKSPACE_MANAGER' "$HYPR_AUTOSTART"; then
		return 0
	fi
	[[ -f "$HYPR_WORKSPACE_CFG" ]] && return 0
	grep -q "\$CONFIG_DIR/bindings.conf" "$HYPR_MAIN" 2>/dev/null && return 0
	grep -q "\$CONFIG_DIR/autostart.conf" "$HYPR_MAIN" 2>/dev/null && return 0
	return 1
}

strip_block() {
	local file="$1"
	if [[ -f "$file" ]]; then
		sed -i '/# BEGIN OMARCHY_WORKSPACE_MANAGER/,/# END OMARCHY_WORKSPACE_MANAGER/d' "$file"
	fi
}

remove_main_sources() {
	if [[ -f "$HYPR_MAIN" ]]; then
		sed -i "\|source = $CONFIG_DIR/bindings.conf|d" "$HYPR_MAIN" 2>/dev/null || true
		sed -i "\|source = $CONFIG_DIR/autostart.conf|d" "$HYPR_MAIN" 2>/dev/null || true
	fi
}

stop_processes() {
	if ! command -v pgrep >/dev/null 2>&1; then
		warn "pgrep not available; skipping process termination"
		return
	fi

	local target_paths=()
	while IFS= read -r path; do
		[[ -n "$path" ]] && target_paths+=("$path")
	done < <(list_known_binaries | sort -u)

	if ((${#target_paths[@]} == 0)); then
		return
	fi

	local killed_any=0
	local killed_pids=()
	local pid
	while IFS= read -r pid; do
		[[ -z "$pid" ]] && continue
		local exe
		exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
		local cwd
		cwd="$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)"
		local should_kill=0
		if [[ -n "$exe" ]]; then
			local target
			for target in "${target_paths[@]}"; do
				if [[ "$exe" == "$target" ]]; then
					should_kill=1
					break
				fi
			done
		fi
		local cmd_first=""
		if ((!should_kill)) && [[ -r "/proc/$pid/cmdline" ]]; then
			while IFS= read -r arg; do
				[[ -z "$arg" ]] && continue
				if [[ -z "$cmd_first" ]]; then
					cmd_first="$arg"
				fi
				if [[ "$arg" == "omarchy-workspace-manager" ]]; then
					should_kill=1
					break
				fi
				local target
				for target in "${target_paths[@]}"; do
					if [[ "$arg" == "$target" ]]; then
						should_kill=1
						break 2
					fi
				done
				if ((!should_kill)) && [[ "$arg" == */* ]]; then
					local candidate=""
					if [[ "$arg" == /* ]]; then
						candidate="$(readlink -f "$arg" 2>/dev/null || true)"
					elif [[ -n "$cwd" ]]; then
						candidate="$(readlink -f "$cwd/$arg" 2>/dev/null || true)"
					fi
					if [[ -n "$candidate" ]]; then
						for target in "${target_paths[@]}"; do
							if [[ "$candidate" == "$target" ]]; then
								should_kill=1
								break
							fi
						done
					fi
				fi
			done < <(tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null || true)
		fi
		if ((should_kill == 0)); then
			continue
		fi
		if ((should_kill)); then
			local detail="${exe:-$cmd_first}"
			if [[ -n "$detail" ]]; then
				log "stopping omarchy-workspace-manager process $pid ($detail)"
			else
				log "stopping omarchy-workspace-manager process $pid"
			fi
			if kill "$pid" >/dev/null 2>&1; then
				killed_any=1
				killed_pids+=("$pid")
			else
				warn "failed to stop process $pid"
			fi
		fi
	done < <(pgrep -f 'omarchy-workspace-manager' || true)

	if ((killed_any)); then
		sleep 0.2
		for pid in "${killed_pids[@]}"; do
			if kill -0 "$pid" 2>/dev/null; then
				if kill -9 "$pid" >/dev/null 2>&1; then
					warn "force killed lingering process $pid"
				fi
			fi
		done
	fi
}

remove_wrapper() {
	local wrapper="$BIN_DIR/omarchy-workspace-manager"
	if [[ -e "$wrapper" ]]; then
		rm -f "$wrapper" || warn "unable to remove $wrapper"
	fi
}

remove_install_tree() {
	if [[ -d "$INSTALL_DEST" ]]; then
		rm -rf "$INSTALL_DEST"
	fi
}

remove_config_dir() {
	if [[ -d "$CONFIG_DIR" ]]; then
		rm -rf "$CONFIG_DIR"
	fi
}

remove_hypr_configs() {
	strip_block "$HYPR_BINDINGS"
	strip_block "$HYPR_AUTOSTART"
	remove_main_sources
	if [[ -f "$HYPR_WORKSPACE_CFG" ]]; then
		rm -f "$HYPR_WORKSPACE_CFG"
	fi
}

reload_hypr() {
	if [[ "${OWM_UNINSTALL_SKIP_HYPR_RELOAD:-0}" == "1" ]]; then
		return
	fi
	local hyprctl
	hyprctl="${OWM_UNINSTALL_HYPRCTL:-}"
	if [[ -z "$hyprctl" ]]; then
		hyprctl="$(command -v hyprctl || true)"
	fi
	if [[ -n "$hyprctl" ]]; then
		log "reloading Hyprland configuration"
		"$hyprctl" reload >/dev/null 2>&1 || warn "hyprctl reload failed"
	else
		warn "hyprctl not found; please reload Hyprland manually"
	fi
}

print_summary() {
	printf '\nUninstall complete.\n\n'
	printf 'Removed:\n'
	printf 'Bindings       : %s/bindings.conf\n' "$CONFIG_DIR"
	printf 'Autostart      : %s/autostart.conf\n' "$CONFIG_DIR"
	printf 'Binary symlink : %s/omarchy-workspace-manager\n' "$BIN_DIR"
	printf 'Install root   : %s\n' "$INSTALL_DEST"
	printf 'Current build  : %s/current\n' "$INSTALL_DEST"
	printf 'Config base    : %s\n' "$CONFIG_DIR"
	printf '\n'
}

self_remove() {
	if [[ $IS_REPO_EXEC -eq 1 ]]; then
		return
	fi
	if [[ "${OWM_UNINSTALL_SELF_REMOVE:-1}" != "1" ]]; then
		printf 'Uninstall script retained at %s\n' "$SCRIPT_PATH"
		return
	fi
	rm -f -- "$SCRIPT_PATH" || warn "failed to delete $SCRIPT_PATH"
}

log "starting uninstall"
stop_processes

if ! any_artifacts_present; then
	printf "No Omarchy Workspace Manager files found.\n"
	exit 0
fi

remove_wrapper
remove_install_tree
remove_config_dir
remove_hypr_configs
reload_hypr
print_summary
self_remove
