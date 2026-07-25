#!/usr/bin/env bash
# lint-after-edit.sh のスモークテスト。
#
# なぜ bats 等の外部フレームワークを使わないのか:
# 他の hooks/*.test.sh と同様、この1ファイルのためだけに新規依存を増やすのは
# スコープ過剰。exit code + stderr の一致だけを見れば十分検証できるため、
# 素の bash + assert 関数で完結させる。
#
# なぜ実際の ruff/eslint を呼ばず PATH/node_modules にスタブを置くのか:
# CI/開発者環境にどちらかが入っていない場合でもテストが決定的に動く必要が
# ある。ruff は PATH フォールバック（command -v ruff）で拾われる実装なので
# スタブ実行ファイルを PATH 先頭に置く。eslint は find_up で
# node_modules/.bin/eslint を親方向に探す実装なので、実ディレクトリ構造の中に
# スタブを配置する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/lint-after-edit.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

# $1: label, $2: expected exit code, $3: json stdin, $4: PATH prefix to prepend (optional)
# $5: 期待する stderr 部分文字列（空なら未検証）
assert_exit() {
  local label="$1" expected="$2" json="$3" path_prefix="${4:-}" must_contain="${5:-}"
  local actual ok=1
  local run_path="$PATH"
  [ -n "$path_prefix" ] && run_path="$path_prefix:$PATH"
  PATH="$run_path" bash "$HOOK" <<<"$json" \
    >/tmp/lint-after-edit-test-stdout.$$ 2>/tmp/lint-after-edit-test-stderr.$$
  actual=$?
  [ "$actual" = "$expected" ] || ok=0
  if [ -n "$must_contain" ]; then
    grep -qF "$must_contain" /tmp/lint-after-edit-test-stderr.$$ || ok=0
  fi
  if [ "$ok" = 1 ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected actual=$actual, must_contain=[$must_contain])"
    echo "  stdout: $(cat /tmp/lint-after-edit-test-stdout.$$)"
    echo "  stderr: $(cat /tmp/lint-after-edit-test-stderr.$$)"
    fail=$((fail + 1))
  fi
  rm -f /tmp/lint-after-edit-test-stdout.$$ /tmp/lint-after-edit-test-stderr.$$
}

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# --- 対象ツール不在 / 未知拡張子 -> exit 0 ---

assert_exit "tool_input.file_path が無い payload -> exit 0（対象ツール不在）" \
  0 '{"tool_input":{}}'

nonexistent="$TMP_ROOT/does-not-exist.py"
assert_exit "file_path はあるがファイル実体が無い -> exit 0" \
  0 "$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$nonexistent")")"

unknown_ext_file="$TMP_ROOT/notes.txt"
printf 'plain text\n' > "$unknown_ext_file"
assert_exit "未知拡張子(.txt) -> exit 0" \
  0 "$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$unknown_ext_file")")"

# --- 壊れた JSON payload -> exit 0（fail-open） ---

assert_exit "壊れた JSON payload -> exit 0（fail-open）" \
  0 '{not valid json'

assert_exit "空 stdin -> exit 0（fail-open）" \
  0 ''

# --- ruff 検出（PATH フォールバック経由） ---

RUFF_STUB_DIR="$(mktemp -d "$TMP_ROOT/ruffstub.XXXXXX")"
cat > "$RUFF_STUB_DIR/ruff" <<'EOF'
#!/usr/bin/env bash
# ruff check --quiet <file> の呼び出しを模した検出ありスタブ。
echo "F401 [*] '$3' imported but unused"
exit 1
EOF
chmod +x "$RUFF_STUB_DIR/ruff"

py_file="$TMP_ROOT/dirty.py"
printf 'import os\n' > "$py_file"
assert_exit "ruff スタブが検出(exit1) -> フックは exit 2 で lint 指摘を返す" \
  2 "$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$py_file")")" \
  "$RUFF_STUB_DIR" \
  "F401"

RUFF_CLEAN_DIR="$(mktemp -d "$TMP_ROOT/ruffclean.XXXXXX")"
cat > "$RUFF_CLEAN_DIR/ruff" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$RUFF_CLEAN_DIR/ruff"

py_clean_file="$TMP_ROOT/clean.py"
printf 'x = 1\n' > "$py_clean_file"
assert_exit "ruff スタブが指摘なし(exit0) -> exit 0" \
  0 "$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$py_clean_file")")" \
  "$RUFF_CLEAN_DIR"

# --- eslint 検出（node_modules/.bin/eslint を find_up で発見する経路） ---

ESLINT_PROJ="$(mktemp -d "$TMP_ROOT/eslintproj.XXXXXX")"
mkdir -p "$ESLINT_PROJ/node_modules/.bin" "$ESLINT_PROJ/src"
cat > "$ESLINT_PROJ/node_modules/.bin/eslint" <<'EOF'
#!/usr/bin/env bash
# eslint <file> の呼び出しを模した検出ありスタブ。
echo "$1"
echo "  1:1  error  'unused' is defined but never used  no-unused-vars"
exit 1
EOF
chmod +x "$ESLINT_PROJ/node_modules/.bin/eslint"

ts_file="$ESLINT_PROJ/src/component.ts"
printf 'const unused = 1;\n' > "$ts_file"
assert_exit "eslint スタブが検出(exit1, node_modules/.bin 経由) -> フックは exit 2 で lint 指摘を返す" \
  2 "$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$ts_file")")" \
  "" \
  "no-unused-vars"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
