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

owm_setup_monitor_identifier() {
	local name="$1"
	local descriptor="$2"
	if [[ -n "$descriptor" ]]; then
		printf 'desc:%s' "$descriptor"
	elif [[ -n "$name" ]]; then
		printf '%s' "$name"
	else
		printf ''
	fi
}

owm_setup_collect_numeric_group() {
	local config_path="$1"
	local jq_path="$2"
	local -a group=()
	if mapfile -t group < <(jq -r "$jq_path | map(select(. != null)) | map(tonumber)[]?" "$config_path" 2>/dev/null); then
		printf '%s\n' "${group[@]}"
	else
		return 1
	fi
}

owm_setup_range_segments() {
	local -n values_ref="$1"
	if ((${#values_ref[@]} == 0)); then
		return 0
	fi
	local -a sorted=()
	mapfile -t sorted < <(printf '%s\n' "${values_ref[@]}" | LC_ALL=C sort -n | uniq)
	local start=""
	local prev=""
	local value
	for value in "${sorted[@]}"; do
		if [[ -z "$start" ]]; then
			start="$value"
			prev="$value"
			continue
		fi
		if ((value == prev + 1)); then
			prev="$value"
		else
			if [[ "$start" == "$prev" ]]; then
				printf '%s\n' "$start"
			else
				printf '%s-%s\n' "$start" "$prev"
			fi
			start="$value"
			prev="$value"
		fi
	done
	if [[ -n "$start" ]]; then
		if [[ "$start" == "$prev" ]]; then
			printf '%s\n' "$start"
		else
			printf '%s-%s\n' "$start" "$prev"
		fi
	fi
}

owm_setup_generate_workspace_rules() {
	local config_path="${OWM_CONFIG_PATH:-$OWM_ROOT/config/paired.json}"
	if [[ ! -f "$config_path" ]]; then
		owm_die "paired configuration not found at $config_path; cannot build workspace rules"
	fi

	local primary_monitor
	local secondary_monitor
	local primary_desc
	local secondary_desc
	local offset
	primary_monitor="$(jq -r '.primary_monitor // empty' "$config_path" 2>/dev/null || true)"
	secondary_monitor="$(jq -r '.secondary_monitor // empty' "$config_path" 2>/dev/null || true)"
	primary_desc="$(jq -r '.primary_descriptor // empty' "$config_path" 2>/dev/null || true)"
	secondary_desc="$(jq -r '.secondary_descriptor // empty' "$config_path" 2>/dev/null || true)"
	offset="$(jq -r '.paired_offset // empty' "$config_path" 2>/dev/null || true)"
	if [[ -z "$offset" || ! "$offset" =~ ^[0-9]+$ || "$offset" == "0" ]]; then
		offset=10
	fi

	local -a primary_group=()
	local -a secondary_group=()
	if ! mapfile -t primary_group < <(owm_setup_collect_numeric_group "$config_path" '.workspace_groups.primary // []'); then
		primary_group=()
	fi
	if ((${#primary_group[@]} == 0)); then
		local i
		for ((i = 1; i <= offset; i++)); do
			primary_group+=("$i")
		done
	fi

	if ! mapfile -t secondary_group < <(owm_setup_collect_numeric_group "$config_path" '.workspace_groups.secondary // []'); then
		secondary_group=()
	fi
	if ((${#secondary_group[@]} == 0)); then
		local value
		for value in "${primary_group[@]}"; do
			secondary_group+=("$((value + offset))")
		done
	fi

	local primary_identifier
	local secondary_identifier
	primary_identifier="$(owm_setup_monitor_identifier "$primary_monitor" "$primary_desc")"
	secondary_identifier="$(owm_setup_monitor_identifier "$secondary_monitor" "$secondary_desc")"
	if [[ -z "$primary_identifier" && -n "$secondary_identifier" ]]; then
		primary_identifier="$secondary_identifier"
	fi
	if [[ -z "$secondary_identifier" && -n "$primary_identifier" ]]; then
		secondary_identifier="$primary_identifier"
	fi
	if [[ -z "$primary_identifier" && -n "$primary_monitor" ]]; then
		primary_identifier="$primary_monitor"
	fi
	if [[ -z "$secondary_identifier" && -n "$secondary_monitor" ]]; then
		secondary_identifier="$secondary_monitor"
	fi

	local primary_default="${primary_group[0]}"
	local secondary_default="${secondary_group[0]}"

	local content=""
	content+="# Autogenerated by Omarchy Workspace Manager\n"
	content+="# Update config/paired.json and rerun setup install to regenerate.\n\n"

	local -a primary_ranges=()
	local -a secondary_ranges=()
	mapfile -t primary_ranges < <(owm_setup_range_segments primary_group)
	mapfile -t secondary_ranges < <(owm_setup_range_segments secondary_group)

	local range
	for range in "${primary_ranges[@]}"; do
		if [[ "$range" == *"-"* ]]; then
			content+="workspace = r[$range], monitor:${primary_identifier}, persistent:true\n"
		else
			content+="workspace = $range, monitor:${primary_identifier}, persistent:true\n"
		fi
	done
	if [[ -n "$secondary_identifier" ]]; then
		for range in "${secondary_ranges[@]}"; do
			if [[ "$range" == *"-"* ]]; then
				content+="workspace = r[$range], monitor:${secondary_identifier}, persistent:true\n"
			else
				content+="workspace = $range, monitor:${secondary_identifier}, persistent:true\n"
			fi
		done
	fi

	if [[ -n "$primary_default" ]]; then
		content+="workspace = $primary_default, monitor:${primary_identifier}, default:true\n"
	fi
	if [[ -n "$secondary_identifier" && -n "$secondary_default" ]]; then
		content+="workspace = $secondary_default, monitor:${secondary_identifier}, default:true\n"
	fi

	printf '%s\n' "$content"
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

	local workspace_rules_enabled="${OWM_SETUP_WORKSPACE_RULES:-1}"
	if [[ "$workspace_rules_enabled" != "0" ]]; then
		local workspace_rules_path="${OWM_SETUP_WORKSPACE_RULES_PATH:-$base_dir/workspace-rules.conf}"
		owm_setup_write_file "$workspace_rules_path" "$(owm_setup_generate_workspace_rules)"
	fi
}

owm_setup_uninstall() {
	local base_dir="${OWM_SETUP_BASE_DIR:-$HOME/.config/omarchy-workspace-manager}"
	local bindings_path="${OWM_SETUP_BINDINGS_PATH:-$base_dir/bindings.conf}"
	local autostart_path="${OWM_SETUP_AUTOSTART_PATH:-$base_dir/autostart.conf}"
	local workspace_rules_path="${OWM_SETUP_WORKSPACE_RULES_PATH:-$base_dir/workspace-rules.conf}"

	owm_setup_remove_file "$bindings_path"
	owm_setup_remove_file "$autostart_path"
	if [[ "${OWM_SETUP_WORKSPACE_RULES:-1}" != "0" ]]; then
		owm_setup_remove_file "$workspace_rules_path"
	fi
}
