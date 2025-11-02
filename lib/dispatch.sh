#!/usr/bin/env bash
# Workspace dispatch helpers for Omarchy Workspace Manager.

owm_source "lib/paired.sh"

owm_dispatch_verify_monitors() {
	local json
	if ! json="$(owm_hypr_get_json monitors)"; then
		owm_warn "unable to query monitors from hyprctl; skipping verification"
		return 0
	fi

	local primary_matches
	local secondary_matches
	primary_matches="$(printf '%s\n' "$json" | jq --arg name "$OWM_PAIRED_PRIMARY" --arg desc "$OWM_PAIRED_PRIMARY_DESC" '
    map(select(.name == $name or ($desc != "" and (.description // "") == $desc))) | length
  ')"
	secondary_matches="$(printf '%s\n' "$json" | jq --arg name "$OWM_PAIRED_SECONDARY" --arg desc "$OWM_PAIRED_SECONDARY_DESC" '
    map(select(.name == $name or ($desc != "" and (.description // "") == $desc))) | length
  ')"

	if ! [[ "$primary_matches" =~ ^[0-9]+$ ]]; then
		owm_warn "could not verify primary monitor presence"
	elif ((primary_matches == 0)); then
		owm_warn "no monitor matches primary identifier '$OWM_PAIRED_PRIMARY'"
	fi

	if ! [[ "$secondary_matches" =~ ^[0-9]+$ ]]; then
		owm_warn "could not verify secondary monitor presence"
	elif ((secondary_matches == 0)); then
		owm_warn "no monitor matches secondary identifier '$OWM_PAIRED_SECONDARY'"
	fi
}

owm_dispatch_apply_group() {
	local group_ref_name="$1"
	local monitor="$2"
	local dry_run="$3"
	local -n group_ref="$group_ref_name"

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
			owm_hypr_dispatch moveworkspacetomonitor "$workspace" "$monitor"
			owm_hypr_dispatch focusmonitor "$monitor"
			owm_hypr_dispatch workspace "$workspace"
		fi
	done
}

owm_dispatch_run() {
	local dry_run="${1:-0}"
	local primary_override="${2:-}"
	local secondary_override="${3:-}"
	local offset_override="${4:-}"

	owm_paired_load_config "$primary_override" "$secondary_override" "$offset_override"

	owm_dispatch_verify_monitors || true

	owm_dispatch_apply_group OWM_PAIRED_PRIMARY_GROUP "$OWM_PAIRED_PRIMARY" "$dry_run"
	if [[ "$OWM_PAIRED_SECONDARY" != "$OWM_PAIRED_PRIMARY" ]]; then
		owm_dispatch_apply_group OWM_PAIRED_SECONDARY_GROUP "$OWM_PAIRED_SECONDARY" "$dry_run"
	else
		owm_debug "Primary and secondary monitors match; skipping duplicate assignment"
	fi
}
