#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit) hook: Claude が編集したファイルを lint する。
# Why: 「編集後に linter を実行する」は決定論的な手順なので、チェックリストで
# モデルの記憶に頼らず自動化する。指摘だけを助言として返し、ツール不在や
# クラッシュは編集フローを壊さないよう常に無言で許可する。
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
file="$(json_field "$input" tool_input.file_path)"
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0
file_dir="$(cd "$(dirname "$file")" >/dev/null 2>&1 && pwd)" || exit 0

# 編集ファイル以外の探索にも再利用できるよう、開始ディレクトリを明示的に受け取る。
find_up() {
  local marker="$1" dir="$2"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -e "$dir/$marker" ]; then
      printf '%s' "$dir/$marker"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

ext="${file##*.}"
output=""
status=0

case "$ext" in
  py)
    # プロジェクト固有設定とのずれを避けるため、仮想環境の ruff を優先する。
    ruff=""
    for cand in .venv/bin/ruff venv/bin/ruff; do
      if hit="$(find_up "$cand" "$file_dir")"; then
        ruff="$hit"
        break
      fi
    done
    if [ -z "$ruff" ]; then
      if ruff_path="$(command -v ruff 2>/dev/null)"; then
        ruff="$ruff_path"
      fi
    fi
    if [ -n "$ruff" ]; then
      if output="$("$ruff" check --quiet "$file" 2>&1)"; then
        status=0
      else
        status=$?
      fi
    fi
    ;;
  ts | tsx | js | jsx | mjs | cjs)
    # 最寄りプロジェクトを基準にし、flat/legacy config と cache の位置を揃える。
    if binpath="$(find_up node_modules/.bin/eslint "$file_dir")"; then
      if projdir="$(
        if cd "$(dirname "$binpath")/../.." >/dev/null 2>&1; then
          pwd
        else
          exit 1
        fi
      )"; then
        if output="$(
          if cd "$projdir"; then
            ./node_modules/.bin/eslint \
              --cache \
              --cache-location "node_modules/.cache/agent-forge-eslint/" \
              "$file" 2>&1
          else
            exit 2
          fi
        )"; then
          status=0
        else
          status=$?
        fi
        # --cache 書込不能（read-only な node_modules 等）だと eslint は exit 2
        # を返し、fail-open ガードで本物の lint 指摘が無言で消えてしまう。
        # exit 2 以上（クラッシュ相当）のときだけ --cache なしで1回だけ再実行し、
        # その結果を採用する。0/1 はキャッシュ起因ではないためそのまま使う。
        if [ "$status" -ge 2 ]; then
          if output="$(
            if cd "$projdir"; then
              ./node_modules/.bin/eslint "$file" 2>&1
            else
              exit 2
            fi
          )"; then
            status=0
          else
            status=$?
          fi
        fi
      fi
    fi
    ;;
  *)
    exit 0
    ;;
esac

# linter 自体の異常を lint 指摘として誤報しない。指摘の契約は exit 1 に限定する。
[ "$status" -eq 0 ] && exit 0
[ "$status" -eq 1 ] || exit 0
[ -n "$output" ] || exit 0

{
  echo "🟠 lint 指摘 (${file##*/}): 編集後の自動 lint で問題を検出しました。修正してください。"
  printf '%s\n' "$output"
} >&2
exit 2
