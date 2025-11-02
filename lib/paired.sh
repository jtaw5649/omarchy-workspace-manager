#!/usr/bin/env bash
# shellcheck shell=bash
# Paired workspace helpers powering the `paired` CLI.

owm_source "lib/hypr.sh"
owm_source "lib/waybar.sh"

# shellcheck disable=SC2034 # exported for dispatch helpers
declare -g -a OWM_PAIRED_PRIMARY_IDS=()
# shellcheck disable=SC2034 # exported for dispatch helpers
declare -g -a OWM_PAIRED_SECONDARY_IDS=()
# shellcheck disable=SC2034 # exported for dispatch helpers
declare -g -A OWM_PAIRED_MONITOR_TARGETS=()
# shellcheck disable=SC2034 # exported for dispatch helpers
declare -g OWM_PAIRED_PRIMARY_PRESENT=0
# shellcheck disable=SC2034 # exported for dispatch helpers
declare -g OWM_PAIRED_SECONDARY_PRESENT=0

owm_paired_collect_identifiers() {
	local name="$1"
	local descriptor="$2"
	local monitor_id="$3"
	local dest_name="$4"
	declare -n dest="$dest_name"
	dest=()
	local -A seen=()
	if [[ -n "$name" && -z "${seen[$name]-}" ]]; then
		dest+=("$name")
		seen["$name"]=1
	fi
	if [[ -n "$monitor_id" ]]; then
		local id_candidate="id:$monitor_id"
		if [[ -z "${seen[$id_candidate]-}" ]]; then
			dest+=("$id_candidate")
			seen["$id_candidate"]=1
		fi
	fi
	if [[ -n "$descriptor" ]]; then
		local descriptor_candidate="desc:$descriptor"
		if [[ -z "${seen[$descriptor_candidate]-}" ]]; then
			dest+=("$descriptor_candidate")
			seen["$descriptor_candidate"]=1
		fi
		if [[ -z "${seen[$descriptor]-}" ]]; then
			dest+=("$descriptor")
			seen["$descriptor"]=1
		fi
	fi
}

owm_paired_reset_monitor_targets() {
	OWM_PAIRED_MONITOR_TARGETS=()
	OWM_PAIRED_PRIMARY_PRESENT=0
	OWM_PAIRED_SECONDARY_PRESENT=0
	if [[ -n "${OWM_PAIRED_PRIMARY_IDS[0]:-}" ]]; then
		OWM_PAIRED_MONITOR_TARGETS[primary]="${OWM_PAIRED_PRIMARY_IDS[0]}"
	fi
	if [[ -n "${OWM_PAIRED_SECONDARY_IDS[0]:-}" ]]; then
		OWM_PAIRED_MONITOR_TARGETS[secondary]="${OWM_PAIRED_SECONDARY_IDS[0]}"
	fi
}

owm_paired_update_monitor_targets() {
	local monitors_json="$1"
	if [[ -z "$monitors_json" || "$monitors_json" == "null" ]]; then
		return 0
	fi
	local -A name_lookup=()
	local -A desc_lookup=()
	local -A id_lookup=()
	while IFS=$'\t' read -r mon_id mon_name mon_desc; do
		if [[ -n "$mon_id" && "$mon_id" != "null" ]]; then
			id_lookup["id:$mon_id"]="$mon_name"
		fi
		if [[ -n "$mon_name" ]]; then
			name_lookup["$mon_name"]=1
		fi
		if [[ -n "$mon_desc" ]]; then
			desc_lookup["$mon_desc"]=1
		fi
	done < <(printf '%s\n' "$monitors_json" | jq -r '.[] | [((.id // "")|tostring), (.name // ""), (.description // "")] | @tsv')

	OWM_PAIRED_PRIMARY_PRESENT=0
	local candidate
	for candidate in "${OWM_PAIRED_PRIMARY_IDS[@]}"; do
		if [[ "$candidate" == desc:* ]]; then
			local match="${candidate#desc:}"
			if [[ -n "${desc_lookup[$match]-}" ]]; then
				OWM_PAIRED_MONITOR_TARGETS[primary]="$candidate"
				# shellcheck disable=SC2034 # propagated to consumers
				OWM_PAIRED_PRIMARY_PRESENT=1
				break
			fi
		elif [[ "$candidate" == id:* ]]; then
			local resolved="${id_lookup[$candidate]-}"
			if [[ -n "$resolved" ]]; then
				OWM_PAIRED_MONITOR_TARGETS[primary]="$resolved"
				# shellcheck disable=SC2034 # propagated to consumers
				OWM_PAIRED_PRIMARY_PRESENT=1
				break
			fi
		else
			if [[ -n "${name_lookup[$candidate]-}" || -n "${desc_lookup[$candidate]-}" ]]; then
				OWM_PAIRED_MONITOR_TARGETS[primary]="$candidate"
				# shellcheck disable=SC2034 # propagated to consumers
				OWM_PAIRED_PRIMARY_PRESENT=1
				break
			fi
		fi
	done

	OWM_PAIRED_SECONDARY_PRESENT=0
	for candidate in "${OWM_PAIRED_SECONDARY_IDS[@]}"; do
		if [[ "$candidate" == desc:* ]]; then
			local match="${candidate#desc:}"
			if [[ -n "${desc_lookup[$match]-}" ]]; then
				OWM_PAIRED_MONITOR_TARGETS[secondary]="$candidate"
				# shellcheck disable=SC2034 # propagated to consumers
				OWM_PAIRED_SECONDARY_PRESENT=1
				break
			fi
		elif [[ "$candidate" == id:* ]]; then
			local resolved="${id_lookup[$candidate]-}"
			if [[ -n "$resolved" ]]; then
				OWM_PAIRED_MONITOR_TARGETS[secondary]="$resolved"
				# shellcheck disable=SC2034 # propagated to consumers
				OWM_PAIRED_SECONDARY_PRESENT=1
				break
			fi
		else
			if [[ -n "${name_lookup[$candidate]-}" || -n "${desc_lookup[$candidate]-}" ]]; then
				OWM_PAIRED_MONITOR_TARGETS[secondary]="$candidate"
				# shellcheck disable=SC2034 # propagated to consumers
				OWM_PAIRED_SECONDARY_PRESENT=1
				break
			fi
		fi
	done
}

owm_paired_monitor_target() {
	local role="$1"
	local target="${OWM_PAIRED_MONITOR_TARGETS[$role]:-}"
	if [[ -n "$target" ]]; then
		printf '%s\n' "$target"
		return 0
	fi
	case "$role" in
	primary)
		if [[ -n "${OWM_PAIRED_PRIMARY_IDS[0]:-}" ]]; then
			printf '%s\n' "${OWM_PAIRED_PRIMARY_IDS[0]}"
		else
			printf '%s\n' "$OWM_PAIRED_PRIMARY"
		fi
		;;
	secondary)
		if [[ -n "${OWM_PAIRED_SECONDARY_IDS[0]:-}" ]]; then
			printf '%s\n' "${OWM_PAIRED_SECONDARY_IDS[0]}"
		else
			printf '%s\n' "$OWM_PAIRED_SECONDARY"
		fi
		;;
	*)
		printf '%s\n' "$role"
		;;
	esac
}

owm_paired_resolve_monitor() {
	local monitor="$1"
	if [[ "$monitor" == "$OWM_PAIRED_PRIMARY" ]]; then
		owm_paired_monitor_target primary
	elif [[ "$monitor" == "$OWM_PAIRED_SECONDARY" ]]; then
		owm_paired_monitor_target secondary
	else
		printf '%s\n' "$monitor"
	fi
}

owm_paired_describe_identifiers() {
	local role="$1"
	local -a identifiers=()
	case "$role" in
	primary)
		identifiers=("${OWM_PAIRED_PRIMARY_IDS[@]}")
		;;
	secondary)
		identifiers=("${OWM_PAIRED_SECONDARY_IDS[@]}")
		;;
	esac
	if ((${#identifiers[@]} == 0)); then
		printf 'none'
	else
		local IFS=', '
		printf '%s' "${identifiers[*]}"
	fi
}

owm_paired_monitor_matches() {
	local role="$1"
	local monitor_id="$2"
	local monitor_name="$3"
	local monitor_desc="$4"

	local -a identifiers=()
	case "$role" in
	primary)
		identifiers=("${OWM_PAIRED_PRIMARY_IDS[@]}")
		;;
	secondary)
		identifiers=("${OWM_PAIRED_SECONDARY_IDS[@]}")
		;;
	*)
		return 1
		;;
	esac

	if ((${#identifiers[@]} == 0)); then
		return 1
	fi

	local -a candidates=()
	if [[ -n "$monitor_desc" ]]; then
		candidates+=("desc:$monitor_desc" "$monitor_desc")
	fi
	if [[ -n "$monitor_name" ]]; then
		candidates+=("$monitor_name")
	fi
	if [[ -n "$monitor_id" ]]; then
		candidates+=("id:$monitor_id")
	fi

	local candidate ident
	for candidate in "${candidates[@]}"; do
		for ident in "${identifiers[@]}"; do
			if [[ -n "$ident" && "$candidate" == "$ident" ]]; then
				return 0
			fi
		done
	done
	return 1
}

owm_paired_prime_monitor_targets() {
	local monitors_json
	if monitors_json="$(owm_hypr_get_json monitors 2>/dev/null)"; then
		if [[ -n "$monitors_json" && "$monitors_json" != "null" ]]; then
			owm_paired_update_monitor_targets "$monitors_json"
		fi
	fi
}

owm_paired_load_config() {
	local primary_override="${1:-}"
	local secondary_override="${2:-}"
	local offset_override="${3:-}"

	if [[ ! -f "$OWM_CONFIG_PATH" ]]; then
		owm_die "missing paired configuration at $OWM_CONFIG_PATH"
	fi

	local primary secondary offset primary_desc secondary_desc primary_id secondary_id
	primary="$(jq -r '.primary_monitor // empty' "$OWM_CONFIG_PATH")"
	secondary="$(jq -r '.secondary_monitor // empty' "$OWM_CONFIG_PATH")"
	offset="$(jq -r '.paired_offset // empty' "$OWM_CONFIG_PATH")"
	primary_desc="$(jq -r '.primary_descriptor // empty' "$OWM_CONFIG_PATH")"
	secondary_desc="$(jq -r '.secondary_descriptor // empty' "$OWM_CONFIG_PATH")"
	primary_id="$(jq -r '.primary_id // empty' "$OWM_CONFIG_PATH")"
	secondary_id="$(jq -r '.secondary_id // empty' "$OWM_CONFIG_PATH")"

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
	export OWM_PAIRED_PRIMARY_ID="$primary_id"
	export OWM_PAIRED_SECONDARY_ID="$secondary_id"
	# shellcheck disable=SC2034 # consumed via nameref in CLI wrappers
	declare -g -a OWM_PAIRED_PRIMARY_GROUP=("${primary_group[@]}")
	# shellcheck disable=SC2034 # consumed via nameref in CLI wrappers
	declare -g -a OWM_PAIRED_SECONDARY_GROUP=("${secondary_group[@]}")

	owm_paired_collect_identifiers "$primary" "$primary_desc" "$primary_id" OWM_PAIRED_PRIMARY_IDS
	owm_paired_collect_identifiers "$secondary" "$secondary_desc" "$secondary_id" OWM_PAIRED_SECONDARY_IDS
	owm_paired_reset_monitor_targets
	owm_paired_prime_monitor_targets
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
	local primary_target
	local secondary_target
	local initial_monitor=""
	local -a commands=()

	primary_target="$(owm_paired_monitor_target primary)"
	secondary_target="$(owm_paired_monitor_target secondary)"
	initial_monitor="$(owm_hypr_focused_monitor)" || initial_monitor=""

	if [[ "$secondary" != "$primary" ]]; then
		commands+=("$(owm_hypr_build_dispatch focusmonitor "$secondary_target")")
		commands+=("$(owm_hypr_build_dispatch workspace "$secondary_ws")")
		commands+=("$(owm_hypr_build_dispatch moveworkspacetomonitor "$secondary_ws" "$secondary_target")")
	fi
	commands+=("$(owm_hypr_build_dispatch focusmonitor "$primary_target")")
	commands+=("$(owm_hypr_build_dispatch workspace "$primary_ws")")
	commands+=("$(owm_hypr_build_dispatch moveworkspacetomonitor "$primary_ws" "$primary_target")")

	local initial_target=""
	if [[ -n "$initial_monitor" ]]; then
		initial_target="$(owm_paired_resolve_monitor "$initial_monitor")"
	fi
	if [[ -n "$initial_target" && "$initial_target" != "$primary_target" ]]; then
		commands+=("$(owm_hypr_build_dispatch focusmonitor "$initial_target")")
	fi

	if ((${#commands[@]} > 0)); then
		owm_hypr_dispatch_batch "${commands[@]}"
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

	local focus_monitor_target
	if ((use_secondary == 1)); then
		focus_monitor_target="$(owm_paired_monitor_target secondary)"
	else
		focus_monitor_target="$(owm_paired_monitor_target primary)"
	fi

	local -a move_commands=()
	move_commands+=("$(owm_hypr_build_dispatch movetoworkspacesilent "$target_workspace")")
	move_commands+=("$(owm_hypr_build_dispatch focusmonitor "$focus_monitor_target")")
	move_commands+=("$(owm_hypr_build_dispatch workspace "$target_workspace")")
	owm_hypr_dispatch_batch "${move_commands[@]}"

	owm_paired_plan_switch "$normalized"
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
