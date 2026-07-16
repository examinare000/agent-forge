---
# copyモードで生成された薄い参照ファイル（正本は agent-forge の rules/15-frontend-design.md）。
# paths: はClaude Codeのnative path-scoped rule機構向け（web/iosのファイル操作時に自動ロードされる）。
paths:
  - "web/**"
  - "ios/**"
---

# フロントエンド設計ルール（参照）

本文は `~/.claude/rules/15-frontend-design.md`（agent-forge導入時にグローバル配置される）を参照してください。

- 未導入の場合: `forge install` を実行してください。
- 本文を直接読みたい場合: agent-forge リポジトリの `rules/15-frontend-design.md` を参照してください。
- 常に最新の内容を追随させたい場合は、`--mode link` で再生成すると本ファイル自体が
  `~/.claude/rules/15-frontend-design.md` への symlink になります。
