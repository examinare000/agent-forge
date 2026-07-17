#!/usr/bin/env bash
# Stop hook: block session stop while uncommitted diffs contain newly-added
# [DEBUG]/[TRACE] log lines.
#
# Why: CLAUDE.md の規約「デバッグログは一時的・専用コミットで削除」は繰り返し
# 破られやすい。determinism ladder（rule -> reminder -> hook）に従い、繰り返し
# 破られる規約はセッション停止という決定論的なタイミングで機械的にブロックする
# 段へ降格させる。
#
# Why fail-open everywhere: これは衛生ゲート（hygiene gate）であってセキュリティ
# 境界ではない。判定に迷う状況（git不在・cwd不正・JSON壊れ・unborn HEAD等）は
# すべて許可（exit 0）側に倒す。ユーザーをセッション終了不能に追い込むことの方が
# デバッグログの一時的な見逃しより害が大きい。
set -uo pipefail

input="$(cat)"

# --- JSON field extraction with jq/python3 fallback ---
# jq が無い環境での動作保障のため、jq とpython3 の両方での
# パース実装を用意。どちらでも外部依存を最小化する設計。
get_field() {
  local field="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r ".${field} // empty" 2>/dev/null || true
  else
    printf '%s' "$input" | python3 -c "import sys,json;
try:
    d=json.load(sys.stdin); print(d.get('$field','') or '')
except Exception:
    print('')" 2>/dev/null || true
  fi
}

# 1. jq・python3が両方とも不在なら、JSONを一切パースできず get_field は常に
#    空文字列を返す。これを検出せずに進行すると、直後の stop_hook_active
#    判定が常に不成立になり、「一度ブロックされたら次の停止で必ず通過する」
#    という文書化された契約（停止1回につき最大1回のブロック）が壊れて永久
#    ブロック経路になってしまう。判定不能なゲートは開ける（fail-open）。
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

# 2. ループガード: stop_hook_active が立っていれば、このフック自身が直前の
#    停止で既に一度ブロック済みということ。停止1回につき最大1回のブロックに
#    するため、ここでは常に許可する。
#    python3 フォールバックは JSON の bool を Python の bool にデコードした後
#    str() 相当で埋め込むため "True"（先頭大文字）になる。jq 経路の "true"
#    （小文字）と両方に対応する必要がある。
stop_hook_active="$(get_field stop_hook_active)"
if [ "$stop_hook_active" = "true" ] || [ "$stop_hook_active" = "True" ]; then
  exit 0
fi

# 3. cwd 解決とgit前提の検証。すべて失敗時は許可。
cwd="$(get_field cwd)"
[ -n "$cwd" ] || cwd="$PWD"

[ -d "$cwd" ] || exit 0
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
# unborn HEAD（コミットが1つも無い repo）は diff の意味が無いため許可。
# fail-open の残余として意図的に受容（新規repo初回コミット前にstageした
# デバッグログは、このゲートでは捕まえられない）。
git -C "$cwd" rev-parse --verify -q HEAD >/dev/null 2>&1 || exit 0

# 4. 未コミットの新規追加行のみを走査する。
#    GIT_OPTIONAL_LOCKS=0: 停止処理中に他プロセスの index.lock と競合しても
#    フックが失敗しないようにする（index を書き換えない diff 系コマンドなので
#    ロック取得自体が本質的に不要）。
#    未追跡ファイルは対象外（`git diff` の既定動作）: スクラッチ置き場等の
#    誤爆を避けるトレードオフとして受け入れる。
findings="$(
  {
    GIT_OPTIONAL_LOCKS=0 git -C "$cwd" -c core.quotePath=false \
      diff --unified=0 --no-color --no-ext-diff 2>/dev/null
    GIT_OPTIONAL_LOCKS=0 git -C "$cwd" -c core.quotePath=false \
      diff --cached --unified=0 --no-color --no-ext-diff 2>/dev/null
  } | awk '
    # "+++ b/path" 行でファイル名を捕捉する。削除された側の "+++ /dev/null"
    # はファイル無し（file=""）にリセットする——このファイルには追加行が
    # 存在し得ないので実害は無いが、意味的に正しくしておく。
    # 末尾TABのtrimが必要な理由: git はパスにスペースを含む場合、
    # core.quotePath=false でも "+++ b/release notes.md<TAB>" のように末尾に
    # リテラルTABを付与する（実gitで再現確認済み）。trimしないと
    # "release notes.md<TAB>" が `.md$` 等のアンカー付き除外パターンに一致
    # しなくなり、除外漏れでブロックしてしまう。
    /^\+\+\+ / {
      file = $0
      sub(/^\+\+\+ /, "", file)
      sub(/^b\//, "", file)
      sub(/\t$/, "", file)
      if (file == "/dev/null") { file = "" }
      next
    }
    # "@@ -a,b +c,d @@" のハント見出しから追加側の開始行番号 c を取り出す。
    /^@@/ {
      line = $0
      match(line, /\+[0-9]+/)
      lineno = substr(line, RSTART + 1, RLENGTH - 1) + 0
      next
    }
    # "+++" ヘッダ自身を誤って追加行として扱わないよう明示的に除外する。
    /^\+/ && !/^\+\+\+/ {
      if (file != "" \
          && file !~ /\.md$/ \
          && file !~ /\.test\./ \
          && file !~ /_test\./ \
          && file !~ /(^|\/)tests?\// \
          && file !~ /(^|\/)fixtures\// \
          && file !~ /(^|\/)block-debug-log-residue\./) {
        content = $0
        sub(/^\+/, "", content)
        if (content ~ /\[(DEBUG|TRACE)\]/) {
          print file ":" lineno ": " content
        }
      }
      lineno++
      next
    }
  '
)"

# 5. 空なら許可、非空ならブロック。
[ -n "$findings" ] || exit 0

cat >&2 <<EOF
🧹 デバッグログの残置を検出しました（未コミットの新規追加行のみを走査）。

$findings

CLAUDE.md の規約により、デバッグログは専用コミット「削除: 不要なデバッグログ」で削除してください。

デバッグ継続中で意図的に残している場合: その旨をユーザーに報告し、そのまま再度停止すれば通過します（本ブロックは停止1回につき最大1回です）。
EOF
exit 2
