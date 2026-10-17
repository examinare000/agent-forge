#!/usr/bin/env bash
# generators/check-private-refs.sh のテストスイート。
#
# 私有リポジトリからの移植で混入しうる個人識別子を検査スクリプトが
# 検出できること、および対象外（docs/ ・出所注記の語）を誤検出しない
# ことを確認する。検出ケースは、最小の疑似 repo を temp dir に作って
# 実行し、本体ファイルへの影響を避ける。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

# 検査スクリプトだけを入れた最小の疑似 repo を作り、そのパスを返す。
# 対象ディレクトリは各テストが必要な分だけ足す（無いディレクトリの扱いも検証対象）。
make_repo() {
  local dir
  dir="$(mktemp -d "$TMP_ROOT/repo-XXXXXX")"
  mkdir -p "$dir/generators" "$dir/rules" "$dir/docs"
  cp "$REPO_ROOT/generators/check-private-refs.sh" "$dir/generators/" 2>/dev/null || true
  echo "$dir"
}

# $1: テスト名 $2: 期待 exit code $3: 実行 repo
# $4: stdout に含まれるべき文字列（空は任意） $5: stderr に含まれるべき文字列（空は任意）
assert_result() {
  local label="$1" expected_code="$2" work_dir="$3" expect_stdout="$4" expect_stderr="$5"
  local actual_code=0 out err ok=true
  out="$(mktemp "$TMP_ROOT/stdout-XXXXXX")"
  err="$(mktemp "$TMP_ROOT/stderr-XXXXXX")"

  (cd "$work_dir" && bash generators/check-private-refs.sh >"$out" 2>"$err") || actual_code=$?

  [ "$actual_code" = "$expected_code" ] || ok=false
  if [ -n "$expect_stdout" ] && ! grep -qF -- "$expect_stdout" "$out"; then ok=false; fi
  if [ -n "$expect_stderr" ] && ! grep -qF -- "$expect_stderr" "$err"; then ok=false; fi

  if [ "$ok" = true ]; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected_code actual=$actual_code)"
    echo "  expected stdout to contain: $expect_stdout"
    echo "  expected stderr to contain: $expect_stderr"
    echo "  stdout: $(cat "$out")"
    echo "  stderr: $(cat "$err")"
    fail=$((fail + 1))
  fi
  rm -f "$out" "$err"
}

# ============================================================
# テスト1 (b): rules/ に個人パスがあると exit 1 で該当行が stderr に出る
# ============================================================
R1="$(make_repo)"
echo 'see /Users/alice/notes for details' > "$R1/rules/99-x.md"
assert_result "rules/ の個人パスを検出して exit 1 と該当行を出す" \
  1 "$R1" "" "/Users/alice/notes"

# ============================================================
# テスト2: 個人識別子が無ければ exit 0 で走査ファイル数を出す
# ============================================================
R2="$(make_repo)"
echo 'clean content' > "$R2/rules/99-clean.md"
assert_result "識別子が無ければ exit 0 で OK と走査数を出す" \
  0 "$R2" "check-private-refs: OK (1 files scanned)" ""

# ============================================================
# テスト3 (c): docs/ は対象外
# ============================================================
R3="$(make_repo)"
echo 'see /Users/alice/notes and volphid' > "$R3/docs/note.md"
assert_result "docs/ に同じ語があっても exit 0（対象外）" \
  0 "$R3" "check-private-refs: OK" ""

# ============================================================
# テスト4 (d): agentDevTemplate は対象語ではない
# ============================================================
R4="$(make_repo)"
echo '移植元: agentDevTemplate' > "$R4/rules/99-origin.md"
assert_result "agentDevTemplate は対象語でなく exit 0" \
  0 "$R4" "check-private-refs: OK" ""

# ============================================================
# テスト5: 他の代表語（私有 repo 名・Tailscale IP・MCP プレフィックス）も検出する
# ============================================================
R5="$(make_repo)"
echo 'host 100.86.1.2' > "$R5/rules/99-ip.md"
assert_result "Tailscale IP を検出して exit 1" 1 "$R5" "" "100.86.1.2"

R6="$(make_repo)"
echo 'use agent-rig here' > "$R6/rules/99-repo.md"
assert_result "私有 repo 名を検出して exit 1" 1 "$R6" "" "agent-rig"

R7="$(make_repo)"
echo 'tool mcp__plugin_shelf_shelf__consult' > "$R7/rules/99-mcp.md"
assert_result "私有 MCP プレフィックスを検出して exit 1" 1 "$R7" "" "mcp__plugin_"

# ============================================================
# テスト8 (a): 現在の repo で exit 0
# ============================================================
assert_result "現在の repo で exit 0" \
  0 "$REPO_ROOT" "check-private-refs: OK" ""

echo "----"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
