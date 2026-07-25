#!/usr/bin/env bash
# claude/settings.base.json と hooks/ 実体・installer/manifest.json の整合性テスト。
#
# なぜこのテストが要るか:
# hook をリネーム/削除したときに settings.base.json の command 側の更新を
# 出荷し忘れると、インストール先でフックが「ファイルが無いのに設定だけ残る」
# 壊れ方をする。この事故は他のテストでは検出できない（各 *.sh 単体テストは
# ファイルが存在する前提で動くため）。
#
# なぜ jq 必須（fail-open）なのか:
# JSON のネスト構造検査は jq がある方が確実で読みやすい。CI では jq は
# prereqs required に含まれるため常に存在するが、開発機でローカル実行する
# ケースを考慮し、jq が無ければ検査をスキップして exit 0 とする
# （hooks/lib/json.sh の python3 フォールバックをここでは使わない —
# ネスト配列の走査を素の python3 で書き直すコストに見合わないため）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
SETTINGS="${ROOT}/claude/settings.base.json"
MANIFEST="${ROOT}/installer/manifest.json"

pass=0
fail=0

assert_true() {
  local label="$1"
  shift
  if "$@"; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label}"
    fail=$((fail + 1))
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq 不在のため settings-parity テストをスキップします。"
  exit 0
fi

echo "=== ①: settings.base.json は valid JSON ==="
assert_true "settings.base.json は valid JSON" \
  jq empty "${SETTINGS}"

echo ""
echo "=== ②: 全 hook command が \$HOME/.claude/hooks/<name>.sh 形式 ==="
while IFS= read -r cmd; do
  [ -n "${cmd}" ] || continue
  if printf '%s' "${cmd}" | grep -qE '^\$HOME/\.claude/hooks/[^/]+\.sh$'; then
    echo "PASS: command 形式が正しい (${cmd})"
    pass=$((pass + 1))
  else
    echo "FAIL: command 形式が不正 (${cmd})"
    fail=$((fail + 1))
  fi
done < <(jq -r '.hooks[][].hooks[].command' "${SETTINGS}")

echo ""
echo "=== ③: 参照された hook 実体が hooks/ に存在し実行可能 ==="
while IFS= read -r cmd; do
  [ -n "${cmd}" ] || continue
  name="${cmd##*/}"
  target="${ROOT}/hooks/${name}"
  if [ -f "${target}" ] && [ -x "${target}" ]; then
    echo "PASS: hooks/${name} が存在し実行可能"
    pass=$((pass + 1))
  else
    echo "FAIL: hooks/${name} が存在しないか実行不可（command=${cmd}）"
    fail=$((fail + 1))
  fi
done < <(jq -r '.hooks[][].hooks[].command' "${SETTINGS}")

echo ""
echo "=== ④: 全 hook に数値 timeout が設定されている ==="
while IFS= read -r timeout; do
  if printf '%s' "${timeout}" | grep -qE '^[0-9]+$'; then
    echo "PASS: timeout が数値 (${timeout})"
    pass=$((pass + 1))
  else
    echo "FAIL: timeout が数値でない (${timeout})"
    fail=$((fail + 1))
  fi
done < <(jq -r '.hooks[][].hooks[].timeout' "${SETTINGS}")

echo ""
echo "=== ⑤: manifest.json は valid JSON ==="
assert_true "manifest.json は valid JSON" \
  jq empty "${MANIFEST}"

echo ""
echo "----"
echo "pass=${pass} fail=${fail}"
[ "${fail}" -eq 0 ]
