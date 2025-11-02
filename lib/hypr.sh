#!/usr/bin/env bash
# Hyprland helpers for Omarchy Workspace Manager.

owm_hyprctl_bin() {
	if [[ -n "${OWM_HYPRCTL_BIN:-}" ]]; then
		printf '%s' "$OWM_HYPRCTL_BIN"
	elif [[ -n "${OWM_HYPRCTL:-}" ]]; then
		printf '%s' "$OWM_HYPRCTL"
	else
		printf '%s' "hyprctl"
	fi
}

owm_hypr_dispatch() {
	owm_hyprctl dispatch "$@"
}

owm_hypr_focused_monitor() {
	local json
	if ! json="$(owm_hypr_get_json monitors)"; then
		return 1
	fi
	if [[ -z "$json" || "$json" == "null" ]]; then
		return 1
	fi

	local monitor
	monitor="$(printf '%s\n' "$json" | jq -r '
		def pick_name($m):
			if ($m.name // "") != "" then $m.name
			elif ($m.description // "") != "" then $m.description
			else ""
			end;
		([.[] | select((.focused? // false) == true)] | first) // ([.[]] | sort_by(.id // 0) | first)
		| (pick_name(.)) // ""
	')"

	if [[ -n "$monitor" ]]; then
		printf '%s\n' "$monitor"
	else
		return 1
	fi
}

owm_hypr_get_json() {
	local resource="$1"
	shift || true
	owm_hyprctl "$resource" "$@" -j
}

owm_hypr_active_workspace_id() {
	local json
	if ! json="$(owm_hypr_get_json activeworkspace)"; then
		return 1
	fi
	if [[ -z "$json" || "$json" == "null" ]]; then
		return 1
	fi
	printf '%s\n' "$json" | jq -r 'if has("id") then .id else empty end'
}

owm_hypr_active_window() {
	local json
	if ! json="$(owm_hypr_get_json activewindow)"; then
		return 1
	fi
	if [[ -z "$json" || "$json" == "null" ]]; then
		return 1
	fi
	printf '%s\n' "$json"
}

owm_hypr_quote_arg() {
	local arg="$1"

	# Preserve simple tokens (numbers, hypr expressions, identifiers) without quoting.
	# Hyprland rejects numeric workspace arguments when wrapped in quotes.
	if [[ -n "$arg" && "$arg" =~ ^[-[:alnum:]._:/+]+$ ]]; then
		printf '%s' "$arg"
		return 0
	fi

	arg=${arg//$'\n'/ }
	arg=${arg//$'\r'/ }
	if [[ -z "$arg" ]]; then
		printf '""'
		return 0
	fi

	# Escape backslashes and quotes so the batch payload stays parseable.
	arg=${arg//\\/\\\\}
	arg=${arg//\"/\\\"}
	printf '"%s"' "$arg"
}

owm_hypr_log_squash() {
	local text="$1"
	local limit="${2:-512}"

	text=${text//$'\n'/\\n}
	text=${text//$'\r'/\\r}

	if ((${#text} > limit)); then
		printf '%s…' "${text:0:limit-1}"
	else
		printf '%s' "$text"
	fi
}

owm_hypr_log_command() {
	local bin="$1"
	local rc="$2"
	local stdout_content="$3"
	local stderr_content="$4"
	shift 4

	if [[ "${OWM_HYPR_LOG_DISABLE:-0}" == "1" ]]; then
		return 0
	fi
	local log_dir
	local log_file
	if [[ -n "${OWM_HYPR_LOG_FILE:-}" ]]; then
		log_file="$OWM_HYPR_LOG_FILE"
		log_dir="$(dirname -- "$log_file")"
	else
		local log_root="${OWM_HYPR_LOG_DIR:-$OWM_LOG_DIR}"
		log_dir="$log_root"
		log_file="${OWM_HYPR_LOG_FILE:-$log_root/hyprctl.log}"
	fi
	owm_ensure_dir "$log_dir" 2>/dev/null || true

	local timestamp
	timestamp="$(owm_now_iso_8601)"

	local status="ok"
	if ((rc != 0)); then
		status="error"
	elif [[ "$stderr_content" == *"Error"* || "$stdout_content" == *"Error"* ]]; then
		status="warn"
	fi

	local args_str=""
	if (($# > 0)); then
		printf -v args_str '%q ' "$@"
		args_str=${args_str% }
	fi

	local stdout_log stderr_log
	stdout_log="$(owm_hypr_log_squash "$stdout_content")"
	stderr_log="$(owm_hypr_log_squash "$stderr_content")"

	local rotate_threshold="${OWM_HYPR_LOG_MAX_BYTES:-1048576}"
	if [[ -f "$log_file" && "$rotate_threshold" =~ ^[0-9]+$ ]]; then
		local log_size
		log_size="$(stat -c%s "$log_file" 2>/dev/null || printf '0')"
		if ((log_size >= rotate_threshold)); then
			local suffix
			suffix="$(date '+%Y%m%d%H%M%S')"
			mv "$log_file" "$log_file.$suffix" 2>/dev/null || true
		fi
	fi

	{
		printf '[%s] status=%s exit=%d cmd=%s' "$timestamp" "$status" "$rc" "$bin"
		if [[ -n "$args_str" ]]; then
			printf ' args=%s' "$args_str"
		fi
		printf '\n'
		if [[ -n "$stdout_log" ]]; then
			printf 'stdout=%s\n' "$stdout_log"
		fi
		if [[ -n "$stderr_log" ]]; then
			printf 'stderr=%s\n' "$stderr_log"
		fi
		printf '\n'
	} >>"$log_file" 2>/dev/null || true
}

owm_hypr_build_dispatch() {
	local command="$1"
	shift || true
	local line="dispatch $command"
	local arg
	for arg in "$@"; do
		line+=" $(owm_hypr_quote_arg "$arg")"
	done
	printf '%s' "$line"
}

owm_hypr_dispatch_batch() {
	local -a commands=("$@")
	if ((${#commands[@]} == 0)); then
		return 0
	fi

	# Hyprland sometimes drops state updates when multiple monitor/workspace commands
	# are squeezed into a single --batch payload. In practice it is more reliable to
	# execute each dispatch individually, so default to serialized calls unless the
	# caller explicitly opts back into batching.
	if [[ "${OWM_HYPR_DISABLE_SERIAL:-0}" != "1" ]]; then
		local command
		for command in "${commands[@]}"; do
			owm_hyprctl --batch "$command"
		done
		return 0
	fi

	local payload
	payload=$(printf '%s\n' "${commands[@]}")
	owm_hyprctl --batch "$payload"
}

owm_hyprctl() {
	local bin
	bin="$(owm_hyprctl_bin)"

	local stdout_file stderr_file
	stdout_file="$(mktemp 2>/dev/null)" || {
		"$bin" "$@"
		return $?
	}
	stderr_file="$(mktemp 2>/dev/null)" || {
		rm -f "$stdout_file"
		"$bin" "$@"
		return $?
	}

	local rc
	if "$bin" "$@" >"$stdout_file" 2>"$stderr_file"; then
		rc=0
	else
		rc=$?
	fi

	local stdout_content stderr_content
	stdout_content="$(<"$stdout_file")"
	stderr_content="$(<"$stderr_file")"
	rm -f "$stdout_file" "$stderr_file"

	owm_hypr_log_command "$bin" "$rc" "$stdout_content" "$stderr_content" "$@"

	local display_stdout="$stdout_content"
	if [[ "$display_stdout" == *"Previous workspace doesn't exist"* ]]; then
		owm_debug "hyprctl notice suppressed: Previous workspace doesn't exist"
		display_stdout="${display_stdout//Previous workspace doesn\'t exist/}"
		display_stdout="${display_stdout//$'\r'/}"
		if [[ "$display_stdout" == ok ]]; then
			:
		else
			display_stdout="${display_stdout//$'\n'/}"
			display_stdout="${display_stdout//[[:space:]]/}"
			if [[ -z "$display_stdout" ]]; then
				display_stdout="ok"
			fi
		fi
	fi

	if [[ -n "$display_stdout" ]]; then
		printf '%s\n' "$display_stdout"
	fi
	if [[ -n "$stderr_content" ]]; then
		printf '%s' "$stderr_content" >&2
	fi

	return $rc
}
