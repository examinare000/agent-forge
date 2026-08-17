#!/usr/bin/env bash
# PreToolUse(Bash) hook: 既知の安全な rm -rf（ビルドキャッシュの whitelist と
# 呼び出し元セッション scratchpad 配下）だけを自動承認し、それ以外は一切判定
# せず従来の権限フロー（deny/ask ルール → default mode ではプロンプト、
# 非対話では実行不可、auto mode では分類器）に委ねる。
#
# 設計の由来: 姉妹の private リポジトリで反証検証6ラウンド（REJECT 5回→
# ACCEPT）を経て確定した設計を移植したもの。決定の要約と主要な不変条件は
# docs/adr/004-safe-rm-hook-auto-approval.md を正本とする。
#
# なぜ allow 専用なのか（"ask"/"deny"/exit 2 を一切出さない）:
# PreToolUse hook の結果統合は並列実行 + last-writer-wins で、exit-2 の
# blockingError も同じイベント型に統合される。本 hook が "ask"/"deny" を
# 出す設計だと、同一コマンドを見た他 hook（ブランチ保護等）の deny 判定を
# 降格させうる（例: rm -rf dist && git commit で main 保護が消える）。
# 「allow か無出力のみ」に限定することでこの衝突クラスを構造的に排除する。
# 素通し（無出力）は保護を追加も除去もしない中立動作であり、判定に迷う
# 入力は常に素通しに倒す。
#
# なぜ変数展開（$TMPDIR 等）を一切信用しないのか:
# hook はシェル展開を検証できない。scratchpad セグメントを含む綴りであって
# も、変数展開の結果として到達する実パスは hook からは分からない
# （反例: TMPDIR が未設定・空展開なら rm -rf $TMPDIR/…/scratchpad の実削除
# 対象は任意の絶対パスになりうる）。この欠陥は移植元の反証検証で複数回
# 崩れたクラスであり、絶対綴りのみを許可対象とすることで恒久排除する。
#
# なぜ exit code を常に 0 に固定するのか:
# 非 0 終了は blockingError として上記の last-writer-wins 統合に乗り、
# 他 hook の deny を降格させるベクタになりうる。「allow 以外を出さない」
# という中核保証には exit code の保証が含まれる。
set -uo pipefail

# hooks ディレクトリ全体だけでなく個別ファイルが symlink の場合も、共有 lib を
# 実体側から読めるようにする。readlink -f は macOS 標準に無いため使わない。
hook_source="${BASH_SOURCE[0]}"
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

emit_allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"既知の安全な rm 対象（ビルド生成物 / 自セッション scratchpad）のみを検出したため自動承認"}}\n'
}

# jq も python3 も無ければフィールドを一切解決できないため素通し
# （allow 専用 hook なので fail-open の危険はない: 素通し＝従来フロー）。
if ! json_tools_available; then
  exit 0
fi

permission_mode="$(json_field "$input" permission_mode)"
case "$permission_mode" in
  default | acceptEdits | auto | bypassPermissions) : ;;
  *) exit 0 ;; # plan・dontAsk・未知値・取得不能はすべて素通し
esac

agent_type="$(json_field "$input" agent_type)"
[ "$agent_type" = "gemini-consult" ] && exit 0

cmd="$(json_field "$input" 'tool_input.command')"

# split_command: コマンド文字列を先頭から1文字ずつ走査し、クォート状態
# （none/single/double）を追跡しながら、
#   - unquoted のリダイレクト（> <）・バッククォート・$( を検出したら
#     1（危険・解析失敗）を返す。
#   - unquoted の ; && || | & 改行でセグメントに分割し、グローバル配列
#     SEGMENTS に生文字列（trim なし）として格納する。
#   - クォートが閉じずに終端したら 1（危険）を返す。
# クォート内のこれらの文字は区切りとして扱わない（ダブルクォート内は
# コマンド置換だけが危険）。
# 戻り値: 0=解析成功（SEGMENTS を利用可） / 1=解析失敗・危険（呼び出し側は
# 即座に素通しへ倒す）。
SEGMENTS=()

split_command() {
  local s="$1"
  local len=${#s}
  local i=0
  local state="none" # none | single | double
  local c c2
  local seg_start=0
  SEGMENTS=()

  while [ "$i" -lt "$len" ]; do
    c="${s:$i:1}"
    case "$state" in
      none)
        case "$c" in
          "'") state="single" ;;
          '"') state="double" ;;
          '\')
            i=$((i + 1)) ;; # 次の1文字をエスケープとして読み飛ばす
          '`')
            return 1 ;;
          '$')
            c2="${s:$i:2}"
            [ "$c2" = '$(' ] && return 1
            ;;
          '>' | '<')
            return 1 ;;
          ';')
            SEGMENTS+=("${s:$seg_start:$((i - seg_start))}")
            seg_start=$((i + 1)) ;;
          $'\n')
            SEGMENTS+=("${s:$seg_start:$((i - seg_start))}")
            seg_start=$((i + 1)) ;;
          '&')
            c2="${s:$i:2}"
            SEGMENTS+=("${s:$seg_start:$((i - seg_start))}")
            if [ "$c2" = '&&' ]; then
              i=$((i + 1)) # && は2文字区切りとして1回で消費する
            fi
            seg_start=$((i + 1)) ;;
          '|')
            c2="${s:$i:2}"
            SEGMENTS+=("${s:$seg_start:$((i - seg_start))}")
            if [ "$c2" = '||' ]; then
              i=$((i + 1)) # || は2文字区切りとして1回で消費する
            fi
            seg_start=$((i + 1)) ;;
          *) : ;;
        esac ;;
      single)
        [ "$c" = "'" ] && state="none" ;;
      double)
        case "$c" in
          '"') state="none" ;;
          '\')
            i=$((i + 1)) ;;
          '`')
            return 1 ;;
          '$')
            c2="${s:$i:2}"
            [ "$c2" = '$(' ] && return 1
            ;;
          *) : ;;
        esac ;;
    esac
    i=$((i + 1))
  done

  [ "$state" != "none" ] && return 1 # クォート未閉鎖は解釈不定のため危険扱い

  SEGMENTS+=("${s:$seg_start}")
  return 0
}

# build_argv_words: 1セグメント分の文字列からクォート除去後の argv 語を
# 組み立て、グローバル配列 ARGV_WORDS に格納する。危険文字（リダイレクト・
# バッククォート・$(・クォート未閉鎖）の判定は split_command が全体に対して
# 既に行っているため、ここではクォート除去のみを行う。語の境界は
# 「クォート外の空白・タブ」のみ。空クォート（""）の中身は空文字のまま
# 蓄積され、語の境界（空白 or 終端）に達した時点で空文字列なら追加しない
# —結果として `""` 単体は argv 語として現れない。
ARGV_WORDS=()

build_argv_words() {
  local s="$1"
  local len=${#s}
  local i=0
  local state="none"
  local c
  local cur_word=""
  ARGV_WORDS=()

  while [ "$i" -lt "$len" ]; do
    c="${s:$i:1}"
    case "$state" in
      none)
        case "$c" in
          "'") state="single" ;;
          '"') state="double" ;;
          ' ' | $'\t')
            if [ -n "$cur_word" ]; then
              ARGV_WORDS+=("$cur_word")
              cur_word=""
            fi ;;
          '\')
            i=$((i + 1))
            [ "$i" -lt "$len" ] && cur_word="${cur_word}${s:$i:1}" ;;
          *)
            cur_word="${cur_word}${c}" ;;
        esac ;;
      single)
        if [ "$c" = "'" ]; then
          state="none"
        else
          cur_word="${cur_word}${c}"
        fi ;;
      double)
        case "$c" in
          '"') state="none" ;;
          '\')
            i=$((i + 1))
            [ "$i" -lt "$len" ] && cur_word="${cur_word}${s:$i:1}" ;;
          *)
            cur_word="${cur_word}${c}" ;;
        esac ;;
    esac
    i=$((i + 1))
  done

  [ -n "$cur_word" ] && ARGV_WORDS+=("$cur_word")
}

# _has_path_segment: path をスラッシュ区切りのセグメント列とみなし、
# target と完全一致するセグメントを含むかを判定する。IFS 分割 + set --
# ではなく case パターンマッチで実装する理由: unquoted の $path を
# word-splitting に通すと（既に glob 文字を除外済みとはいえ）展開の経路を
# 増やしたくない。case パターン中の "$target" はリテラル一致であり
# （target は "scratchpad" や ".." のような glob メタ文字を含まない固定
# 文字列のみを渡す）、glob 展開の危険がない。
_has_path_segment() {
  local path="$1" target="$2"
  case "$path" in
    "$target" | "$target"/* | */"$target" | */"$target"/*) return 0 ;;
  esac
  return 1
}

_has_dotdot_segment() {
  _has_path_segment "$1" ".."
}

# _target_has_safe_chars: 禁止文字を個別に列挙するブラックリストではなく、
# 許可する文字だけを列挙するホワイトリストにする（英数字・.・_・/・- のみ
# 許可）。
#
# なぜ反転したのか（移植元の adversarial-verifier REJECT を受けての修正）:
# 当初はブラックリスト（$・バッククォート・glob の * ? [）だったが、
# ブレース展開 {} が禁止文字集合から漏れており、`{..,x}/node_modules` の
# ような入力がシェル展開後に `../node_modules` に到達する実測済みバイパス
# があった。禁止したい文字（展開を引き起こしうる $ ` * ? [ ] { } ~ ! 等）を
# 都度洗い出す方式は、シェルの展開機構ひとつでも見落とせば同じ欠陥クラスを
# 再発する。許可文字だけを列挙するホワイトリストに反転すれば、ブレース展開
# ・チルダ展開・変数展開・コマンド置換・glob を個別に列挙せずとも構造的に
# 全て排除できる（このいずれの展開構文も英数字・.・_・/・- だけでは組み立て
# られない）。
_target_has_safe_chars() {
  case "$1" in
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

# target_is_safe: rm セグメントの1ターゲットが安全条件を満たすかを判定
# する。評価順: 文字ホワイトリスト（両分岐共通）→ (a) 一時領域
# （scratchpad 限定・絶対綴りのみ）→ (b) それ以外（whitelist basename）。
target_is_safe() {
  local w="$1"

  _target_has_safe_chars "$w" || return 1

  case "$w" in
    /tmp/claude-* | /private/tmp/claude-*)
      # (a) 一時領域: ..セグメントを含めば不安全、scratchpad という完全な
      # パスセグメントを含めば安全。
      _has_dotdot_segment "$w" && return 1
      _has_path_segment "$w" "scratchpad" && return 0
      return 1
      ;;
  esac

  # (b) それ以外: 語頭-・..セグメント・/始まりのいずれかがあれば不安全
  # （~ 始まりは文字ホワイトリストで既に排除済みのため個別チェック不要）。
  # 末尾 / を除いた basename が whitelist に完全一致すれば安全。
  case "$w" in
    -*) return 1 ;;
    /*) return 1 ;;
  esac
  _has_dotdot_segment "$w" && return 1

  local trimmed="$w"
  while [ "${trimmed: -1}" = "/" ] && [ -n "$trimmed" ]; do
    trimmed="${trimmed%/}"
  done
  local base="${trimmed##*/}"

  case "$base" in
    node_modules | dist | build | target | out | coverage | \
      .next | .nuxt | .turbo | .cache | .parcel-cache | __pycache__ | \
      .pytest_cache | .mypy_cache | .ruff_cache | .tox | .gradle | \
      .dart_tool | DerivedData)
      return 0 ;;
    *) return 1 ;;
  esac
}

# is_rm_segment_safe: ARGV_WORDS（先頭が "rm" であることは呼び出し側で
# 確認済み）のインデックス1以降を検査する。フラグは -r/-R/-f の任意組合せ
# （-rf/-fr/-r -f 等）・--recursive・--force・-- のみ許可。それ以外の
# フラグ（-v 等）が1つでもあれば不安全。ターゲットは1個以上必要で、
# 全ターゲットが target_is_safe を満たさなければ不安全。
is_rm_segment_safe() {
  local n=${#ARGV_WORDS[@]}
  local idx=1
  local word rest
  local target_count=0

  while [ "$idx" -lt "$n" ]; do
    word="${ARGV_WORDS[$idx]}"
    case "$word" in
      --) : ;;
      --recursive | --force) : ;;
      -[rRf]*)
        rest="${word#-}"
        case "$rest" in
          *[!rRf]*) return 1 ;; # r/R/f 以外の文字を含む連結フラグは不安全
        esac
        ;;
      -*)
        return 1 ;; # 許可外のフラグ
      *)
        target_is_safe "$word" || return 1
        target_count=$((target_count + 1)) ;;
    esac
    idx=$((idx + 1))
  done

  [ "$target_count" -ge 1 ]
}

split_command "$cmd" || exit 0

had_rm_segment=0
all_safe=1
for seg in "${SEGMENTS[@]}"; do
  build_argv_words "$seg"
  n=${#ARGV_WORDS[@]}
  if [ "$n" -eq 0 ]; then
    continue # 空セグメント（末尾改行・末尾セミコロン等）は無視する
  fi
  if [ "${ARGV_WORDS[0]}" != "rm" ]; then
    all_safe=0
    break
  fi
  had_rm_segment=1
  if ! is_rm_segment_safe; then
    all_safe=0
    break
  fi
done

if [ "$all_safe" -eq 1 ] && [ "$had_rm_segment" -eq 1 ]; then
  emit_allow
fi

exit 0
