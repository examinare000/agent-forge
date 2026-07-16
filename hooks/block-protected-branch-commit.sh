#!/usr/bin/env bash
# PreToolUse(Bash) hook: block `git commit` on protected branches.
# Why a hook, not a prompt rule: branch protection is an absolute prohibition,
# so it must be deterministic (exit code 2 blocks the tool call) rather than
# relying on the model to remember the rule. See ~/.claude/CLAUDE.md.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
# Directory the command actually runs in (agent's persistent Bash cwd).
# Multi-repo safety: evaluate the TARGET repo's branch, not the hook process's
# own cwd (= session project dir), which may sit on a different branch.
payload_cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"

# Only act when the command actually invokes `git commit` (incl. --amend).
# Split on command separators (; | &) and require a segment whose FIRST word is
# `git` running the `commit` subcommand — so `echo git commit` or
# `git log --grep commit` don't false-trigger.
is_commit=0
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}" # ltrim
  if printf '%s' "$seg" | grep -Eq '^git( +-C +[^ ]+| +-c +[^ ]+)* +commit\b'; then
    is_commit=1
    break
  fi
done < <(printf '%s\n' "$cmd" | tr ';|&' '\n\n\n')
[ "$is_commit" -eq 1 ] || exit 0

is_protected() {
  case "$1" in main | master | develop) return 0 ;; *) return 1 ;; esac
}

# Resolve the directory the commit actually targets, so branch protection is
# evaluated against the RIGHT repo (not the session cwd, which may be elsewhere).
eff_dir="${payload_cwd:-.}"
# Honor a `cd <dir>` that precedes the commit in the same command line.
cd_target="$(printf '%s' "$cmd" | grep -oE '(^|[;&|]) *cd +[^ ;&|]+' | tail -1 | sed -E 's/.*cd +//')"
if [ -n "$cd_target" ]; then
  case "$cd_target" in
    /*) eff_dir="$cd_target" ;;
    "~"/*) eff_dir="${HOME}/${cd_target#~/}" ;;
    *) eff_dir="${payload_cwd:-.}/$cd_target" ;;
  esac
fi
# A `git -C <dir> commit` targets that dir explicitly → it wins.
gitc_dir="$(printf '%s' "$cmd" | grep -oE '\bgit +-C +[^ ]+ +commit' | head -1 | sed -E 's/.*git +-C +//; s/ +commit.*//')"
[ -n "$gitc_dir" ] && eff_dir="$gitc_dir"

# Fast path: if the target repo's HEAD is not on a protected branch, allow.
branch="$(git -C "$eff_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if ! is_protected "$branch"; then
  exit 0
fi

# HEAD is on a protected branch, but the same command may move off it before
# committing (e.g. `git switch -c feat && git commit`). Detect unambiguous
# branch switches and, if any lands on a NON-protected branch, allow:
#   - `git switch [-c|--create|-C] NAME`  (git switch never operates on files)
#   - `git checkout (-b|-B) NAME`         (explicit branch creation)
# Plain `git checkout NAME` is intentionally ignored (ambiguous with file paths).
targets="$(printf '%s' "$cmd" | grep -oE \
  '\bgit +switch +((-c|--create|-C) +)?[A-Za-z0-9._/][A-Za-z0-9._/-]*|\bgit +checkout +(-b|-B) +[A-Za-z0-9._/][A-Za-z0-9._/-]*' \
  | awk '{print $NF}')"

if [ -n "$targets" ]; then
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    is_protected "$t" || exit 0 # switches to a non-protected branch first → allow
  done <<< "$targets"
fi

echo "🔴 ブランチ保護: '${branch}' への直接コミットは禁止です。" \
     "フィーチャーブランチを作成してからコミットしてください" \
     "(agent-rules/10-git-strategy.md)。" >&2
exit 2
