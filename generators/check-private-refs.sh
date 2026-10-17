#!/usr/bin/env bash
# 私有リポジトリから移植したコンテンツに、個人識別子（ホスト名・個人パス・
# 私有 repo 名・私有 MCP 名）が混入していないかを機械検出する。
#
# gitleaks は秘密情報専用でホスト名や私有 repo 名は検出しないため、
# その穴を埋める目的で CI から呼ぶ。exit 0: 混入なし / exit 1: 混入あり。
#
# 対象外: docs/ ・CHANGELOG.md ・.git/ （経緯の記録として過去の出所を書く場所）。
# agentDevTemplate は既存の出所注記（scaffold/new-project.sh 等のコメント）に
# 使われているため、意図的に対象語へ含めない。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

SCAN_DIRS=(rules skills agents claude reference dist installer scaffold)

# 置換時に 1 箇所だけ直せばよいよう、パターンは別ファイルにせずここに置く。
PATTERN='volphid|kelly|avalon|tail18a7d0|100\.86\.|100\.113\.|/Users/[a-z]+|agent-rig|personalized-claude|com\.rio\.|mcp__plugin_|kelly:8767|8768'

cd "$REPO_ROOT"

# 無い対象ディレクトリは黙って飛ばす（OSS 側で未配備のものがあり得る）。
existing=()
for d in "${SCAN_DIRS[@]}"; do
  [ -d "$d" ] && existing+=("$d")
done

if [ "${#existing[@]}" -eq 0 ]; then
  echo "check-private-refs: OK (0 files scanned)"
  exit 0
fi

# -I でバイナリを除外。grep は「一致なし=1」「エラー=2」なので区別する。
rc=0
hits="$(grep -rInE -- "$PATTERN" "${existing[@]}")" || rc=$?
if [ "$rc" -gt 1 ]; then
  echo "check-private-refs: grep failed (exit $rc)" >&2
  exit 2
fi

if [ "$rc" -eq 0 ]; then
  echo "check-private-refs: 個人識別子の疑いがある行:" >&2
  echo "$hits" >&2
  exit 1
fi

scanned="$(find "${existing[@]}" -type f | wc -l | tr -d ' ')"
echo "check-private-refs: OK ($scanned files scanned)"
