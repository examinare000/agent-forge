#!/usr/bin/env bash
# Stop hook: 未コミット差分に新規追加の [DEBUG]/[TRACE] が残る間は停止をブロックする。
#
# Why: CLAUDE.md の規約「デバッグログは一時的・専用コミットで削除」は繰り返し
# 破られやすい。determinism ladder（rule -> reminder -> hook）に従い、繰り返し
# 破られる規約はセッション停止という決定論的なタイミングで機械的にブロックする
# 段へ降格させる。
#
# Why: 全経路を fail-open にする。これは衛生ゲートであってセキュリティ
# 境界ではない。判定に迷う状況（git不在・cwd不正・JSON壊れ・unborn HEAD等）は
# すべて許可（exit 0）側に倒す。ユーザーをセッション終了不能に追い込むことの方が
# デバッグログの一時的な見逃しより害が大きい。
set -uo pipefail

# hooks ディレクトリ全体だけでなく個別ファイルが symlink の場合も、共有 lib を
# 実体側から読めるようにする。readlink -f は macOS 標準に無いため使わない。
hook_source="${BASH_SOURCE[0]}"
# 反復上限ガード: 真の循環symlink（a→b→a）は、このループへ到達する前に
# OS自身のsymlink解決（open(2)のMAXSYMLINKS）がELOOPで弾く（実測: macOSで
# 32ホップ）ため、循環そのものはbash起動時点で必ず失敗し無限ループにはなら
# ない。このガードが実際に保護するのは、OSの上限内で開けてしまう「正当だが
# 異常に長い」symlinkチェーンで、そのまま辿るとhookタイムアウトの原因になり
# 得るケース。OSの上限より十分小さい値で早期にfail-open（exit 0）する。
hook_symlink_hops=0
while [ -h "$hook_source" ]; do
  hook_symlink_hops=$((hook_symlink_hops + 1))
  [ "$hook_symlink_hops" -le 10 ] || exit 0
  hook_dir="$(cd -P "$(dirname "$hook_source")" >/dev/null 2>&1 && pwd)" || exit 0
  hook_target="$(readlink "$hook_source" 2>/dev/null)" || exit 0
  case "$hook_target" in
    /*) hook_source="$hook_target" ;;
    *) hook_source="$hook_dir/$hook_target" ;;
  esac
done
HOOK_DIR="$(cd -P "$(dirname "$hook_source")" >/dev/null 2>&1 && pwd)" || exit 0
# shellcheck source=./lib/json.sh
source "$HOOK_DIR/lib/json.sh" 2>/dev/null || exit 0

input="$(cat 2>/dev/null)" || exit 0

# 1. jq・python3が両方とも不在なら、JSONを一切パースできず json_field は常に
#    空文字列を返す。これを検出せずに進行すると、直後の stop_hook_active
#    判定が常に不成立になり、「一度ブロックされたら次の停止で必ず通過する」
#    という文書化された契約（停止1回につき最大1回のブロック）が壊れて永久
#    ブロック経路になってしまう。判定不能なゲートは開ける（fail-open）。
if ! json_tools_available; then
  exit 0
fi

# 2. ループガード: stop_hook_active が立っていれば、このフック自身が直前の
#    停止で既に一度ブロック済みということ。停止1回につき最大1回のブロックに
#    するため、ここでは常に許可する。
#    python3 フォールバックは JSON の bool を Python の bool にデコードした後
#    str() 相当で埋め込むため "True"（先頭大文字）になる。jq 経路の "true"
#    （小文字）と両方に対応する必要がある。
stop_hook_active="$(json_field "$input" stop_hook_active)"
if [ "$stop_hook_active" = "true" ] || [ "$stop_hook_active" = "True" ]; then
  exit 0
fi

# 3. cwd 解決とgit前提の検証。すべて失敗時は許可。
cwd="$(json_field "$input" cwd)"
[ -n "$cwd" ] || cwd="$PWD"

[ -d "$cwd" ] || exit 0
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
# unborn HEAD（コミットが1つも無い repo）は diff の意味が無いため許可。
# fail-open の残余として意図的に受容（新規repo初回コミット前にstageした
# デバッグログは、このゲートでは捕まえられない）。
git -C "$cwd" rev-parse --verify -q HEAD >/dev/null 2>&1 || exit 0
# pathspec（下記 diff_paths の `.`）は git -C の作業ディレクトリ相対で解釈される。
# cwd がリポジトリのサブディレクトリの場合に走査範囲が cwd 配下へ狭まり、兄弟
# ディレクトリの残置を見逃すため、常にリポジトリ最上位から走査する。
cwd="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$cwd" ] || exit 0

# 4. 未コミットの新規追加行のみを走査する。
#    GIT_OPTIONAL_LOCKS=0: 停止処理中に他プロセスの index.lock と競合しても
#    フックが失敗しないようにする（index を書き換えない diff 系コマンドなので
#    ロック取得自体が本質的に不要）。
#    HEAD との差分だけでは、マーカーを stage 後に作業ツリーから消して未stageの
#    ままにした場合、相殺された正味差分しか見えずコミット候補の残置を見逃す。
#    そのため通常差分と --cached の両方を必ず走査する。
#    pathspec は awk 除外の厳密な部分集合に限る純粋な前処理であり、追加行と除外の
#    最終判定は常に awk を正本とする。この不変条件を崩してはならない。
#    未追跡ファイルは対象外（`git diff` の既定動作）: スクラッチ置き場等の
#    誤爆を避けるトレードオフとして受け入れる。
diff_paths=(
  .
  ':(exclude,glob)**/*.md'
  ':(exclude,glob)**/*.test.*'
  ':(exclude,glob)**/*_test.*'
  ':(exclude,glob)test/**'
  ':(exclude,glob)**/test/**'
  ':(exclude,glob)tests/**'
  ':(exclude,glob)**/tests/**'
  ':(exclude,glob)fixtures/**'
  ':(exclude,glob)**/fixtures/**'
  ':(exclude,glob)block-debug-log-residue.*'
  ':(exclude,glob)**/block-debug-log-residue.*'
)
findings="$(
  {
    GIT_OPTIONAL_LOCKS=0 git -C "$cwd" -c core.quotePath=false \
      diff --unified=0 --no-color --no-ext-diff -G'\[(DEBUG|TRACE)\]' \
      -- "${diff_paths[@]}" 2>/dev/null
    GIT_OPTIONAL_LOCKS=0 git -C "$cwd" -c core.quotePath=false \
      diff --cached --unified=0 --no-color --no-ext-diff -G'\[(DEBUG|TRACE)\]' \
      -- "${diff_paths[@]}" 2>/dev/null
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
