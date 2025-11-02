#!/usr/bin/env bash
# Setup helpers for installing Omarchy Workspace Manager integrations.

owm_setup_resolve_command() {
	if command -v omarchy-workspace-manager >/dev/null 2>&1; then
		printf '%s' "omarchy-workspace-manager"
		return 0
	fi

	if [[ -x "$OWM_ROOT/bin/omarchy-workspace-manager" ]]; then
		printf '%s' "$OWM_ROOT/bin/omarchy-workspace-manager"
		return 0
	fi

	owm_die "omarchy-workspace-manager command not found; ensure it is installed or set OWM_SETUP_BIN"
}

owm_setup_template_dir() {
	printf '%s' "${OWM_SETUP_TEMPLATES_DIR:-$OWM_TEMPLATES_DIR}"
}

owm_setup_escape_sed() {
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//&/\\&}"
	value="${value//\//\\/}"
	printf '%s' "$value"
}

owm_setup_render_template() {
	local template="$1"
	local bin="$2"
	if [[ ! -f "$template" ]]; then
		owm_die "template not found: $template"
	fi
	local escaped_bin
	escaped_bin="$(owm_setup_escape_sed "$bin")"
	sed "s/__OWM_BIN__/$escaped_bin/g" "$template"
}

owm_setup_confirm_overwrite() {
	local path="$1"
	if [[ ! -e "$path" || "${OWM_SETUP_FORCE:-0}" == "1" ]]; then
		return 0
	fi
	printf 'File %s already exists. Overwrite? [y/N]: ' "$path" >&2
	local answer
	read -r answer || return 1
	case "$answer" in
	y | Y | yes | YES)
		return 0
		;;
	*)
		owm_warn "skipping update for $path"
		return 1
		;;
	esac
}

owm_setup_write_file() {
	local path="$1"
	local content="$2"
	local dir
	dir="$(dirname -- "$path")"
	mkdir -p -- "$dir"
	if ! owm_setup_confirm_overwrite "$path"; then
		return 1
	fi
	umask 077
	printf '%s\n' "$content" >"$path"
	owm_info "wrote $path"
}

owm_setup_remove_file() {
	local path="$1"
	if [[ ! -e "$path" ]]; then
		return 0
	fi
	if [[ "${OWM_SETUP_FORCE:-0}" != "1" ]]; then
		printf 'Remove %s? [y/N]: ' "$path" >&2
		local answer
		read -r answer || return 1
		case "$answer" in
		y | Y | yes | YES) ;;
		*)
			owm_warn "preserving $path"
			return 1
			;;
		esac
	fi
	rm -f -- "$path"
	owm_info "removed $path"
}

owm_setup_install() {
	local base_dir="${OWM_SETUP_BASE_DIR:-$HOME/.config/omarchy-workspace-manager}"
	local bindings_path="${OWM_SETUP_BINDINGS_PATH:-$base_dir/bindings.conf}"
	local autostart_path="${OWM_SETUP_AUTOSTART_PATH:-$base_dir/autostart.conf}"
	local bin_path
	bin_path="${OWM_SETUP_BIN:-$(owm_setup_resolve_command)}"
	local template_dir
	template_dir="$(owm_setup_template_dir)"
	local bindings_template="$template_dir/hypr-bindings.conf"
	local autostart_template="$template_dir/hypr-autostart.conf"

	owm_setup_write_file "$bindings_path" "$(owm_setup_render_template "$bindings_template" "$bin_path")"
	owm_setup_write_file "$autostart_path" "$(owm_setup_render_template "$autostart_template" "$bin_path")"
}

owm_setup_uninstall() {
	local base_dir="${OWM_SETUP_BASE_DIR:-$HOME/.config/omarchy-workspace-manager}"
	local bindings_path="${OWM_SETUP_BINDINGS_PATH:-$base_dir/bindings.conf}"
	local autostart_path="${OWM_SETUP_AUTOSTART_PATH:-$base_dir/autostart.conf}"

	owm_setup_remove_file "$bindings_path"
	owm_setup_remove_file "$autostart_path"
}
