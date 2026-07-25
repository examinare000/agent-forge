# ADR-002: trial-log の書き手は Write 権限を持つワーカーに限定し、レビュアーは報告経由で転記する

- ステータス: 採用済み
- 日付: 2026-07-25
- 最終更新日: 2026-07-25

## 背景

rules/30 と Skill `trial-log` は `code-reviewer` / `ai-antipattern-reviewer` / `adversarial-verifier` を「Write/Edit 権限を持つ書き手」として trial-log の自書きを義務付けていたが、本リポジトリのエージェント定義ではこの 3 者の tools は `Bash, Read, Grep, Glob` のみで、義務が実行不能だった。

その後のクロスベンダーレビュー（Codex）で、`testability-architect` も同様に Write/Edit を持たない（tools は `Bash, Read, Grep, Glob, Skill, TodoWrite, WebSearch, WebFetch, mcp__shelf__*`）と判明し、当初この ADR が書き手に含めていたのは誤りだったと確定した。

## 検討した選択肢

1. **レビュアー系に Write を付与して自書きさせる** — ai-antipattern-reviewer の検疫設計（未信頼の AI 生成 diff を扱うため書き込み経路を持たせない）と、検証役の read-only 性による独立性担保に反する。棄却（詳細: [docs/trial-log/trial-log-writer-roster.md](../trial-log/trial-log-writer-roster.md)「棄却した案」）。
2. **レビュアーは読む義務 + 報告に含め、オーケストレーターが転記する** — read-only 設計を維持しつつ、棄却理由への異議・新たな棄却知見は報告経由で trial-log に残る。採用。

## 決定

書き手（自書き義務）は Write を持つ `tdd-strict-coder` / `implementation-coder` とメインに限定。`testability-architect` を含む read-only の 4 エージェント（`code-reviewer` / `ai-antipattern-reviewer` / `adversarial-verifier` / `testability-architect`）は「読む義務 + 報告に含める」に統一し、正準ブロック `generators/agent-blocks/trial-log-reviewer.md` にこの契約を明文化した。

## 理由

検証役の read-only 性（検疫・独立性）は trial-log の利便より優先度が高い。転記方式でも記録は失われず、オーケストレーターの事実確認を経る分だけ品質はむしろ上がる。

## 結果

- skills/trial-log・rules/30・エージェント定義の三者の記述が実権限と整合した。
- オーケストレーターはレビュー結果受領時に trial-log への転記責任を負う。
