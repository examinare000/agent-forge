---
# copyモードで生成された薄い参照ファイル（正本は agent-forge の rules/11-testing-strategy.md）。
# paths: はClaude Codeのnative path-scoped rule機構向け（テスト関連ファイル操作時に自動ロードされる）。
paths:
  - "**/*.test.ts"
  - "**/*.spec.ts"
  - "**/*_test.py"
  - "**/test_*.py"
  - "**/tests/**"
  - "**/__tests__/**"
---

# テスト戦略ルール（参照）

本文は `~/.claude/rules/11-testing-strategy.md`（agent-forge導入時にグローバル配置される）を参照してください。

- 未導入の場合: `forge install` を実行してください。
- 本文を直接読みたい場合: agent-forge リポジトリの `rules/11-testing-strategy.md` を参照してください。
- 常に最新の内容を追随させたい場合は、`--mode link` で再生成すると本ファイル自体が
  `~/.claude/rules/11-testing-strategy.md` への symlink になります。
