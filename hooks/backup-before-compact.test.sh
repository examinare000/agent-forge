#!/usr/bin/env bash
# backup-before-compact.sh のスモークテスト。
#
# なぜ bats 等の外部フレームワークを使わないのか:
# 他の hooks/*.test.sh と同様、この1ファイルのためだけに新規依存を増やすのは
# スコープ過剰。exit code + バックアップ先ディレクトリの実体を見れば十分
# 検証できるため、素の bash + assert 関数で完結させる。
#
# なぜ実 $HOME を使わないのか:
# フックはバックアップ先を $HOME/.claude/backups/transcripts に固定で書く
# 実装なので、実 $HOME に対して実行すると実際のバックアップディレクトリを
# 汚染する。HOME を使い捨ての一時ディレクトリへ向けて隔離する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/backup-before-compact.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# $1: label, $2: expected exit code, $3: json stdin, $4: FAKE_HOME
assert_exit() {
  local label="$1" expected="$2" json="$3" fake_home="$4"
  local actual
  HOME="$fake_home" bash "$HOOK" <<<"$json" \
    >/tmp/backup-before-compact-test-stdout.$$ 2>/tmp/backup-before-compact-test-stderr.$$
  actual=$?
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected=$expected actual=$actual)"
    echo "  stdout: $(cat /tmp/backup-before-compact-test-stdout.$$)"
    echo "  stderr: $(cat /tmp/backup-before-compact-test-stderr.$$)"
    fail=$((fail + 1))
  fi
  rm -f /tmp/backup-before-compact-test-stdout.$$ /tmp/backup-before-compact-test-stderr.$$
}

# --- payload 不正 -> exit 0 ---

FAKE_HOME_1="$(mktemp -d "$TMP_ROOT/home1.XXXXXX")"
assert_exit "壊れた JSON payload -> exit 0（fail-open）、バックアップも作られない" \
  0 '{not valid json' "$FAKE_HOME_1"
if [ ! -d "$FAKE_HOME_1/.claude/backups/transcripts" ]; then
  echo "PASS: 壊れた payload ではバックアップ先ディレクトリ自体が作られない"
  pass=$((pass + 1))
else
  echo "FAIL: 壊れた payload なのにバックアップ先ディレクトリが作られた"
  fail=$((fail + 1))
fi

FAKE_HOME_2="$(mktemp -d "$TMP_ROOT/home2.XXXXXX")"
assert_exit "transcript_path が実在しない -> exit 0" \
  0 "$(printf '{"transcript_path":%s}' "$(json_escape "$FAKE_HOME_2/does-not-exist.jsonl")")" "$FAKE_HOME_2"

# --- transcript_path を含む payload でバックアップが作られる ---

FAKE_HOME_3="$(mktemp -d "$TMP_ROOT/home3.XXXXXX")"
transcript_3="$FAKE_HOME_3/session.jsonl"
printf '{"type":"user","message":"hello"}\n' > "$transcript_3"
assert_exit "transcript_path が実在するファイル -> exit 0" \
  0 "$(printf '{"transcript_path":%s,"trigger":"manual"}' "$(json_escape "$transcript_3")")" "$FAKE_HOME_3"

dest_dir_3="$FAKE_HOME_3/.claude/backups/transcripts"
copied="$(find "$dest_dir_3" -maxdepth 1 -type f -name '*-manual-session.jsonl' 2>/dev/null | head -1)"
if [ -n "$copied" ] && grep -qF 'hello' "$copied"; then
  echo "PASS: バックアップファイルが作られ、内容が元 transcript と一致する"
  pass=$((pass + 1))
else
  echo "FAIL: バックアップファイルが作られていない、または内容不一致"
  echo "  dest_dir listing: $(ls -1 "$dest_dir_3" 2>/dev/null)"
  fail=$((fail + 1))
fi

# --- 保持数50の刈り込み ---

FAKE_HOME_4="$(mktemp -d "$TMP_ROOT/home4.XXXXXX")"
dest_dir_4="$FAKE_HOME_4/.claude/backups/transcripts"
mkdir -p "$dest_dir_4"
# 55件の使い捨てバックアップを、mtime を明示的にずらして事前に用意する
# （ls -1t の並び順が mtime に依存するため、同時刻生成による曖昧さを避ける）。
i=1
while [ "$i" -le 55 ]; do
  f="$dest_dir_4/pre-existing-$(printf '%03d' "$i").jsonl"
  printf '{}\n' > "$f"
  touch -t "202601010000.$(printf '%02d' "$((i % 60))")" "$f" 2>/dev/null || touch "$f"
  i=$((i + 1))
  sleep 0.01
done
before_count="$(find "$dest_dir_4" -maxdepth 1 -type f -name '*.jsonl' | wc -l | tr -d ' ')"

transcript_4="$FAKE_HOME_4/new-session.jsonl"
printf '{"type":"user","message":"newest"}\n' > "$transcript_4"
assert_exit "56件目のバックアップ発生後も exit 0" \
  0 "$(printf '{"transcript_path":%s,"trigger":"auto"}' "$(json_escape "$transcript_4")")" "$FAKE_HOME_4"

after_count="$(find "$dest_dir_4" -maxdepth 1 -type f -name '*.jsonl' | wc -l | tr -d ' ')"
newest_kept="$(find "$dest_dir_4" -maxdepth 1 -type f -name '*-auto-new-session.jsonl' 2>/dev/null | head -1)"
if [ "$before_count" = "55" ] && [ "$after_count" = "50" ] && [ -n "$newest_kept" ]; then
  echo "PASS: 保持数50への刈り込み（56件中最新50件のみ残り、最新分は残存）"
  pass=$((pass + 1))
else
  echo "FAIL: 保持数刈り込みが期待通りでない (before=$before_count after=$after_count newest_kept=[$newest_kept])"
  fail=$((fail + 1))
fi

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
