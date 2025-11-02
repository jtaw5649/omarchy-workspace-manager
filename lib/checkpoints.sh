#!/usr/bin/env bash
# Checkpoint comparison helpers.

owm_checkpoints_default_expected() {
	printf '%s/config/paired.json' "$OWM_ROOT"
}

owm_checkpoints_default_actual() {
	printf '%s/.config/omarchy-workspace-manager/paired.json' "$HOME"
}

owm_checkpoints_build_diff() {
	local expected_path="$1"
	local actual_path="$2"

	jq -n --slurpfile expected "$expected_path" --slurpfile actual "$actual_path" '
    ($expected[0] // {}) as $expected |
    ($actual[0] // {}) as $actual |
    def arr(v): if v == null then [] else v end;
    def groups(v): if v.workspace_groups == null then {} else v.workspace_groups end;
    {
      primary_monitor: {expected: ($expected.primary_monitor // null), actual: ($actual.primary_monitor // null)},
      secondary_monitor: {expected: ($expected.secondary_monitor // null), actual: ($actual.secondary_monitor // null)},
      paired_offset: {expected: ($expected.paired_offset // null), actual: ($actual.paired_offset // null)},
      workspace_groups: {
        primary_missing: (arr(groups($expected).primary) - arr(groups($actual).primary)),
        primary_extra: (arr(groups($actual).primary) - arr(groups($expected).primary)),
        secondary_missing: (arr(groups($expected).secondary) - arr(groups($actual).secondary)),
        secondary_extra: (arr(groups($actual).secondary) - arr(groups($expected).secondary))
      }
    }
  '
}

owm_checkpoints_has_diff() {
	local diff_json="$1"
	printf '%s\n' "$diff_json" | jq '(
    (.primary_monitor.expected != .primary_monitor.actual) or
    (.secondary_monitor.expected != .secondary_monitor.actual) or
    (.paired_offset.expected != .paired_offset.actual) or
    ((.workspace_groups.primary_missing | length) > 0) or
    ((.workspace_groups.primary_extra | length) > 0) or
    ((.workspace_groups.secondary_missing | length) > 0) or
    ((.workspace_groups.secondary_extra | length) > 0)
  )'
}

owm_checkpoints_print_text() {
	local diff_json="$1"
	printf '%s\n' "$diff_json" | jq -r '
    def show(val): if val == null then "(unset)" else (val | tostring) end;
    "Primary monitor : expected " + show(.primary_monitor.expected) + ", actual " + show(.primary_monitor.actual),
    "Secondary monitor : expected " + show(.secondary_monitor.expected) + ", actual " + show(.secondary_monitor.actual),
    "Paired offset   : expected " + show(.paired_offset.expected) + ", actual " + show(.paired_offset.actual),
    ("Primary group missing : " + ((.workspace_groups.primary_missing | if length == 0 then "[]" else tostring end))),
    ("Primary group extra   : " + ((.workspace_groups.primary_extra | if length == 0 then "[]" else tostring end))),
    ("Secondary group missing : " + ((.workspace_groups.secondary_missing | if length == 0 then "[]" else tostring end))),
    ("Secondary group extra   : " + ((.workspace_groups.secondary_extra | if length == 0 then "[]" else tostring end)))
  '
}

owm_checkpoints_diff() {
	local expected_path="$1"
	local actual_path="$2"
	local json_output="$3"

	if [[ ! -f "$expected_path" ]]; then
		owm_die "expected checkpoint not found at $expected_path"
	fi
	if [[ ! -f "$actual_path" ]]; then
		owm_die "actual checkpoint not found at $actual_path"
	fi

	local diff
	diff="$(owm_checkpoints_build_diff "$expected_path" "$actual_path")"

	if [[ "$json_output" == "1" ]]; then
		local status
		status="$(owm_checkpoints_has_diff "$diff")"
		if [[ "$status" == "true" ]]; then
			status="drift"
		else
			status="in_sync"
		fi
		printf '%s\n' "$diff" | jq --arg status "$status" '. + {status: $status}'
		return 0
	fi

	owm_checkpoints_print_text "$diff"
	local changed
	changed="$(owm_checkpoints_has_diff "$diff")"
	if [[ "$changed" == "true" ]]; then
		owm_warn "configuration drift detected"
	else
		owm_info "checkpoints match"
	fi
}
