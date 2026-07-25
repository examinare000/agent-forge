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
export TMP_ROOT
OUT="$TMP_ROOT/out"
ERR="$TMP_ROOT/err"

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
    >"$OUT" 2>"$ERR"
  actual=$?
  [ "$actual" = "$expected" ] || ok=0
  if [ -n "$must_contain" ]; then
    grep -qF "$must_contain" "$ERR" || ok=0
  fi
  if [ "$ok" = 1 ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected actual=$actual, must_contain=[$must_contain])"
    echo "  stdout: $(cat "$OUT")"
    echo "  stderr: $(cat "$ERR")"
    fail=$((fail + 1))
  fi
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
printf '%s\n' "$*" > "$TMP_ROOT/eslint-args"
echo "${!#}"
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

RUFF_CRASH_DIR="$(mktemp -d "$TMP_ROOT/ruffcrash.XXXXXX")"
cat > "$RUFF_CRASH_DIR/ruff" <<'EOF'
#!/usr/bin/env bash
echo "Traceback: ruff crashed"
exit 2
EOF
chmod +x "$RUFF_CRASH_DIR/ruff"

assert_exit "ruff がクラッシュ(exit2) -> fail-openで exit 0" \
  0 "$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$py_file")")" \
  "$RUFF_CRASH_DIR"
if [ ! -s "$ERR" ]; then
  echo "PASS: ruff クラッシュ時は stderr が空"
  pass=$((pass + 1))
else
  echo "FAIL: ruff クラッシュ時に stderr が出力された: $(cat "$ERR")"
  fail=$((fail + 1))
fi

# --cache 書込不能（read-only な node_modules 等）で eslint が exit 2 を返す
# ケース。--cache なしで再実行すると本来の lint 指摘（exit 1）が拾えるため、
# フックはその再実行結果を採用して指摘を返さなければならない。
ESLINT_CACHE_FAIL_PROJ="$(mktemp -d "$TMP_ROOT/eslintcachefail.XXXXXX")"
mkdir -p "$ESLINT_CACHE_FAIL_PROJ/node_modules/.bin" "$ESLINT_CACHE_FAIL_PROJ/src"
cat > "$ESLINT_CACHE_FAIL_PROJ/node_modules/.bin/eslint" <<'EOF'
#!/usr/bin/env bash
# --cache 付き呼び出しはキャッシュ書込不能を模して exit 2（クラッシュ扱い）。
# --cache なし呼び出しは本来の lint 指摘を返す（exit 1）。
if printf '%s\n' "$*" | grep -q -- '--cache'; then
  echo "cache write failed: EACCES" >&2
  exit 2
fi
echo "${!#}"
echo "  1:1  error  'unused' is defined but never used  no-unused-vars"
exit 1
EOF
chmod +x "$ESLINT_CACHE_FAIL_PROJ/node_modules/.bin/eslint"
cache_fail_file="$ESLINT_CACHE_FAIL_PROJ/src/component.ts"
printf 'const unused = 1;\n' > "$cache_fail_file"
assert_exit "eslint が --cache 書込不能で exit2 -> --cacheなし再実行の指摘(exit1)を採用してフックはexit 2" \
  2 "$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$cache_fail_file")")" \
  "" \
  "no-unused-vars"

ESLINT_CRASH_PROJ="$(mktemp -d "$TMP_ROOT/eslintcrash.XXXXXX")"
mkdir -p "$ESLINT_CRASH_PROJ/node_modules/.bin" "$ESLINT_CRASH_PROJ/src"
cat > "$ESLINT_CRASH_PROJ/node_modules/.bin/eslint" <<'EOF'
#!/usr/bin/env bash
echo "eslint executable failed"
exit 127
EOF
chmod +x "$ESLINT_CRASH_PROJ/node_modules/.bin/eslint"
eslint_crash_file="$ESLINT_CRASH_PROJ/src/component.ts"
printf 'const value = 1;\n' > "$eslint_crash_file"
assert_exit "eslint が実行不能相当(exit127) -> fail-openで exit 0" \
  0 "$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$eslint_crash_file")")"

if grep -q -- '--cache' "$TMP_ROOT/eslint-args"; then
  echo "PASS: eslint 呼び出しに --cache を含む"
  pass=$((pass + 1))
else
  echo "FAIL: eslint 呼び出しに --cache が無い: $(cat "$TMP_ROOT/eslint-args")"
  fail=$((fail + 1))
fi

# jq を隠しても python3 フォールバックで file_path を抽出し lint できる。
PYTHON_ONLY_BIN="$(mktemp -d "$TMP_ROOT/pythononly.XXXXXX")"
for tool in bash cat dirname env python3; do
  real="$(command -v "$tool" 2>/dev/null || true)"
  [ -n "$real" ] && ln -s "$real" "$PYTHON_ONLY_BIN/$tool"
done
ln -s "$RUFF_STUB_DIR/ruff" "$PYTHON_ONLY_BIN/ruff"
REAL_BASH="$(command -v bash)"
PATH="$PYTHON_ONLY_BIN" "$REAL_BASH" "$HOOK" \
  <<<"$(printf '{"tool_input":{"file_path":%s}}' "$(json_escape "$py_file")")" \
  >"$OUT" 2>"$ERR"
python_fallback_rc=$?
if [ "$python_fallback_rc" = "2" ] && grep -qF "F401" "$ERR"; then
  echo "PASS: jq 不在でも python3 フォールバックで lint する"
  pass=$((pass + 1))
else
  echo "FAIL: python3 フォールバック lint (expected=2 actual=$python_fallback_rc stderr=$(cat "$ERR"))"
  fail=$((fail + 1))
fi

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
