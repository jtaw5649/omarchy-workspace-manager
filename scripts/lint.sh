#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
STATUS=0

mapfile -t SHELL_FILES < <(find "$PROJECT_ROOT" \( -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/dist" -o -path "$PROJECT_ROOT/target" \) -prune -false -o -type f \( -name '*.sh' -o -name '*.bash' \))
SHELL_FILES+=("$PROJECT_ROOT/bin/omarchy-workspace-manager")

if command -v shellcheck >/dev/null 2>&1; then
	if ((${#SHELL_FILES[@]} > 0)); then
		echo "[lint] shellcheck"
		shellcheck -x "${SHELL_FILES[@]}" || STATUS=1
	fi
else
	echo "[lint] shellcheck not installed; skipping" >&2
fi

if command -v shfmt >/dev/null 2>&1; then
	if ((${#SHELL_FILES[@]} > 0)); then
		echo "[fmt] shfmt --diff"
		shfmt -ln bash -d "${SHELL_FILES[@]}" || STATUS=1
	fi
else
	echo "[fmt] shfmt not installed; skipping" >&2
fi

exit $STATUS
