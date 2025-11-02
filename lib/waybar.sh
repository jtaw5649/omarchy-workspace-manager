#!/usr/bin/env bash
# Waybar signalling helpers.

owm_waybar_refresh() {
	local signal="${OWM_WAYBAR_SIGNAL:-RTMIN+5}"
	local bin="${OWM_WAYBAR_NOTIFIER:-pkill}"

	if ! command -v "$bin" >/dev/null 2>&1; then
		owm_warn "skipping Waybar refresh; notifier '$bin' unavailable"
		return 0
	fi

	"$bin" -"$signal" waybar >/dev/null 2>&1 || true
}
