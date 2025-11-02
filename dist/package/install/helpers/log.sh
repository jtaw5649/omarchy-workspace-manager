#!/usr/bin/env bash

owm_install_info() {
	printf '[install] %s\n' "$*"
}

owm_install_warn() {
	printf '[install][warn] %s\n' "$*" >&2
}

owm_install_error() {
	printf '[install][error] %s\n' "$*" >&2
}

owm_install_die() {
	owm_install_error "$*"
	exit 1
}
