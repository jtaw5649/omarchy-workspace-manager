#!/usr/bin/env bash

# shellcheck source=install/helpers/log.sh
source "${OWM_INSTALL_ROOT}/install/helpers/log.sh"

owm_install_ensure_dir() {
	local dir="$1"
	mkdir -p "$dir"
}
