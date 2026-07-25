#!/usr/bin/env bash
# json.sh のスモークテスト。
#
# なぜ bats 等の外部フレームワークを使わないのか:
# hooks 配下の既存テストと同じく、外部依存を増やさず bash の関数契約だけを
# 決定的に検証できるため、素の bash と pass/fail カウンタで完結させる。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LIB="$SCRIPT_DIR/json.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

if [ -f "$LIB" ]; then
  # shellcheck source=./json.sh
  source "$LIB"
else
  echo "FAIL: json.sh が存在する"
  exit 1
fi

# settings-parity.test.sh の SKIP 方針に合わせる: jq も python3 も無い開発機では
# json_field が常に空文字列しか返せず、以降の全アサーションが無意味な FAIL に
# なる。判定不能なテスト前提はブロックではなくスキップとして exit 0 で倒す。
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: jq も python3 も無いため json.sh のテストをスキップします。"
  exit 0
fi

assert_output() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected=[$expected] actual=[$actual])"
    fail=$((fail + 1))
  fi
}

if json_tools_available; then
  echo "PASS: jq または python3 があれば利用可能"
  pass=$((pass + 1))
else
  echo "FAIL: 利用可能な JSON ツールを検出できない"
  fail=$((fail + 1))
fi

EMPTY_BIN="$TMP_ROOT/empty-bin"
mkdir -p "$EMPTY_BIN"
if PATH="$EMPTY_BIN" json_tools_available; then
  echo "FAIL: jq・python3 両方が無いのに利用可能と判定"
  fail=$((fail + 1))
else
  echo "PASS: jq・python3 両方が無ければ利用不可"
  pass=$((pass + 1))
fi

assert_output "トップレベル文字列を抽出" \
  "manual" "$(json_field '{"trigger":"manual"}' trigger)"
assert_output "ネストした tool_input.file_path を抽出" \
  "/tmp/example.py" "$(json_field '{"tool_input":{"file_path":"/tmp/example.py"}}' tool_input.file_path)"
assert_output "存在しないフィールドは空文字列" \
  "" "$(json_field '{"trigger":"manual"}' missing.value)"
assert_output "正しいJSONの後ろにゴミがある入力も部分値を漏らさず空文字列（fail-open）" \
  "" "$(json_field '{"trigger":"partial"} trailing garbage' trigger)"

# jq をアンインストールせず python3 だけを見せ、フォールバック経路を固定する。
PYTHON_ONLY_BIN="$TMP_ROOT/python-only-bin"
mkdir -p "$PYTHON_ONLY_BIN"
ln -s "$(command -v python3)" "$PYTHON_ONLY_BIN/python3"
assert_output "python3 フォールバックでもネストした値を抽出" \
  "/tmp/fallback.py" \
  "$(PATH="$PYTHON_ONLY_BIN" json_field '{"tool_input":{"file_path":"/tmp/fallback.py"}}' tool_input.file_path)"

if command -v jq >/dev/null 2>&1; then
  assert_output "jq 経路の bool は true" \
    "true" "$(json_field '{"active":true}' active)"
else
  # jq のみ不在（python3 経路は上のケースで検証済み）: jq 依存ケースだけを
  # 個別 SKIP し、python3 フォールバック経路のテストは続行する。
  echo "SKIP: jq 経路の bool 表記検証は jq 不在のためスキップします。"
fi
assert_output "python3 経路の bool は互換性維持のため True" \
  "True" "$(PATH="$PYTHON_ONLY_BIN" json_field '{"active":true}' active)"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
