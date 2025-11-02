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
	local -a batch_commands=()

	local workspace
	for workspace in "${group_ref[@]}"; do
		[[ -n "$workspace" ]] || continue
		if ! [[ "$workspace" =~ ^-?[0-9]+$ ]]; then
			owm_warn "skipping non-numeric workspace '$workspace' for monitor '$monitor'"
			continue
		fi
		if [[ "$dry_run" == "1" ]]; then
			printf '[dry-run] move workspace %s to monitor %s\n' "$workspace" "$monitor"
			printf '[dry-run] focus monitor %s; workspace %s\n' "$monitor" "$workspace"
		else
			batch_commands+=("$(owm_hypr_build_dispatch moveworkspacetomonitor "$workspace" "$monitor_target")")
			batch_commands+=("$(owm_hypr_build_dispatch focusmonitor "$monitor_target")")
			batch_commands+=("$(owm_hypr_build_dispatch workspace "$workspace")")
		fi
	done
	if [[ "$dry_run" != "1" && ${#batch_commands[@]} -gt 0 ]]; then
		owm_hypr_dispatch_batch "${batch_commands[@]}"
	fi
}

owm_dispatch_run() {
	local dry_run="${1:-0}"
	local primary_override="${2:-}"
	local secondary_override="${3:-}"
	local offset_override="${4:-}"

	owm_paired_load_config "$primary_override" "$secondary_override" "$offset_override"

	owm_dispatch_verify_monitors || true

	owm_dispatch_apply_group "$OWM_PAIRED_PRIMARY" "$dry_run" "${OWM_PAIRED_PRIMARY_GROUP[@]}"
	if [[ "$OWM_PAIRED_SECONDARY" != "$OWM_PAIRED_PRIMARY" ]]; then
		owm_dispatch_apply_group "$OWM_PAIRED_SECONDARY" "$dry_run" "${OWM_PAIRED_SECONDARY_GROUP[@]}"
	else
		owm_debug "Primary and secondary monitors match; skipping duplicate assignment"
	fi
}
