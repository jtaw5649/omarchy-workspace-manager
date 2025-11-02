#!/usr/bin/env bash
# Paired workspace helpers powering the `paired` CLI.

owm_source "lib/hypr.sh"
owm_source "lib/waybar.sh"

owm_paired_load_config() {
	local primary_override="${1:-}"
	local secondary_override="${2:-}"
	local offset_override="${3:-}"

	if [[ ! -f "$OWM_CONFIG_PATH" ]]; then
		owm_die "missing paired configuration at $OWM_CONFIG_PATH"
	fi

	local primary secondary offset primary_desc secondary_desc
	primary="$(jq -r '.primary_monitor // empty' "$OWM_CONFIG_PATH")"
	secondary="$(jq -r '.secondary_monitor // empty' "$OWM_CONFIG_PATH")"
	offset="$(jq -r '.paired_offset // empty' "$OWM_CONFIG_PATH")"
	primary_desc="$(jq -r '.primary_descriptor // empty' "$OWM_CONFIG_PATH")"
	secondary_desc="$(jq -r '.secondary_descriptor // empty' "$OWM_CONFIG_PATH")"

	if [[ -n "$primary_override" ]]; then
		primary="$primary_override"
	fi
	if [[ -n "$secondary_override" ]]; then
		secondary="$secondary_override"
	fi
	if [[ -n "$offset_override" ]]; then
		offset="$offset_override"
	fi

	if [[ -z "$primary" || -z "$secondary" ]]; then
		owm_die "paired configuration must define both primary and secondary monitors"
	fi

	if [[ -z "$offset" ]]; then
		offset=10
	fi
	if ! [[ "$offset" =~ ^[0-9]+$ ]] || ((offset <= 0)); then
		owm_die "invalid paired offset '$offset'"
	fi

	local -a primary_group=()
	local -a secondary_group=()

	if ! readarray -t primary_group < <(jq -r '(.workspace_groups.primary // []) | map(tostring)[]' "$OWM_CONFIG_PATH"); then
		owm_die "failed to parse primary workspace assignments"
	fi
	if ! readarray -t secondary_group < <(jq -r '(.workspace_groups.secondary // []) | map(tostring)[]' "$OWM_CONFIG_PATH"); then
		owm_die "failed to parse secondary workspace assignments"
	fi

	if ((${#primary_group[@]} == 0)); then
		for ((i = 1; i <= offset; i++)); do
			primary_group+=("$i")
		done
	fi

	if ((${#secondary_group[@]} == 0)); then
		for workspace in "${primary_group[@]}"; do
			if [[ "$workspace" =~ ^-?[0-9]+$ ]]; then
				secondary_group+=("$((workspace + offset))")
			fi
		done
	fi

	if ((${#primary_group[@]} == 0)); then
		owm_die "no primary workspace assignments configured"
	fi
	if ((${#secondary_group[@]} == 0)); then
		owm_die "no secondary workspace assignments configured"
	fi

	export OWM_PAIRED_PRIMARY="$primary"
	export OWM_PAIRED_SECONDARY="$secondary"
	export OWM_PAIRED_OFFSET="$offset"
	export OWM_PAIRED_PRIMARY_DESC="$primary_desc"
	export OWM_PAIRED_SECONDARY_DESC="$secondary_desc"
	# shellcheck disable=SC2034 # referenced via nameref in dispatch helpers
	declare -g -a OWM_PAIRED_PRIMARY_GROUP=("${primary_group[@]}")
	# shellcheck disable=SC2034 # referenced via nameref in dispatch helpers
	declare -g -a OWM_PAIRED_SECONDARY_GROUP=("${secondary_group[@]}")
}

owm_paired_normalize_workspace() {
	local requested="$1"
	local offset="$2"
	if ((offset <= 0)); then
		printf '%s\n' "$requested"
		return 0
	fi
	local mod=$((((requested - 1) % offset) + 1))
	printf '%s\n' "$mod"
}

owm_paired_plan_switch() {
	local requested="$1"
	local offset="$OWM_PAIRED_OFFSET"
	local normalized
	normalized="$(owm_paired_normalize_workspace "$requested" "$offset")"
	export OWM_PAIRED_PRIMARY_WORKSPACE="$normalized"
	export OWM_PAIRED_SECONDARY_WORKSPACE="$((normalized + offset))"
}

owm_paired_execute_switch() {
	local primary="$OWM_PAIRED_PRIMARY"
	local secondary="$OWM_PAIRED_SECONDARY"
	local primary_ws="$OWM_PAIRED_PRIMARY_WORKSPACE"
	local secondary_ws="$OWM_PAIRED_SECONDARY_WORKSPACE"
	local initial_monitor=""

	initial_monitor="$(owm_hypr_focused_monitor)" || initial_monitor=""

	if [[ "$secondary" != "$primary" ]]; then
		owm_hypr_dispatch focusmonitor "$secondary"
		owm_hypr_dispatch workspace "$secondary_ws"
	fi
	owm_hypr_dispatch focusmonitor "$primary"
	owm_hypr_dispatch workspace "$primary_ws"

	if [[ -n "$initial_monitor" && "$initial_monitor" != "$primary" ]]; then
		owm_hypr_dispatch focusmonitor "$initial_monitor"
	fi
}

owm_paired_switch() {
	local requested="$1"
	local skip_waybar="${2:-0}"

	if ! [[ "$requested" =~ ^[0-9]+$ ]]; then
		owm_die "workspace must be numeric"
	fi

	owm_paired_plan_switch "$requested"
	owm_paired_execute_switch

	if [[ "$skip_waybar" != "1" ]]; then
		owm_waybar_refresh
	fi
}

owm_paired_cycle() {
	local direction="$1"
	local skip_waybar="${2:-0}"

	local offset="$OWM_PAIRED_OFFSET"
	local active
	active="$(owm_hypr_active_workspace_id)" || owm_die "unable to determine active workspace"
	if ! [[ "$active" =~ ^-?[0-9]+$ ]]; then
		owm_die "active workspace id '$active' is not numeric"
	fi

	local base target
	if ((active > offset)); then
		base=$((active - offset))
	else
		base="$active"
	fi

	case "$direction" in
	next)
		target=$((base + 1))
		if ((target > offset)); then
			target=1
		fi
		;;
	prev)
		if ((base <= 1)); then
			target="$offset"
		else
			target=$((base - 1))
		fi
		;;
	*)
		owm_die "direction must be 'next' or 'prev'"
		;;
	esac

	owm_paired_plan_switch "$target"
	owm_paired_execute_switch

	if [[ "$skip_waybar" != "1" ]]; then
		owm_waybar_refresh
	fi
}

owm_paired_move_window() {
	local requested="$1"
	local skip_waybar="${2:-0}"

	if ! [[ "$requested" =~ ^[0-9]+$ ]]; then
		owm_die "workspace must be numeric"
	fi

	local window_json
	window_json="$(owm_hypr_active_window)" || owm_die "unable to fetch active window"

	local window_monitor
	window_monitor="$(printf '%s\n' "$window_json" | jq -r 'if .monitor == null then "" elif ( .monitor | type == "number" ) then (.monitor|tostring) else .monitor end')"
	local workspace_id
	workspace_id="$(printf '%s\n' "$window_json" | jq -r 'if .workspaceID != null then .workspaceID elif (.workspace != null and .workspace.id != null) then .workspace.id else empty end')"

	local offset="$OWM_PAIRED_OFFSET"
	local normalized
	normalized="$(owm_paired_normalize_workspace "$requested" "$offset")"

	local use_secondary=0
	if [[ -n "$window_monitor" && "$window_monitor" == "$OWM_PAIRED_SECONDARY" ]]; then
		use_secondary=1
	elif [[ -n "$workspace_id" && "$workspace_id" =~ ^[0-9]+$ && "$offset" =~ ^[0-9]+$ ]]; then
		if ((workspace_id > offset)); then
			use_secondary=1
		fi
	fi

	local target_workspace="$normalized"
	if ((use_secondary == 1)); then
		target_workspace=$((normalized + offset))
	fi

	owm_hypr_dispatch movetoworkspacesilent "$target_workspace"

	local focus_monitor="$OWM_PAIRED_PRIMARY"
	if ((use_secondary == 1)); then
		focus_monitor="$OWM_PAIRED_SECONDARY"
	fi

	owm_hypr_dispatch focusmonitor "$focus_monitor"
	owm_hypr_dispatch workspace "$target_workspace"

	if ((use_secondary == 1)); then
		owm_paired_plan_switch "$normalized"
	else
		owm_paired_plan_switch "$normalized"
	fi
	local original_primary_ws="$OWM_PAIRED_PRIMARY_WORKSPACE"
	local original_secondary_ws="$OWM_PAIRED_SECONDARY_WORKSPACE"
	owm_paired_execute_switch
	export OWM_PAIRED_PRIMARY_WORKSPACE="$original_primary_ws"
	export OWM_PAIRED_SECONDARY_WORKSPACE="$original_secondary_ws"

	if [[ "$skip_waybar" != "1" ]]; then
		owm_waybar_refresh
	fi
}

owm_paired_explain() {
	local json_output="${1:-0}"

	local primary="$OWM_PAIRED_PRIMARY"
	local secondary="$OWM_PAIRED_SECONDARY"
	local offset="$OWM_PAIRED_OFFSET"
	local primary_desc="$OWM_PAIRED_PRIMARY_DESC"
	local secondary_desc="$OWM_PAIRED_SECONDARY_DESC"

	if [[ "$json_output" == "1" ]]; then
		jq -n --arg primary "$primary" \
			--arg secondary "$secondary" \
			--arg primary_desc "$primary_desc" \
			--arg secondary_desc "$secondary_desc" \
			--argjson offset "$offset" \
			'{
        primary_monitor: $primary,
        primary_descriptor: (if $primary_desc == "" then null else $primary_desc end),
        secondary_monitor: $secondary,
        secondary_descriptor: (if $secondary_desc == "" then null else $secondary_desc end),
        pair_offset: $offset,
        config_source: "config/paired.json"
      }'
		return 0
	fi

	printf 'Primary monitor     : %s\n' "$primary"
	if [[ -n "$primary_desc" ]]; then
		printf '  descriptor        : %s\n' "$primary_desc"
	fi
	printf 'Secondary monitor   : %s\n' "$secondary"
	if [[ -n "$secondary_desc" ]]; then
		printf '  descriptor        : %s\n' "$secondary_desc"
	fi
	printf 'Paired workspace gap: %s (config)\n' "$offset"
	printf '\n'
	printf 'Configuration source: %s\n' "$OWM_CONFIG_PATH"
}
