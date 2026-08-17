#!/usr/bin/env bash
# approve-safe-rm.sh のスモークテスト。
#
# 設計の由来・不変条件の正本: docs/adr/004-safe-rm-hook-auto-approval.md。
# 姉妹の private リポジトリでの反証検証6ラウンドで確定した設計に対する
# 固定テストであり、本ファイルは設計判断を追加・変更しない。
#
# なぜ「stdout（allowJSON か空のみ）と exit code 0 の両方」を全ケースで
# アサートするのか: 本 hook の中核保証は「allow か無出力のみを返し、
# いかなる入力・異常でも exit code 0 で終える」こと。片方だけの判定では、
# 例えば exit 2 で stdout が空のケース（=deny/blockingError の一種）を
# 見逃してしまう。deny 降格ベクタを塞いだことを回帰で固定するため、
# 常に両方を見る。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/approve-safe-rm.sh"

pass=0
fail=0

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
STDOUT_FILE="$TMP_ROOT/stdout"
STDERR_FILE="$TMP_ROOT/stderr"

# json_payload: permission_mode / agent_type / command から JSON stdin を
# 組み立てる。permission_mode / agent_type に "__OMIT__" を渡すとフィールド
# 自体を省略する（欠落ケースの再現）。手組みエスケープを避け python3 の
# json.dumps に委譲する。
json_payload() {
  local permission_mode="$1" agent_type="$2" cmd="$3"
  python3 - "$permission_mode" "$agent_type" "$cmd" <<'PYEOF'
import json, sys
permission_mode, agent_type, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
d = {"tool_input": {"command": cmd}}
if permission_mode != "__OMIT__":
    d["permission_mode"] = permission_mode
if agent_type != "__OMIT__":
    d["agent_type"] = agent_type
print(json.dumps(d))
PYEOF
}

# 便宜ヘルパー: permission_mode=default・agent_type省略の定番ケース。
cmd_json() {
  json_payload "default" "__OMIT__" "$1"
}

run_hook() {
  local json="$1"
  bash "$HOOK" <<<"$json" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  return $?
}

run_hook_with_path() {
  local json="$1" custom_path="$2"
  env -i PATH="$custom_path" HOME="$HOME" /bin/bash "$HOOK" <<<"$json" \
    >"$STDOUT_FILE" 2>"$STDERR_FILE"
  return $?
}

# assert_allow: allow JSON を stdout に出し、exit code が 0 であること。
assert_allow() {
  local label="$1" json="$2"
  local actual ok=1
  run_hook "$json"
  actual=$?
  [ "$actual" = 0 ] || ok=0
  grep -q '"permissionDecision":"allow"' "$STDOUT_FILE" || ok=0
  grep -q '"permissionDecision":"deny"' "$STDOUT_FILE" && ok=0
  grep -q '"permissionDecision":"ask"' "$STDOUT_FILE" && ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected allow, exit=0; actual exit=$actual)"
    echo "  stdout: $(cat "$STDOUT_FILE")"
    echo "  stderr: $(cat "$STDERR_FILE")"
    fail=$((fail + 1))
  fi
}

# assert_passthrough: 無出力（stdout 空）かつ exit code が 0 であること。
assert_passthrough() {
  local label="$1" json="$2"
  local actual ok=1
  run_hook "$json"
  actual=$?
  [ "$actual" = 0 ] || ok=0
  [ -s "$STDOUT_FILE" ] && ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected passthrough(empty stdout), exit=0; actual exit=$actual)"
    echo "  stdout: $(cat "$STDOUT_FILE")"
    echo "  stderr: $(cat "$STDERR_FILE")"
    fail=$((fail + 1))
  fi
}

assert_passthrough_with_path() {
  local label="$1" json="$2" custom_path="$3"
  local actual ok=1
  run_hook_with_path "$json" "$custom_path"
  actual=$?
  [ "$actual" = 0 ] || ok=0
  [ -s "$STDOUT_FILE" ] && ok=0
  if [ "$ok" = 1 ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected passthrough(empty stdout), exit=0; actual exit=$actual)"
    echo "  stdout: $(cat "$STDOUT_FILE")"
    echo "  stderr: $(cat "$STDERR_FILE")"
    fail=$((fail + 1))
  fi
}

# =========================================================================
# allow 系: 既知の安全な rm は permission_mode=default で自動承認
# =========================================================================

assert_allow "rm -rf node_modules は allow" \
  "$(cmd_json 'rm -rf node_modules')"

assert_allow "rm -rf \"dist\"（ダブルクォート）は allow" \
  "$(cmd_json 'rm -rf "dist"')"

assert_allow "rm -rf ./node_modules は allow" \
  "$(cmd_json 'rm -rf ./node_modules')"

assert_allow "rm -rf node_modules/（末尾スラッシュ）は allow" \
  "$(cmd_json 'rm -rf node_modules/')"

assert_allow "rm -rf node_modules dist（複数ターゲット全安全）は allow" \
  "$(cmd_json 'rm -rf node_modules dist')"

assert_allow "rm -rf dist; rm -rf build（純 rm 複合）は allow" \
  "$(cmd_json 'rm -rf dist; rm -rf build')"

assert_allow "rm -fr __pycache__ は allow" \
  "$(cmd_json 'rm -fr __pycache__')"

assert_allow "rm -r -f coverage は allow" \
  "$(cmd_json 'rm -r -f coverage')"

assert_allow "rm --recursive .cache は allow" \
  "$(cmd_json 'rm --recursive .cache')"

assert_allow "rm -rf -- node_modules は allow" \
  "$(cmd_json 'rm -rf -- node_modules')"

assert_allow "rm -rf packages/app/node_modules は allow" \
  "$(cmd_json 'rm -rf packages/app/node_modules')"

assert_allow "rm -rf /tmp/claude-501/p/s/scratchpad/z は allow" \
  "$(cmd_json 'rm -rf /tmp/claude-501/p/s/scratchpad/z')"

assert_allow "rm -rf /private/tmp/claude-501/p/s/scratchpad は allow" \
  "$(cmd_json 'rm -rf /private/tmp/claude-501/p/s/scratchpad')"

assert_allow "末尾改行付き rm -rf node_modules は allow（空セグメント耐性）" \
  "$(cmd_json $'rm -rf node_modules\n')"

assert_allow "rm -rf dist ;（末尾セミコロン）は allow（空セグメント耐性）" \
  "$(cmd_json 'rm -rf dist ;')"

# --- permission_mode allowlist の全4値 ---

assert_allow "permission_mode=acceptEdits でも allow" \
  "$(json_payload 'acceptEdits' '__OMIT__' 'rm -rf node_modules')"

assert_allow "permission_mode=auto でも allow" \
  "$(json_payload 'auto' '__OMIT__' 'rm -rf node_modules')"

assert_allow "permission_mode=bypassPermissions でも allow" \
  "$(json_payload 'bypassPermissions' '__OMIT__' 'rm -rf node_modules')"

# --- agent_type が gemini-consult 以外なら allow を妨げない ---

assert_allow "agent_type=tdd-strict-coder は allow を妨げない" \
  "$(json_payload 'default' 'tdd-strict-coder' 'rm -rf node_modules')"

# =========================================================================
# 素通し系: 危険・不安全・判定不能なら無出力のまま exit 0
# =========================================================================

assert_passthrough "rm -rf src（whitelist外）は素通し" \
  "$(cmd_json 'rm -rf src')"

assert_passthrough "rm -rf ../x（親ディレクトリ参照）は素通し" \
  "$(cmd_json 'rm -rf ../x')"

assert_passthrough "rm -rf ~/x（ホーム展開）は素通し" \
  "$(cmd_json 'rm -rf ~/x')"

assert_passthrough "rm -rf /etc（絶対パス・scratchpad系でない）は素通し" \
  "$(cmd_json 'rm -rf /etc')"

assert_passthrough "rm -rf \$HOME（変数展開）は素通し" \
  "$(cmd_json 'rm -rf $HOME')"

assert_passthrough "rm -rf node_modules ../secret（不安全語が後）は素通し" \
  "$(cmd_json 'rm -rf node_modules ../secret')"

assert_passthrough "rm -rf ../secret node_modules（不安全語が先）は素通し" \
  "$(cmd_json 'rm -rf ../secret node_modules')"

assert_passthrough "rm -rf dist /etc（複数ターゲットの1つが不安全）は素通し" \
  "$(cmd_json 'rm -rf dist /etc')"

assert_passthrough "rm -rf \"\"（空文字列ターゲット）は素通し" \
  "$(cmd_json 'rm -rf ""')"

assert_passthrough "rm -rf \$TMPDIR/probe（変数綴り）は素通し" \
  "$(cmd_json 'rm -rf $TMPDIR/probe')"

assert_passthrough "rm -rf \$TMPDIR/x/scratchpad/y（変数綴り+scratchpad）は素通し" \
  "$(cmd_json 'rm -rf $TMPDIR/x/scratchpad/y')"

assert_passthrough "rm -rf \${TMPDIR}/x/scratchpad（\${}綴り）は素通し" \
  "$(cmd_json 'rm -rf ${TMPDIR}/x/scratchpad')"

assert_passthrough "rm -rf \$TMPDIR/Users/rio/git/p/docs/scratchpad は素通し" \
  "$(cmd_json 'rm -rf $TMPDIR/Users/rio/git/p/docs/scratchpad')"

assert_passthrough "rm -rf /tmp/claudeXYZ/scratchpad（境界なし前方一致）は素通し" \
  "$(cmd_json 'rm -rf /tmp/claudeXYZ/scratchpad')"

assert_passthrough "rm -rf /tmp/claude-501（scratchpadセグメントなし）は素通し" \
  "$(cmd_json 'rm -rf /tmp/claude-501')"

assert_passthrough "rm -rf /tmp/claude-501/a/scratchpad/../b（..セグメント）は素通し" \
  "$(cmd_json 'rm -rf /tmp/claude-501/a/scratchpad/../b')"

assert_passthrough "rm -rf dist && npm run build（他コマンド混在）は素通し" \
  "$(cmd_json 'rm -rf dist && npm run build')"

assert_passthrough "rm -rf dist > f（リダイレクト）は素通し" \
  "$(cmd_json 'rm -rf dist > f')"

assert_passthrough "rm -rf node_modules/../..（basename が ..）は素通し" \
  "$(cmd_json 'rm -rf node_modules/../..')"

assert_passthrough "rm -rfv dist（許可外フラグ v）は素通し" \
  "$(cmd_json 'rm -rfv dist')"

assert_passthrough "/bin/rm -rf dist（パス付きargv[0]）は素通し" \
  "$(cmd_json '/bin/rm -rf dist')"

assert_passthrough "rm -rf *（glob）は素通し" \
  "$(cmd_json 'rm -rf *')"

assert_passthrough "クォート未閉鎖は素通し" \
  "$(cmd_json 'rm -rf "dist')"

# --- ブレース展開・チルダ語中混入の回帰（移植元の adversarial-verifier
#     REJECT 起因） ---
#
# シェル展開前のリテラル文字列だけを見て判定するため、ブレース展開 {} が
# 禁止文字集合から漏れていると、展開後に basename だけが whitelist に一致
# する任意パス（cwd 外・$HOME 配下を含む）を許してしまう欠陥があった。
# 実測: rm -rf {..,x}/node_modules は展開後 ../node_modules を含む。

assert_passthrough "rm -rf {..,x}/node_modules（ブレース展開で ../node_modules に到達）は素通し" \
  "$(cmd_json 'rm -rf {..,x}/node_modules')"

assert_passthrough "rm -rf {~,x}/dist（ブレース展開で \$HOME/dist に到達）は素通し" \
  "$(cmd_json 'rm -rf {~,x}/dist')"

assert_passthrough "rm -rf {~,x}/git/agent-forge/dist（ブレース展開で実在OSS配布物に到達）は素通し" \
  "$(cmd_json 'rm -rf {~,x}/git/agent-forge/dist')"

assert_passthrough "rm -rf {..,x}/{..,x}/dist（ブレースの重ねがけで任意深度の ../.. に到達）は素通し" \
  "$(cmd_json 'rm -rf {..,x}/{..,x}/dist')"

assert_passthrough "rm file.txt（whitelist外・rmだが対象外）は素通し" \
  "$(cmd_json 'rm file.txt')"

assert_passthrough "ls（rmでない）は素通し" \
  "$(cmd_json 'ls')"

# --- permission_mode allowlist 外 ---

assert_passthrough "permission_mode=plan では whitelist rm でも素通し" \
  "$(json_payload 'plan' '__OMIT__' 'rm -rf node_modules')"

assert_passthrough "permission_mode=dontAsk では whitelist rm でも素通し" \
  "$(json_payload 'dontAsk' '__OMIT__' 'rm -rf node_modules')"

assert_passthrough "permission_mode欠落では whitelist rm でも素通し" \
  "$(json_payload '__OMIT__' '__OMIT__' 'rm -rf node_modules')"

assert_passthrough "permission_mode=未知値では whitelist rm でも素通し" \
  "$(json_payload 'weirdMode' '__OMIT__' 'rm -rf node_modules')"

# --- agent_type=gemini-consult ---

assert_passthrough "agent_type=gemini-consult では whitelist rm でも素通し" \
  "$(json_payload 'default' 'gemini-consult' 'rm -rf node_modules')"

# --- 不正入力 ---

assert_passthrough "不正 JSON は素通し" \
  '{not valid json'

assert_passthrough "空入力は素通し" \
  ''

echo "----"

# =========================================================================
# jq/python3 フォールバック（PATH 制限で再現）
# =========================================================================
# 除外したいコマンド以外を実バイナリへのシンボリックリンクとして集めた
# ディレクトリに PATH を丸ごと差し替える。本 hook は stdin を読むために
# cat を要する。
NO_JQ_NO_PY3_PATH="$TMP_ROOT/no-jq-no-py3-bin"
mkdir -p "$NO_JQ_NO_PY3_PATH"
_cat_src="$(command -v cat 2>/dev/null)"
[ -n "$_cat_src" ] && ln -s "$_cat_src" "$NO_JQ_NO_PY3_PATH/cat"

# json_payload 自体が python3 に依存するため、jq/python3 不在ケースの JSON は
# ここだけ手組みで用意する（デバッグ対象がフック側であり、生成側に外部
# コマンドを使うと切り分けが曖昧になるのを避けるため）。
assert_passthrough_with_path \
  "jq・python3ともに不在 -> whitelist rm でも素通し（fail-closed 側ではなく単なる無出力）" \
  '{"permission_mode":"default","tool_input":{"command":"rm -rf node_modules"}}' \
  "$NO_JQ_NO_PY3_PATH"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
