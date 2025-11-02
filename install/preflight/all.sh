#!/usr/bin/env bash

owm_install_preflight() {
	owm_install_info "running preflight checks"
	local -a required=(bash jq tar pgrep pkill)
	local cmd
	for cmd in "${required[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			owm_install_die "required command '$cmd' not found"
		fi
	done

	if ! command -v hyprctl >/dev/null 2>&1; then
		owm_install_die "hyprctl not found; please install Hyprland utilities before running the installer"
	fi
}
