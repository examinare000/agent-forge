#!/usr/bin/env bash
# PreCompact hook: compact 前に会話 transcript のスナップショットを保存する。
# Why: compact は不可逆なので、要約から重要事項が落ちても完全な履歴へ戻れるよう
# 安価な保険を置く。これは衛生処理であり、どの障害でも必ず許可する。
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
src="$(json_field "$input" transcript_path)"
trigger="$(json_field "$input" trigger)"
[ -n "$trigger" ] || trigger=unknown
[ -n "$src" ] && [ -f "$src" ] || exit 0

# HOME 未設定（launchd 等の特殊環境）では退避先を決められない。fail-open。
[ -n "${HOME:-}" ] || exit 0
dest_dir="$HOME/.claude/backups/transcripts"
mkdir -p "$dest_dir" || exit 0

# trigger は外部入力なので、区切り文字や空白をファイル名へ持ち込ませない。
trigger="$(printf '%s' "$trigger" | tr -c '[:alnum:]_-' '_')" || exit 0
[ -n "$trigger" ] || trigger=unknown
stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null)" || exit 0
base="$(basename "$src" 2>/dev/null)" || exit 0
cp "$src" "$dest_dir/${stamp}-$$-${trigger}-${base}" 2>/dev/null || exit 0

# 拡張子を限定すると別形式の transcript 導入時に上限が形骸化するため、通常
# ファイル全体を対象にする。
# 単一パスで刈り込む: 削除のたびにディレクトリ全体を再 glob + 再 stat して
# 最古を探す旧実装は O(n^2) で、バックアップが数千件溜まった場合に
# PreCompact hook がタイムアウトし得た。mtime降順（新しい順）に1回だけ列挙し、
# 51件目以降（保持数50を超える古い側）だけをまとめて削除する。
(
  cd "$dest_dir" 2>/dev/null || exit 0
  ls -1t . 2>/dev/null | tail -n +51 | while IFS= read -r candidate; do
    [ -f "$candidate" ] && rm -f "$candidate" 2>/dev/null
  done
) 2>/dev/null

exit 0
