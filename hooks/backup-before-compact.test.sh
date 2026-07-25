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
OUT="$TMP_ROOT/out"
ERR="$TMP_ROOT/err"

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
    >"$OUT" 2>"$ERR"
  actual=$?
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected=$expected actual=$actual)"
    echo "  stdout: $(cat "$OUT")"
    echo "  stderr: $(cat "$ERR")"
    fail=$((fail + 1))
  fi
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

# --- HOME 不在 -> exit 0 ---

transcript_no_home="$TMP_ROOT/no-home-session.jsonl"
printf '{"type":"user"}\n' > "$transcript_no_home"
json_no_home="$(printf '{"transcript_path":%s,"trigger":"manual"}' "$(json_escape "$transcript_no_home")")"
env -u HOME bash "$HOOK" <<<"$json_no_home" >"$OUT" 2>"$ERR"
no_home_rc=$?
if [ "$no_home_rc" = "0" ] && [ ! -s "$OUT" ] && [ ! -s "$ERR" ]; then
  echo "PASS: HOME が未設定でも無出力で fail-open"
  pass=$((pass + 1))
else
  echo "FAIL: HOME 未設定時の fail-open (exit=$no_home_rc)"
  echo "  stdout: $(cat "$OUT")"
  echo "  stderr: $(cat "$ERR")"
  fail=$((fail + 1))
fi

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
# （最古ファイルの比較が mtime に依存するため、同時刻生成による曖昧さを避ける）。
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

# --- trigger のパストラバーサル防止 ---

FAKE_HOME_5="$(mktemp -d "$TMP_ROOT/home5.XXXXXX")"
transcript_5="$FAKE_HOME_5/session.jsonl"
printf '{"type":"user"}\n' > "$transcript_5"
assert_exit "危険な trigger でも exit 0" \
  0 "$(printf '{"transcript_path":%s,"trigger":"../../evil name"}' "$(json_escape "$transcript_5")")" "$FAKE_HOME_5"
dest_dir_5="$FAKE_HOME_5/.claude/backups/transcripts"
safe_count="$(find "$dest_dir_5" -maxdepth 1 -type f | wc -l | tr -d ' ')"
outside_count="$(find "$FAKE_HOME_5" -type f ! -path "$transcript_5" ! -path "$dest_dir_5/*" | wc -l | tr -d ' ')"
if [ "$safe_count" = "1" ] && [ "$outside_count" = "0" ]; then
  echo "PASS: 危険な trigger は無害化されバックアップ先外へ書かない"
  pass=$((pass + 1))
else
  echo "FAIL: trigger 無害化 (inside=$safe_count outside=$outside_count)"
  fail=$((fail + 1))
fi

# --- 同一秒・同一入力でも PID nonce により衝突しない ---

FAKE_HOME_6="$(mktemp -d "$TMP_ROOT/home6.XXXXXX")"
transcript_6="$FAKE_HOME_6/session.jsonl"
printf '{"type":"user"}\n' > "$transcript_6"
json6="$(printf '{"transcript_path":%s,"trigger":"manual"}' "$(json_escape "$transcript_6")")"
HOME="$FAKE_HOME_6" bash "$HOOK" <<<"$json6" >"$OUT" 2>"$ERR" &
pid_a=$!
HOME="$FAKE_HOME_6" bash "$HOOK" <<<"$json6" >"$TMP_ROOT/out2" 2>"$TMP_ROOT/err2" &
pid_b=$!
wait "$pid_a"
rc_a=$?
wait "$pid_b"
rc_b=$?
collision_count="$(find "$FAKE_HOME_6/.claude/backups/transcripts" -maxdepth 1 -type f -name '*-manual-session.jsonl' | wc -l | tr -d ' ')"
if [ "$rc_a" = "0" ] && [ "$rc_b" = "0" ] && [ "$collision_count" = "2" ]; then
  echo "PASS: 同一秒の2プロセスでもバックアップ2件が残る"
  pass=$((pass + 1))
else
  echo "FAIL: 同一秒衝突回避 (rc_a=$rc_a rc_b=$rc_b count=$collision_count)"
  fail=$((fail + 1))
fi

# --- 拡張子を限定せず全バックアップを50件へ刈り込む ---

FAKE_HOME_7="$(mktemp -d "$TMP_ROOT/home7.XXXXXX")"
dest_dir_7="$FAKE_HOME_7/.claude/backups/transcripts"
mkdir -p "$dest_dir_7"
i=1
while [ "$i" -le 30 ]; do
  printf '{}\n' > "$dest_dir_7/pre-existing-$(printf '%02d' "$i").jsonl"
  printf 'text\n' > "$dest_dir_7/pre-existing-$(printf '%02d' "$i").txt"
  i=$((i + 1))
done
transcript_7="$FAKE_HOME_7/new-session.jsonl"
printf '{"type":"user"}\n' > "$transcript_7"
assert_exit "混在拡張子61件からの刈り込みも exit 0" \
  0 "$(printf '{"transcript_path":%s,"trigger":"auto"}' "$(json_escape "$transcript_7")")" "$FAKE_HOME_7"
all_count="$(find "$dest_dir_7" -maxdepth 1 -type f | wc -l | tr -d ' ')"
if [ "$all_count" = "50" ]; then
  echo "PASS: .jsonl と .txt を合わせた総数が50件に刈り込まれる"
  pass=$((pass + 1))
else
  echo "FAIL: 全拡張子の刈り込み後件数 (expected=50 actual=$all_count)"
  fail=$((fail + 1))
fi

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
