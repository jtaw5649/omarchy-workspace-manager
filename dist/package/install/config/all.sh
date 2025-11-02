#!/usr/bin/env bash

append_source_block() {
	local file="$1"
	local include="$2"
	if [[ ! -f "$file" ]]; then
		touch "$file"
	fi
	sed -i '/# BEGIN OMARCHY_WORKSPACE_MANAGER/,/# END OMARCHY_WORKSPACE_MANAGER/d' "$file"
	if [[ -s "$file" && $(tail -c1 "$file") != $'\n' ]]; then
		echo >>"$file"
	fi
	cat >>"$file" <<EOF_INNER
# BEGIN OMARCHY_WORKSPACE_MANAGER
source = $include
# END OMARCHY_WORKSPACE_MANAGER
EOF_INNER
}

owm_install_update_main_source() {
	local file="$1"
	local line="$2"
	if [[ ! -f "$file" ]]; then
		touch "$file"
	fi
	if ! grep -Fxq "$line" "$file"; then
		echo "$line" >>"$file"
	fi
}

owm_install_update_hypr_sources() {
	local bindings_source="$OWM_INSTALL_CONFIG_DIR/bindings.conf"
	local autostart_source="$OWM_INSTALL_CONFIG_DIR/autostart.conf"
	local bindings_file="${OWM_INSTALL_HYPR_BINDINGS:-$HOME/.config/hypr/bindings.conf}"
	local autostart_file="${OWM_INSTALL_HYPR_AUTOSTART:-$HOME/.config/hypr/autostart.conf}"

	append_source_block "$bindings_file" "$bindings_source"
	append_source_block "$autostart_file" "$autostart_source"

	local main_config="${OWM_INSTALL_HYPR_MAIN:-$HOME/.config/hypr/hyprland.conf}"
	if [[ -f "$main_config" ]]; then
		owm_install_update_main_source "$main_config" "source = $bindings_source"
		owm_install_update_main_source "$main_config" "source = $autostart_source"
	else
		owm_install_warn "Hyprland main config $main_config missing; skipping source injection"
	fi
}

owm_install_reload_hypr() {
	local hyprctl
	hyprctl="${OWM_INSTALL_HYPRCTL:-}"
	if [[ -z "$hyprctl" ]]; then
		hyprctl="$(command -v hyprctl || true)"
	fi
	if [[ -n "$hyprctl" ]]; then
		owm_install_info "reloading Hyprland configuration"
		"$hyprctl" reload >/dev/null 2>&1 || owm_install_warn "hyprctl reload failed"
	else
		owm_install_warn "hyprctl not found; please restart Hyprland manually"
	fi
}

owm_install_configure_paired() {
	local version_dir="${OWM_INSTALL_VERSION_DIR:-}"
	if [[ -z "$version_dir" || ! -d "$version_dir" ]]; then
		owm_install_warn "version directory unavailable; skipping paired workspace autoconfig"
		return 0
	fi

	local config_path="$version_dir/config/paired.json"
	if [[ ! -f "$config_path" ]]; then
		owm_install_warn "paired configuration missing at $config_path; skipping autoconfig"
		return 0
	fi

	local hyprctl
	hyprctl="${OWM_INSTALL_HYPRCTL:-}"
	if [[ -z "$hyprctl" ]]; then
		hyprctl="$(command -v hyprctl || true)"
	fi
	if [[ -z "$hyprctl" ]]; then
		owm_install_warn "hyprctl not found; keeping packaged paired config"
		return 0
	fi

	local monitors_raw monitors_json
	if ! monitors_raw="$("$hyprctl" monitors -j 2>/dev/null)"; then
		owm_install_warn "hyprctl monitors failed; keeping packaged paired config"
		return 0
	fi

	if ! monitors_json="$(printf '%s\n' "$monitors_raw" | jq 'map(select((.name // "") != "" or (.description // "") != ""))' 2>/dev/null)"; then
		owm_install_warn "unable to parse hyprctl monitors output; keeping packaged paired config"
		return 0
	fi

	local monitor_count
	monitor_count="$(printf '%s\n' "$monitors_json" | jq 'length' 2>/dev/null)" || monitor_count="0"
	if ! [[ "$monitor_count" =~ ^[0-9]+$ ]] || ((monitor_count == 0)); then
		owm_install_warn "no identifiable monitors detected; keeping packaged paired config"
		return 0
	fi

	local config_json
	if ! config_json="$(jq -n --argjson monitors "$monitors_json" '
		def sorted: ($monitors | sort_by((.x // 0), (.id // 0)));
		def pick(idx):
			(sorted | if length > idx then .[idx] else (if length > 0 then .[length - 1] else {} end) end);
		def name_of(m):
			if (m | type) == "object" then
				if (m.name // "") != "" then m.name
				elif (m.description // "") != "" then m.description
				else ""
				end
			else ""
			end;
		def desc_of(m):
			if (m | type) == "object" then (m.description // "") else "" end;
		def null_if_empty(s): if s == "" then null else s end;
		{
			primary_monitor: name_of(pick(0)),
			primary_descriptor: null_if_empty(desc_of(pick(0))),
			secondary_monitor: name_of(pick(1)),
			secondary_descriptor: null_if_empty(desc_of(pick(1))),
			paired_offset: 10,
			workspace_groups: {
				primary: [range(1; 11)],
				secondary: [range(11; 21)]
			}
		}
	' 2>/dev/null)"; then
		owm_install_warn "failed to build paired configuration; keeping packaged defaults"
		return 0
	fi

	local config_dir tmp
	config_dir="$(dirname "$config_path")"
	if ! tmp="$(mktemp "$config_dir/paired.json.XXXXXX")"; then
		owm_install_warn "unable to create temporary config; keeping packaged paired config"
		return 0
	fi

	if ! printf '%s\n' "$config_json" | jq '.' >"$tmp" 2>/dev/null; then
		rm -f "$tmp"
		owm_install_warn "failed to write paired configuration; keeping packaged defaults"
		return 0
	fi
	mv "$tmp" "$config_path"

	local primary_monitor primary_desc secondary_monitor secondary_desc
	primary_monitor="$(printf '%s\n' "$config_json" | jq -r '.primary_monitor')"
	primary_desc="$(printf '%s\n' "$config_json" | jq -r '.primary_descriptor // empty')"
	secondary_monitor="$(printf '%s\n' "$config_json" | jq -r '.secondary_monitor')"
	secondary_desc="$(printf '%s\n' "$config_json" | jq -r '.secondary_descriptor // empty')"

	if [[ -z "$primary_monitor" && -n "$primary_desc" ]]; then
		primary_monitor="$primary_desc"
	fi
	if [[ -z "$secondary_monitor" && -n "$secondary_desc" ]]; then
		secondary_monitor="$secondary_desc"
	fi

	local primary_label="$primary_monitor"
	if [[ -n "$primary_desc" && "$primary_desc" != "$primary_monitor" ]]; then
		primary_label+=" ($primary_desc)"
	fi
	local secondary_label="$secondary_monitor"
	if [[ -n "$secondary_desc" && "$secondary_desc" != "$secondary_monitor" ]]; then
		secondary_label+=" ($secondary_desc)"
	fi

	owm_install_info "configured paired workspaces for $primary_label ↔ $secondary_label"
}

owm_install_apply_config() {
	local binary="$OWM_INSTALL_BIN_DIR/omarchy-workspace-manager"
	local base_dir="$OWM_INSTALL_CONFIG_DIR"

	if [[ -x "$binary" ]]; then
		owm_install_info "generating Hyprland fragments via setup install"
		OWM_SETUP_SILENT=1 "$binary" setup install --base-dir "$base_dir" --yes
	else
		owm_install_die "unable to locate $binary for setup install"
	fi

	owm_install_update_hypr_sources

	if [[ "${OWM_INSTALL_SKIP_HYPR_RELOAD:-0}" != "1" ]]; then
		owm_install_reload_hypr
	fi
}
