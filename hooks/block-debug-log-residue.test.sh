#!/usr/bin/env bash
# block-debug-log-residue.sh のスモークテスト。
#
# なぜ bats 等の外部フレームワークを使わないのか:
# この1ファイルのためだけに新規依存を増やすのはスコープ過剰。exit code とstderr内容の
# 一致だけを見れば十分検証できるため、素の bash + assert 関数で完結させる。
#
# なぜ実リポジトリ（このプロジェクト自体や ~/.claude）を使わないのか:
# フックは git diff を走らせて未コミット差分の内容を読む実装なので、実環境に対して
# 実行すると意図しない検出/誤検出が起きうる。mktemp -d の使い捨て git repo だけを
# 対象にし、TMP_ROOT 配下にまとめて trap で確実に掃除する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/block-debug-log-residue.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

# --- ヘルパ ---

# 使い捨て git repo を作り、そのパスを stdout に返す。
# 初期コミットを1つ積んで HEAD を born 状態にする（unborn HEAD 専用ケースは
# このヘルパを使わず個別に git init する）。
make_repo() {
  local dir
  dir="$(mktemp -d "$TMP_ROOT/repo.XXXXXX")"
  git init -q "$dir"
  git -C "$dir" -c user.name=t -c user.email=t@t.example \
    commit -q -m init --allow-empty
  printf '%s' "$dir"
}

# ファイルを書いてコミットする（追跡済み・クリーンな初期状態を作る用途）。
commit_file() {
  local dir="$1" path="$2" content="$3"
  mkdir -p "$dir/$(dirname "$path")"
  printf '%s' "$content" >"$dir/$path"
  git -C "$dir" add "$path"
  git -C "$dir" -c user.name=t -c user.email=t@t.example \
    commit -q -m "add $path"
}

# ファイルを書くだけ（未stageの作業ツリー変更を作る用途）。
write_file() {
  local dir="$1" path="$2" content="$3"
  mkdir -p "$dir/$(dirname "$path")"
  printf '%s' "$content" >"$dir/$path"
}

stage_file() {
  git -C "$1" add "$2"
}

# $1: label, $2: expected exit code, $3: json stdin, $4: (optional) cd先ディレクトリ
# $4 を指定すると、そのディレクトリを $PWD としてフックを実行する
# （JSONにcwdフィールドが無いケースの $PWD フォールバック検証用）。
assert_exit() {
  local label="$1" expected="$2" json="$3" dir="${4:-}"
  local actual
  if [ -n "$dir" ]; then
    (cd "$dir" && bash "$HOOK" <<<"$json") \
      >/tmp/debug-log-residue-test-stdout.$$ 2>/tmp/debug-log-residue-test-stderr.$$
  else
    bash "$HOOK" <<<"$json" \
      >/tmp/debug-log-residue-test-stdout.$$ 2>/tmp/debug-log-residue-test-stderr.$$
  fi
  actual=$?
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected=$expected actual=$actual)"
    echo "  stdout: $(cat /tmp/debug-log-residue-test-stdout.$$)"
    echo "  stderr: $(cat /tmp/debug-log-residue-test-stderr.$$)"
    fail=$((fail + 1))
  fi
  rm -f /tmp/debug-log-residue-test-stdout.$$ /tmp/debug-log-residue-test-stderr.$$
}

# $1: label, $2: expected exit code, $3: stderr に含まれるべき文字列, $4: json stdin
assert_stderr_contains() {
  local label="$1" expected="$2" needle="$3" json="$4"
  local actual
  bash "$HOOK" <<<"$json" \
    >/tmp/debug-log-residue-test-stdout.$$ 2>/tmp/debug-log-residue-test-stderr.$$
  actual=$?
  if [ "$actual" = "$expected" ] && grep -qF "$needle" /tmp/debug-log-residue-test-stderr.$$; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected_exit=$expected actual=$actual needle=$needle)"
    echo "  stderr: $(cat /tmp/debug-log-residue-test-stderr.$$)"
    fail=$((fail + 1))
  fi
  rm -f /tmp/debug-log-residue-test-stdout.$$ /tmp/debug-log-residue-test-stderr.$$
}

# =========================================================================
# 1. stop_hook_active=true はループガードとして最優先（違反ありrepoでも許可）
# =========================================================================
repo1="$(make_repo)"
commit_file "$repo1" foo.sh $'line1\n'
write_file "$repo1" foo.sh $'line1\n[DEBUG] leftover\n'
assert_exit "1. stop_hook_active=true は違反ありrepoでも許可（ループガード）" \
  0 '{"stop_hook_active":true,"cwd":"'"$repo1"'"}'

# =========================================================================
# 2. stop_hook_active="True"（python3フォールバックのPython bool str()表記）も許可
# =========================================================================
repo2="$(make_repo)"
commit_file "$repo2" foo.sh $'line1\n'
write_file "$repo2" foo.sh $'line1\n[DEBUG] leftover\n'
assert_exit "2. stop_hook_active=\"True\" も許可（jq/python3フォールバック両対応）" \
  0 '{"stop_hook_active":"True","cwd":"'"$repo2"'"}'

# =========================================================================
# 3. 非gitディレクトリのcwd -> 許可
# =========================================================================
nongit_dir="$(mktemp -d "$TMP_ROOT/nongit.XXXXXX")"
assert_exit "3. 非gitディレクトリのcwdは許可" \
  0 '{"cwd":"'"$nongit_dir"'"}'

# =========================================================================
# 4. クリーンなrepo -> 許可
# =========================================================================
repo4="$(make_repo)"
commit_file "$repo4" foo.sh $'line1\n'
assert_exit "4. クリーンなrepoは許可" \
  0 '{"cwd":"'"$repo4"'"}'

# =========================================================================
# 5. 未stageの追加行 [DEBUG] -> ブロック
# =========================================================================
repo5="$(make_repo)"
commit_file "$repo5" foo.sh $'line1\n'
write_file "$repo5" foo.sh $'line1\n[DEBUG] leftover\n'
assert_exit "5. 未stageの追加行 [DEBUG] をブロック" \
  2 '{"cwd":"'"$repo5"'"}'

# =========================================================================
# 6. stage済みのみの追加行 [TRACE] -> ブロック
# =========================================================================
repo6="$(make_repo)"
commit_file "$repo6" foo.sh $'line1\n'
write_file "$repo6" foo.sh $'line1\n[TRACE] leftover\n'
stage_file "$repo6" foo.sh
assert_exit "6. stage済みのみの追加行 [TRACE] をブロック" \
  2 '{"cwd":"'"$repo6"'"}'

# =========================================================================
# 7. コミット済み既存の[DEBUG]・新規変更なし -> 許可（修正不能ゲート回避）
# =========================================================================
repo7="$(make_repo)"
commit_file "$repo7" foo.sh $'line1\n[DEBUG] already committed\n'
assert_exit "7. コミット済み既存の[DEBUG]は新規差分が無ければ許可" \
  0 '{"cwd":"'"$repo7"'"}'

# =========================================================================
# 8. [DEBUG]行を削除するだけのdiff -> 許可
# =========================================================================
repo8="$(make_repo)"
commit_file "$repo8" foo.sh $'line1\n[DEBUG] old\n'
write_file "$repo8" foo.sh $'line1\n'
assert_exit "8. [DEBUG]行を削除するだけのdiffは許可" \
  0 '{"cwd":"'"$repo8"'"}'

# =========================================================================
# 9. README.md への追加 -> 除外され許可
# =========================================================================
repo9="$(make_repo)"
commit_file "$repo9" README.md $'title\n'
write_file "$repo9" README.md $'title\n[DEBUG] note\n'
assert_exit "9. README.md への追加は除外され許可" \
  0 '{"cwd":"'"$repo9"'"}'

# =========================================================================
# 10. foo.test.sh への追加 -> 除外され許可
# =========================================================================
repo10="$(make_repo)"
write_file "$repo10" foo.test.sh $'[DEBUG] in test file\n'
stage_file "$repo10" foo.test.sh
assert_exit "10. foo.test.sh への追加は除外され許可" \
  0 '{"cwd":"'"$repo10"'"}'

# =========================================================================
# 11. tests/helper.py への追加 -> 除外され許可
# =========================================================================
repo11="$(make_repo)"
write_file "$repo11" tests/helper.py $'[DEBUG] in tests dir\n'
stage_file "$repo11" tests/helper.py
assert_exit "11. tests/helper.py への追加は除外され許可" \
  0 '{"cwd":"'"$repo11"'"}'

# =========================================================================
# 12. fixtures/sample.txt への追加 -> 除外され許可
# =========================================================================
repo12="$(make_repo)"
write_file "$repo12" fixtures/sample.txt $'[DEBUG] in fixtures dir\n'
stage_file "$repo12" fixtures/sample.txt
assert_exit "12. fixtures/sample.txt への追加は除外され許可" \
  0 '{"cwd":"'"$repo12"'"}'

# =========================================================================
# 13. 未追跡ファイル内の [DEBUG] -> 走査対象外で許可
# =========================================================================
repo13="$(make_repo)"
write_file "$repo13" untracked.sh $'[DEBUG] never added\n'
assert_exit "13. 未追跡ファイル内の [DEBUG] は走査対象外で許可" \
  0 '{"cwd":"'"$repo13"'"}'

# =========================================================================
# 14. JSONにcwdフィールドが無い -> $PWDにフォールバックしてブロック
# =========================================================================
repo14="$(make_repo)"
commit_file "$repo14" foo.sh $'line1\n'
write_file "$repo14" foo.sh $'line1\n[DEBUG] leftover\n'
assert_exit "14. JSONにcwd無し時は\$PWDにフォールバックしてブロック" \
  2 '{}' "$repo14"

# =========================================================================
# 15. 壊れたstdin（非repo cwd）-> 許可（fail-open）
# 空stdin '' も同じ get_field パース失敗経路（jq/python3ともに空文字列を返す）
# を通るため、壊れたJSON1本の検証で経路としては等価に確認できる。
# =========================================================================
assert_exit "15. 壊れたJSONは非repo cwdで許可（パース失敗時のfail-open）" \
  0 '{not valid json' "$nongit_dir"

# =========================================================================
# 16. unborn HEAD + stage済み違反 -> 許可（fail-openの残余として意図的に受容）
# =========================================================================
repo16="$(mktemp -d "$TMP_ROOT/repo.XXXXXX")"
git init -q "$repo16"
write_file "$repo16" foo.sh $'[DEBUG] before first commit\n'
stage_file "$repo16" foo.sh
assert_exit "16. unborn HEAD + stage済み違反は許可（fail-openの残余、意図的受容）" \
  0 '{"cwd":"'"$repo16"'"}'

# =========================================================================
# 17. file:line 正確性: 3行目に追加した行番号が stderr に正しく出る
# =========================================================================
repo17="$(make_repo)"
commit_file "$repo17" foo.sh $'line1\nline2\n'
write_file "$repo17" foo.sh $'line1\nline2\n[DEBUG] third line\n'
assert_stderr_contains "17. file:line 正確性: foo.sh:3 を含めてブロック" \
  2 "foo.sh:3" '{"cwd":"'"$repo17"'"}'

# =========================================================================
# 18. 複数ファイルの違反を全件列挙 / フック自身と同名ファイルは自己除外
# 単一シナリオに3条件（fileA検出・fileB検出・自己除外）をまとめて検証する。
# =========================================================================
repo18="$(make_repo)"
commit_file "$repo18" fileA.sh $'a\n'
commit_file "$repo18" fileB.sh $'b\n'
commit_file "$repo18" block-debug-log-residue.sh $'orig\n'
write_file "$repo18" fileA.sh $'a\n[DEBUG] violation A\n'
write_file "$repo18" fileB.sh $'b\n[TRACE] violation B\n'
write_file "$repo18" block-debug-log-residue.sh $'orig\n[DEBUG] self should be excluded\n'

label18="18. 複数ファイル違反を全件列挙しつつフック自身は自己除外"
bash "$HOOK" <<<'{"cwd":"'"$repo18"'"}' \
  >/tmp/debug-log-residue-test-stdout.$$ 2>/tmp/debug-log-residue-test-stderr.$$
actual18=$?
if [ "$actual18" = "2" ] \
  && grep -qF "fileA.sh" /tmp/debug-log-residue-test-stderr.$$ \
  && grep -qF "fileB.sh" /tmp/debug-log-residue-test-stderr.$$ \
  && ! grep -q "block-debug-log-residue.sh:" /tmp/debug-log-residue-test-stderr.$$; then
  echo "PASS: $label18"
  pass=$((pass + 1))
else
  echo "FAIL: $label18 (actual=$actual18)"
  echo "  stderr: $(cat /tmp/debug-log-residue-test-stderr.$$)"
  fail=$((fail + 1))
fi
rm -f /tmp/debug-log-residue-test-stdout.$$ /tmp/debug-log-residue-test-stderr.$$

# =========================================================================
# 19. スペースを含む .md パス: git は "+++ b/path" 行のパスがスペースを含む場合
#    末尾にリテラルTABを付与する（core.quotePath=false でも）。これをtrimしな
#    いと `.md$` のアンカー一致が「.md<TAB>」に対して失敗し、除外漏れでブロック
#    される（レビュー指摘・実git出力で再現確認済み）。
# =========================================================================
repo19="$(make_repo)"
commit_file "$repo19" "release notes.md" $'title\n'
write_file "$repo19" "release notes.md" $'title\n[DEBUG] note\n'
assert_exit "19. スペースを含む .md パスは末尾TABをtrimして除外され許可" \
  0 '{"cwd":"'"$repo19"'"}'

# =========================================================================
# 20. jq・python3 両方が不在 -> fail-open（ループガード死の回避）
#    get_field は両ツール不在時に常に空文字列を返す実装のため、これを検出せず
#    進行すると stop_hook_active 判定が常に不成立になり、「一度ブロックされ
#    たら次の停止で必ず通過する」契約が壊れて永久ブロック経路になる。
#    実際の jq/python3 をアンインストールせず、PATH を jq/python3 を含まない
#    最小ディレクトリに絞ったサブシェルでフックを実行することで再現する。
# =========================================================================
make_min_path() {
  local dir="$1"
  mkdir -p "$dir"
  local tool real
  for tool in cat git awk; do
    real="$(command -v "$tool" 2>/dev/null || true)"
    [ -n "$real" ] && ln -sf "$real" "$dir/$tool"
  done
  printf '%s' "$dir"
}
minbin="$(make_min_path "$TMP_ROOT/minbin")"
# PATH="$minbin" bash ... と書くと、上書き後のPATHで "bash" 自体の探索も
# 行われてしまい bash が見つからず失敗する（POSIXの一時的変数代入は、代入後の
# 環境でコマンド名自体も探索する）。"/" を含む絶対パスで呼べばPATH探索を経由
# しないため、事前に実体を解決しておく。
REAL_BASH="$(command -v bash)"

repo20="$(make_repo)"
commit_file "$repo20" foo.sh $'line1\n'
write_file "$repo20" foo.sh $'line1\n[DEBUG] leftover\n'

label20="20. jq/python3両不在時はfail-open（ループガード永久ブロック回避）"
# jq/python3 が両方不在だと get_field は JSON を一切パースできず "cwd" 抽出も
# 失敗する（stop_hook_active だけでなく全フィールドが空文字列になる）。よって
# $PWD フォールバック側も違反ありrepoに固定しないと、テスト実行時のカレント
# ディレクトリに結果が左右される不安定なテストになってしまう。cd で確実に
# repo20 に固定した上で、JSONにも同じcwdを冗長に渡す。
(cd "$repo20" && PATH="$minbin" "$REAL_BASH" "$HOOK" <<<'{"cwd":"'"$repo20"'"}') \
  >/tmp/debug-log-residue-test-stdout.$$ 2>/tmp/debug-log-residue-test-stderr.$$
actual20=$?
if [ "$actual20" = "0" ]; then
  echo "PASS: $label20 (exit=$actual20)"
  pass=$((pass + 1))
else
  echo "FAIL: $label20 (expected=0 actual=$actual20)"
  echo "  stderr: $(cat /tmp/debug-log-residue-test-stderr.$$)"
  fail=$((fail + 1))
fi
rm -f /tmp/debug-log-residue-test-stdout.$$ /tmp/debug-log-residue-test-stderr.$$

# =========================================================================
# 21. 自己除外の厳密化: サブストリング一致ではなく、ファイル名（basename）が
#    "block-debug-log-residue." で始まる場合のみ除外する。
#    "myblock-debug-log-residue.sh" のようにサブストリングとしてのみ含む
#    無関係なファイルは、旧実装（部分一致）では誤って除外されていた。
# =========================================================================
repo21="$(make_repo)"
commit_file "$repo21" "myblock-debug-log-residue.sh" $'orig\n'
write_file "$repo21" "myblock-debug-log-residue.sh" $'orig\n[DEBUG] should not be excluded\n'
assert_exit "21. 自己除外はbasename前方一致のみ: 無関係な部分一致ファイルはブロック" \
  2 '{"cwd":"'"$repo21"'"}'

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
