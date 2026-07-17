# CLAUDE.md — {{PROJECT_NAME}}

このファイルはプロジェクトへの薄い入口です。エージェント挙動の正本は
[agent-forge](https://github.com/examinare000/agent-forge) が `~/.claude/` 配下にグローバル導入する
ルール・スキル・サブエージェント定義であり、ここでは重複させません。

## ルーティング

- 共通ルール一覧・優先順位: `~/.claude/rules/README.md`
- 憲法（矛盾時に常に最優先）: `~/.claude/rules/00-core-principles.md`
- パススコープ付きルール（このプロジェクト内・自分の規約を追加する場所）: `.claude/rules/README.md`
- サブエージェント定義: `~/.claude/agents/`
- スキル: `~/.claude/skills/`

## 前提

agent-forge が未導入（`~/.claude/rules` が存在しない）の場合は、先に
`forge install` を実行してください。導入状態は `forge check` で確認できます。
