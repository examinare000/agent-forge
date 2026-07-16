#!/usr/bin/env bash
# ドキュメント整合性チェック（pre-push ゲート / skill の検証ステップ共用）。
# 正本は docs/design/*.md（Markdown）。HTML は MkDocs 生成物（手書き正本にしない）。
# 軽量チェックは依存なしで常時実行。mkdocs があれば --strict ビルドも実行する。
#
# 本スクリプトは agent-forge の scaffold テンプレート由来（各プロジェクトへコピーされる）。
# 固有ファイル名には依存せず、docs/design/ 配下の Markdown 正本を走査して汎用的に検証する。
#
# 使い方:   bash scripts/check-docs.sh
# 終了コード: 0=OK / 1=違反（pre-push を中止すべき）
set -uo pipefail

# リポジトリルート（mkdocs.yml と docs/ がある場所）へ移動
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DESIGN="docs/design"
fail=0
note() { printf '  - %s\n' "$1"; }

# docs/ が無い環境（部分チェックアウト等）はスキップ
if [ ! -d docs ]; then
  echo "ℹ️  docs/ が見つからないためドキュメントチェックをスキップします。"
  exit 0
fi

echo "🔎 ドキュメント整合性チェック ..."

# 1) 移行済み HTML の残骸を禁止（同名 .md 正本が存在する HTML は移行完了後の残骸＝削除すべき）。
#    .md がまだ無い HTML（未移行）は対象外とし、固有のファイル名に依存しない判定にする。
if [ -d "$DESIGN" ]; then
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    md="${h%.html}.md"
    if [ -f "$md" ]; then
      echo "❌ Markdown 正本が存在するのに手書き HTML が残っています: $h"
      note "移行済み（$md がある）なら $h は削除してください。HTML は mkdocs build の生成物です（~/.claude/rules/30-documentation-management.md 参照）。"
      fail=1
    fi
  done < <(find "$DESIGN" -maxdepth 1 -type f -name '*.html' 2>/dev/null)
fi

# 2) Markdown 正本の存在（design ディレクトリがあるのに .md が一つも無いのは異常）
if [ -d "$DESIGN" ]; then
  md_count="$(find "$DESIGN" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$md_count" -eq 0 ]; then
    echo "❌ Markdown 正本がありません: $DESIGN/*.md"
    note "設計・仕様の正本は Markdown です（~/.claude/rules/30-documentation-management.md 参照）。"
    fail=1
  fi
fi

# 3) design 系 HTML へのリンクの健全性（Markdown リンク構文のみ検出。prose 言及は対象外）。
#    リンク先 .html が (a) 削除済み = dangling、または (b) 同名 .md 正本が存在する = 張り替え漏れ
#    の場合に検出。未移行 HTML（.html が存在し .md が無い）への正当なリンクは対象外。
while IFS= read -r line; do
  [ -n "$line" ] || continue
  base="$(printf '%s\n' "$line" | grep -oE '[A-Za-z0-9._-]+\.html' | head -1)"
  [ -n "$base" ] || continue
  stem="${base%.html}"
  if [ -f "$DESIGN/$stem.md" ] || [ ! -f "$DESIGN/$base" ]; then
    echo "❌ 要修正の design HTML リンク: $line"
    note "$DESIGN/$stem.md があれば .md へ張り替え。$DESIGN/$base が無ければ削除済みリンクです（~/.claude/rules/30-documentation-management.md 参照）。"
    fail=1
  fi
done < <(grep -rnE '\]\([^)]*design/[^)]*\.html[^)]*\)' --include='*.md' docs 2>/dev/null || true)

# 4) design/*.md のコードフェンス（```）対応（Mermaid 含む）が偶数か
for m in "$DESIGN"/*.md; do
  [ -f "$m" ] || continue
  # WHY: grep -c は no-match でも "0" を出力しつつ exit 1 を返すため、|| echo 0 では
  # 出力が 2 行になり後続の算術式が壊れる。exit code は無視し、空出力のみ 0 に補正する。
  fences="$(grep -c '^```' "$m" 2>/dev/null)" || true
  fences="${fences:-0}"
  if [ $((fences % 2)) -ne 0 ]; then
    echo "❌ コードフェンス(triple-backtick)が閉じていません: $m (fence数=$fences)"
    fail=1
  fi
done

# 5) mkdocs があれば strict ビルド（リンク切れ・nav 不整合・Mermaid 設定を検証）
if command -v mkdocs >/dev/null 2>&1 && [ -f mkdocs.yml ]; then
  echo "🏗  mkdocs build --strict ..."
  tmpsite="$(mktemp -d)"
  if ! mkdocs build --strict --site-dir "$tmpsite" >/tmp/mkdocs-check.log 2>&1; then
    echo "❌ mkdocs build --strict が失敗しました（リンク切れ等）。詳細:"
    tail -20 /tmp/mkdocs-check.log | sed 's/^/  /'
    fail=1
  fi
  rm -rf "$tmpsite"
else
  echo "ℹ️  mkdocs 未導入のため strict ビルドはスキップ（軽量チェックのみ）。導入: pip install -r requirements-docs.txt"
fi

if [ "$fail" -ne 0 ]; then
  echo "🔴 ドキュメントチェック失敗。修正してから push してください。"
  exit 1
fi
echo "✅ ドキュメントチェック OK。"
exit 0
