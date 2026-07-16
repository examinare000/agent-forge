---
# copyモードで生成された薄い参照ファイル（正本は agent-forge の rules/70-docker-environments.md）。
# paths: はClaude Codeのnative path-scoped rule機構向け（Docker/Compose/infraのファイル操作時に自動ロードされる）。
paths:
  - "**/Dockerfile"
  - "**/*compose*.yml"
  - "**/*compose*.yaml"
  - "infra/**"
---

# Docker/インフラ環境ルール（参照）

本文は `~/.claude/rules/70-docker-environments.md`（agent-forge導入時にグローバル配置される）を参照してください。

- 未導入の場合: `forge install` を実行してください。
- 本文を直接読みたい場合: agent-forge リポジトリの `rules/70-docker-environments.md` を参照してください。
- 常に最新の内容を追随させたい場合は、`--mode link` で再生成すると本ファイル自体が
  `~/.claude/rules/70-docker-environments.md` への symlink になります。
