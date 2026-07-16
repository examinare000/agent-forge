#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit) hook: lint the file Claude just edited.
# Why a hook, not a checklist item: "run the linter after editing" is a
# deterministic step, so it belongs in automation rather than relying on the
# model to remember the pre-merge checklist. Findings are surfaced as advisory
# feedback (exit 2 -> stderr returned to Claude); they never block the edit and
# any tooling problem degrades to a silent no-op (exit 0) so the edit flow is
# never broken. See ~/.claude/CLAUDE.md (pre-merge checklist) and
# agent-rules/13-readability.md.
set -uo pipefail

# No ERR trap on purpose: a linter that finds problems exits non-zero, and we
# must NOT swallow that. Each risky step below is guarded explicitly instead, so
# tooling failures degrade to a silent no-op without hiding real lint findings.

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
[ -n "$file" ] && [ -f "$file" ] || exit 0

# Walk up from the edited file to find a marker (relative path). Echoes the
# absolute marker path on success.
find_up() {
  local dir marker="$1"
  dir="$(cd "$(dirname "$file")" && pwd)" || return 1
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -e "$dir/$marker" ]; then
      printf '%s' "$dir/$marker"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

ext="${file##*.}"
output=""
status=0

case "$ext" in
  py)
    # Prefer a project-local ruff (venv), fall back to PATH, then `python -m`.
    ruff=""
    for cand in .venv/bin/ruff venv/bin/ruff; do
      if hit="$(find_up "$cand")"; then ruff="$hit"; break; fi
    done
    [ -z "$ruff" ] && command -v ruff >/dev/null 2>&1 && ruff="ruff"
    [ -z "$ruff" ] || {
      output="$("$ruff" check --quiet "$file" 2>&1)"
      status=$?
    }
    ;;
  ts | tsx | js | jsx | mjs | cjs)
    # Use the nearest project's eslint so its flat/legacy config resolves.
    if binpath="$(find_up node_modules/.bin/eslint)"; then
      projdir="$(cd "$(dirname "$binpath")/../.." && pwd)"
      output="$(cd "$projdir" && ./node_modules/.bin/eslint "$file" 2>&1)"
      status=$?
    fi
    ;;
  *)
    exit 0
    ;;
esac

# Linter clean (or not run) -> stay quiet.
[ "$status" -eq 0 ] && exit 0
[ -n "$output" ] || exit 0

{
  echo "🟠 lint 指摘 (${file##*/}): 編集後の自動 lint で問題を検出しました。修正してください。"
  printf '%s\n' "$output"
} >&2
exit 2
