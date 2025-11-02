#!/usr/bin/env bash
# Workspace dispatch helpers for Omarchy Workspace Manager.

owm_source "lib/paired.sh"

owm_dispatch_verify_monitors() {
	local json
	if ! json="$(owm_hypr_get_json monitors)"; then
		owm_warn "unable to query monitors from hyprctl; skipping verification"
		return 0
	fi

	owm_paired_update_monitor_targets "$json"

	if ((OWM_PAIRED_PRIMARY_PRESENT == 0)); then
		owm_warn "no monitor matches primary identifiers ($(owm_paired_describe_identifiers primary))"
	fi
	if ((OWM_PAIRED_SECONDARY_PRESENT == 0)); then
		owm_warn "no monitor matches secondary identifiers ($(owm_paired_describe_identifiers secondary))"
	fi

	local primary_target
	local secondary_target
	primary_target="$(owm_paired_monitor_target primary)"
	secondary_target="$(owm_paired_monitor_target secondary)"
	owm_debug "monitor targets resolved to primary='$primary_target' secondary='$secondary_target'"
}

owm_dispatch_apply_group() {
	local monitor="$1"
	shift
	local dry_run="$1"
	shift
	local monitor_target
	monitor_target="$(owm_paired_resolve_monitor "$monitor")"
	local -a group_ref=("$@")
	local -a move_commands=()

	local workspace
	for workspace in "${group_ref[@]}"; do
		[[ -n "$workspace" ]] || continue
		if ! [[ "$workspace" =~ ^-?[0-9]+$ ]]; then
			owm_warn "skipping non-numeric workspace '$workspace' for monitor '$monitor'"
			continue
		fi
		if [[ "$dry_run" == "1" ]]; then
			printf '[dry-run] move workspace %s to monitor %s\n' "$workspace" "$monitor"
		else
			move_commands+=("$(owm_hypr_build_dispatch moveworkspacetomonitor "$workspace" "$monitor_target")")
		fi
	done
	if [[ "$dry_run" != "1" && ${#move_commands[@]} -gt 0 ]]; then
		owm_hypr_dispatch_batch "${move_commands[@]}"
	fi
}

owm_dispatch_run() {
	local dry_run="${1:-0}"
	local primary_override="${2:-}"
	local secondary_override="${3:-}"
	local offset_override="${4:-}"

	owm_paired_load_config "$primary_override" "$secondary_override" "$offset_override"

	owm_dispatch_verify_monitors || true

	local initial_monitor=""
	local initial_workspace=""
	if [[ "$dry_run" != "1" ]]; then
		initial_monitor="$(owm_hypr_focused_monitor 2>/dev/null || true)"
		initial_workspace="$(owm_hypr_active_workspace_id 2>/dev/null || true)"
	fi

	owm_dispatch_apply_group "$OWM_PAIRED_PRIMARY" "$dry_run" "${OWM_PAIRED_PRIMARY_GROUP[@]}"
	if [[ "$OWM_PAIRED_SECONDARY" != "$OWM_PAIRED_PRIMARY" ]]; then
		owm_dispatch_apply_group "$OWM_PAIRED_SECONDARY" "$dry_run" "${OWM_PAIRED_SECONDARY_GROUP[@]}"
	else
		owm_debug "Primary and secondary monitors match; skipping duplicate assignment"
	fi

	if [[ "$dry_run" != "1" ]]; then
		local -a restore_commands=()
		local secondary_target=""
		secondary_target="$(owm_paired_monitor_target secondary)"
		if [[ -n "$secondary_target" && "$OWM_PAIRED_SECONDARY" != "$OWM_PAIRED_PRIMARY" ]]; then
			local offset="$OWM_PAIRED_OFFSET"
			if [[ "$offset" =~ ^[0-9]+$ && "$offset" -gt 0 && "$initial_workspace" =~ ^-?[0-9]+$ ]]; then
				local normalized
				normalized="$(owm_paired_normalize_workspace "$initial_workspace" "$offset")"
				if [[ -n "$normalized" && "$normalized" =~ ^-?[0-9]+$ ]]; then
					local secondary_workspace=$((normalized + offset))
					restore_commands+=("$(owm_hypr_build_dispatch moveworkspacetomonitor "$secondary_workspace" "$secondary_target")")
					restore_commands+=("$(owm_hypr_build_dispatch focusmonitor "$secondary_target")")
					restore_commands+=("$(owm_hypr_build_dispatch workspace "$secondary_workspace")")
				fi
			fi
		fi
		if [[ -n "$initial_monitor" ]]; then
			restore_commands+=("$(owm_hypr_build_dispatch focusmonitor "$initial_monitor")")
		fi
		if [[ -n "$initial_workspace" ]]; then
			restore_commands+=("$(owm_hypr_build_dispatch workspace "$initial_workspace")")
		fi
		if ((${#restore_commands[@]} > 0)); then
			owm_hypr_dispatch_batch "${restore_commands[@]}"
		fi
	fi
}
