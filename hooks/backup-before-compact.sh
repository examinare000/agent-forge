#!/usr/bin/env bash
# PreCompact hook: snapshot the conversation transcript before it is compacted.
# Why: compaction is lossy, and a backup lets us recover the full history if a
# summary drops something important. Cheap insurance; never blocks (always
# exit 0). See the steering best-practices: PreCompact for chat-history backup.
set -uo pipefail

input="$(cat)"
src="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null || true)"
trigger="$(printf '%s' "$input" | jq -r '.trigger // "unknown"' 2>/dev/null || echo unknown)"
[ -n "$src" ] && [ -f "$src" ] || exit 0

dest_dir="$HOME/.claude/backups/transcripts"
mkdir -p "$dest_dir" || exit 0

stamp="$(date +%Y%m%d-%H%M%S)"
base="$(basename "$src")"
cp "$src" "$dest_dir/${stamp}-${trigger}-${base}" 2>/dev/null || exit 0

# Retain only the 50 most recent backups to bound disk usage.
ls -1t "$dest_dir"/*.jsonl 2>/dev/null | tail -n +51 | while IFS= read -r old; do
  rm -f "$old" 2>/dev/null || true
done

exit 0
