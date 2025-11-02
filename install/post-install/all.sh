#!/usr/bin/env bash

owm_install_restart_daemon() {
	local binary="$OWM_INSTALL_BIN_DIR/omarchy-workspace-manager"
	if [[ ! -x "$binary" ]]; then
		owm_install_warn "daemon restart skipped; missing $binary"
		return
	fi

	local resolved_binary
	resolved_binary="$(readlink -f "$binary" 2>/dev/null || printf '%s' "$binary")"

	local stopped_count=0
	if command -v pgrep >/dev/null 2>&1; then
		local -a stop_pids=()
		while IFS= read -r pid; do
			[[ -z "$pid" ]] && continue
			local exe
			exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
			if [[ -n "$exe" && "$exe" == "$resolved_binary" ]]; then
				stop_pids+=("$pid")
			fi
		done < <(pgrep -f 'omarchy-workspace-manager daemon' || true)

		if ((${#stop_pids[@]} > 0)); then
			owm_install_info "stopping existing daemon (${#stop_pids[@]} instance(s))"
			kill "${stop_pids[@]}" >/dev/null 2>&1 || true
			sleep 0.2
			local pid
			for pid in "${stop_pids[@]}"; do
				if kill -0 "$pid" 2>/dev/null; then
					kill -9 "$pid" >/dev/null 2>&1 || true
				fi
			done
			stopped_count=${#stop_pids[@]}
		fi
	fi

	"$binary" daemon >/dev/null 2>&1 &
	local new_pid=$!
	if ((stopped_count > 0)); then
		owm_install_info "daemon relaunched (pid $new_pid)"
	else
		owm_install_info "daemon launched (pid $new_pid)"
	fi
}

owm_install_summary() {
	local workspace_rules="$OWM_INSTALL_CONFIG_DIR/workspace-rules.conf"
	local state_dir="${OWM_INSTALL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-workspace-manager}"
	local log_dir="${OWM_INSTALL_LOG_DIR:-$state_dir/logs}"
	local log_file="${OWM_INSTALL_LOG_FILE:-$log_dir/hyprctl.log}"

	cat <<SUMMARY

Installation complete.

Bindings       : $OWM_INSTALL_CONFIG_DIR/bindings.conf
Autostart      : $OWM_INSTALL_CONFIG_DIR/autostart.conf
Workspace rules: $workspace_rules
Binary symlink : $OWM_INSTALL_BIN_DIR/omarchy-workspace-manager
Install root   : $OWM_INSTALL_DEST
Current build  : $OWM_INSTALL_DEST/current
Config base    : $OWM_INSTALL_CONFIG_DIR
Logs           : $log_file
SUMMARY
}
