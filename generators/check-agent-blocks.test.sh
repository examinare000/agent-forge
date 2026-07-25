#!/usr/bin/env bash
# generators/check-agent-blocks.sh のテストスイート。
#
# 検査スクリプトが、generators/agent-blocks/ の正準ブロックの埋め込みを
# 検証できること、および各ケースでの exit code と出力が仕様に合致する
# ことを確認する。
#
# テスト実行時は、リポジトリ全体を temp dir へ複製してサンドボックス内で
# 検査スクリプトを実行することで、本体ファイルへの影響を避ける。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# テスト用の一時ディレクトリを作成
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

# テスト: 実行結果の検証
# $1: テスト名（日本語）
# $2: 期待される exit code
# $3: スクリプト実行時のカレントディレクトリ（TMP_ROOT 内）
# $4: 期待される stdout に含まれるべきテキスト（空文字列は「任意」）
# $5: 期待される stderr に含まれるべきテキスト（空文字列は「任意」）
assert_result() {
  local label="$1" expected_code="$2" work_dir="$3" expect_stdout="$4" expect_stderr="$5"
  local actual_code
  local stdout_file stderr_file

  stdout_file="$(mktemp "$TMP_ROOT/stdout-XXXXXX")"
  stderr_file="$(mktemp "$TMP_ROOT/stderr-XXXXXX")"

  # テスト実行
  cd "$work_dir"
  bash generators/check-agent-blocks.sh >"$stdout_file" 2>"$stderr_file" || actual_code=$?
  actual_code=${actual_code:-0}

  # exit code 検証
  if [ "$actual_code" = "$expected_code" ]; then
    # 追加の出力検証
    local stdout_ok=true stderr_ok=true

    if [ -n "$expect_stdout" ]; then
      if ! grep -qF "$expect_stdout" "$stdout_file"; then
        stdout_ok=false
      fi
    fi

    if [ -n "$expect_stderr" ]; then
      if ! grep -qF "$expect_stderr" "$stderr_file"; then
        stderr_ok=false
      fi
    fi

    if [ "$stdout_ok" = true ] && [ "$stderr_ok" = true ]; then
      echo "PASS: $label"
      pass=$((pass + 1))
    else
      echo "FAIL: $label (output mismatch)"
      if [ "$stdout_ok" = false ]; then
        echo "  expected stdout to contain: $expect_stdout"
        echo "  actual stdout: $(cat "$stdout_file")"
      fi
      if [ "$stderr_ok" = false ]; then
        echo "  expected stderr to contain: $expect_stderr"
        echo "  actual stderr: $(cat "$stderr_file")"
      fi
      fail=$((fail + 1))
    fi
  else
    echo "FAIL: $label (expected exit=$expected_code actual=$actual_code)"
    echo "  stdout: $(cat "$stdout_file")"
    echo "  stderr: $(cat "$stderr_file")"
    fail=$((fail + 1))
  fi

  rm -f "$stdout_file" "$stderr_file"
}

# ============================================================
# テスト1: 無改変複製でバリデーション成功
# ============================================================
TEST_REPO_1="$TMP_ROOT/test-repo-1"
mkdir -p "$TEST_REPO_1"
cp -R "$REPO_ROOT/agents" "$TEST_REPO_1/"
cp -R "$REPO_ROOT/skills" "$TEST_REPO_1/"
cp -R "$REPO_ROOT/generators" "$TEST_REPO_1/"

assert_result "無改変複製で exit 0 を返す" \
  0 "$TEST_REPO_1" \
  "agent-blocks: 6 blocks × 24 targets OK" \
  ""

# ============================================================
# テスト2: エージェントファイルからブロックの一部削除
# ============================================================
TEST_REPO_2="$TMP_ROOT/test-repo-2"
mkdir -p "$TEST_REPO_2"
cp -R "$REPO_ROOT/agents" "$TEST_REPO_2/"
cp -R "$REPO_ROOT/skills" "$TEST_REPO_2/"
cp -R "$REPO_ROOT/generators" "$TEST_REPO_2/"

# agents/test-runner.md の no-nesting ブロック行を削除
# no-nesting ブロックの正確な行は以下（先頭の「-」を削除して部分に）
# - **No-nesting**: サブエージェントを起動・委譲するな。自分の役割内で完遂できない分解・並列化が必要なら、必要なタスク境界をオーケストレータへ返せ。追加起動はメインセッションだけが行う。
python3 -c "import sys,io; p=sys.argv[1]; lines=[l for l in io.open(p,encoding='utf-8') if '**No-nesting**: サブエージェント' not in l]; io.open(p,'w',encoding='utf-8').writelines(lines)" "$TEST_REPO_2/agents/test-runner.md"

assert_result "エージェントファイルからno-nestingブロックを削除するとexit 1" \
  1 "$TEST_REPO_2" \
  "" \
  "no-nesting"

# ============================================================
# テスト3: stderr にブロック名と対象ファイル名の両方が出力されている
# ============================================================
# (テスト2と同じリポジトリを継続使用)
TEST_REPO_3="$TMP_ROOT/test-repo-3"
mkdir -p "$TEST_REPO_3"
cp -R "$REPO_ROOT/agents" "$TEST_REPO_3/"
cp -R "$REPO_ROOT/skills" "$TEST_REPO_3/"
cp -R "$REPO_ROOT/generators" "$TEST_REPO_3/"

# agents/tdd-strict-coder.md から no-nesting ブロックを削除
python3 -c "import sys,io; p=sys.argv[1]; lines=[l for l in io.open(p,encoding='utf-8') if '**No-nesting**: サブエージェント' not in l]; io.open(p,'w',encoding='utf-8').writelines(lines)" "$TEST_REPO_3/agents/tdd-strict-coder.md"

stderr_tmp="$(mktemp "$TMP_ROOT/stderr-verify-XXXXXX")"
cd "$TEST_REPO_3"
bash generators/check-agent-blocks.sh >/dev/null 2>"$stderr_tmp" || true

# stderr の内容を検証
if grep -qF "no-nesting.md:" "$stderr_tmp" && grep -qF "tdd-strict-coder.md" "$stderr_tmp"; then
  echo "PASS: stderr にブロック名とファイル名が含まれる"
  pass=$((pass + 1))
else
  echo "FAIL: stderr 内容不足"
  echo "  stderr: $(cat "$stderr_tmp")"
  fail=$((fail + 1))
fi
rm -f "$stderr_tmp"

# ============================================================
# テスト4: ブロックファイル自体を書き換えると不一致になる
# ============================================================
TEST_REPO_4="$TMP_ROOT/test-repo-4"
mkdir -p "$TEST_REPO_4"
cp -R "$REPO_ROOT/agents" "$TEST_REPO_4/"
cp -R "$REPO_ROOT/skills" "$TEST_REPO_4/"
cp -R "$REPO_ROOT/generators" "$TEST_REPO_4/"

# generators/agent-blocks/report-core.md の最後に 1 行追加
echo "" >> "$TEST_REPO_4/generators/agent-blocks/report-core.md"
echo "MODIFIED LINE" >> "$TEST_REPO_4/generators/agent-blocks/report-core.md"

assert_result "ブロックファイル変更で exit 1" \
  1 "$TEST_REPO_4" \
  "" \
  "report-core.md"

# ============================================================
# テスト5: agent-blocks ディレクトリが無い場合
# ============================================================
TEST_REPO_5="$TMP_ROOT/test-repo-5"
mkdir -p "$TEST_REPO_5"
cp -R "$REPO_ROOT/agents" "$TEST_REPO_5/"
cp -R "$REPO_ROOT/skills" "$TEST_REPO_5/"
cp -R "$REPO_ROOT/generators" "$TEST_REPO_5/"

# ディレクトリを削除
rm -rf "$TEST_REPO_5/generators/agent-blocks"

stderr_tmp="$(mktemp "$TMP_ROOT/stderr-nodir-XXXXXX")"
cd "$TEST_REPO_5"
bash generators/check-agent-blocks.sh >/dev/null 2>"$stderr_tmp" || actual_exit=$?
actual_exit=${actual_exit:-0}

if [ "$actual_exit" -ne 0 ]; then
  echo "PASS: agent-blocks ディレクトリなしで exit 非0"
  pass=$((pass + 1))
else
  echo "FAIL: agent-blocks ディレクトリなしなのに exit 0"
  fail=$((fail + 1))
fi

# エラーメッセージが出ているか確認
if grep -qE "No such file|FileNotFoundError" "$stderr_tmp"; then
  echo "PASS: agent-blocks ディレクトリ不在でエラーメッセージが出力されている"
  pass=$((pass + 1))
else
  echo "FAIL: agent-blocks ディレクトリ不在でもエラーメッセージがない"
  echo "  stderr: $(cat "$stderr_tmp")"
  fail=$((fail + 1))
fi
rm -f "$stderr_tmp"

# ============================================================
# 結果集計
# ============================================================
echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
