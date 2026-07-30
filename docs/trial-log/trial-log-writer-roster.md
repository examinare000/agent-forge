# trial-log: trial-log 書き手指定とツール権限の整合

範囲: どのエージェントが trial-log を「自分で書く」義務を負えるか（frontmatter tools との整合）。trial-log の書式・配置は扱わない（`shared-block-canonicalization.md` と rules/30 の領分）。

関連: ブランチ `feature/token-efficiency`

## 目的
skills/trial-log と rules/30 が書き手に指定するエージェント集合を、実際の tools 権限と矛盾しない形に修正する。

## 現在地
実装完了（2026-07-25 クロスベンダーレビューでの再修正込み）。書き手は Write/Edit を持つ `tdd-strict-coder` / `implementation-coder` + メインのみに確定。`testability-architect` は当初「書き手」に含めていたが、frontmatter tools を再確認したところ Write/Edit を持たない（`Bash, Read, Grep, Glob, Skill, TodoWrite, WebSearch, WebFetch, mcp__shelf__*`）ことが判明し、read-only 群（`code-reviewer` / `ai-antipattern-reviewer` / `adversarial-verifier` / `testability-architect`）へ移した。修正対象は `skills/trial-log/SKILL.md`「書き手」節、`rules/94-self-improvement-protocol.md` L27、`docs/adr/002-trial-log-writer-roster.md`、`agents/testability-architect.md`（trial-log-worker ブロック→trial-log-reviewer ブロックへ差し替え）、`generators/check-agent-blocks.sh` の MAPPING（testability-architect を trial-log-worker.md の対象から trial-log-reviewer.md の対象へ移動、合計対象数 24 は不変）。

## 観測（矛盾の内容）
- rules/30「書き手」および skills/trial-log は `code-reviewer` / `ai-antipattern-reviewer` / `adversarial-verifier` を「Write/Edit 権限を持つワーカー」として書き手に列挙している。
- しかし本リポジトリの agents/ 定義では、この 3 エージェントの frontmatter tools は `Bash, Read, Grep, Glob` のみ（Write/Edit なし）。code-reviewer は本文の禁止事項でも「コードの修正（Edit/Write は持っていない）」と自認。ai-antipattern-reviewer は検疫（quarantine）設計として意図的に read-only。
- 【2026-07-25 追記・検出者: クロスベンダーレビュー(Codex)】上記の初回修正で書き手に加えた `testability-architect` 自身も、frontmatter tools（`Bash, Read, Grep, Glob, Skill, TodoWrite, WebSearch, WebFetch, mcp__shelf__*`）に Write/Edit を持たず、同じ矛盾を再生産していた。原因は初回修正時に testability-architect の tools を実地確認せず「アーキテクト的役割だから書けるはず」という思い込みで書き手に加えたこと（観測ではなく推測で埋めた）。教訓: ロスター系の修正では対象エージェント全員の frontmatter tools を都度 grep で確認する。

## 棄却した案

### レビュアー系に Write を付与して自書きさせる案
- 棄却理由（観測): ai-antipattern-reviewer の検疫設計（AI 生成 diff = 未信頼コンテンツを扱うため書き込み経路を持たせない）と衝突する。adversarial-verifier / code-reviewer も read-only であることが検証の独立性の担保になっている。trial-log 1 用途のために書き込み権限を開けるのはリスク対効果が合わない。
- 採用した代替: レビュアーは読む義務のみ負い、棄却理由への異議・新たな棄却知見は報告に含め、オーケストレーターが trial-log へ転記する。

## adversarial-verifier 再検証 PASS 時の補足（メイン転記）
- 「ワーカーの報告契約は5項目」という語は導入コミット由来の経過的な念押しで、本リポジトリ内に定義実体が存在しなかったことを `git log -S` で確認。今後この語を正本として参照しない（実効的な出力契約は CLAUDE.core.md の「ワーカー出力契約」）。
- 残存リスクとして受容: check-agent-blocks.test.sh は期待文字列 `6 blocks × 24 targets OK` をハードコードしており、ブロック・対象を増やす際はテスト更新が必須。

## 追記 2026-07-30（事後補完）

### frontmatter tools の実地確認
agents/*.md 全8ファイルの frontmatter tools を確認（`grep -n "^tools:" agents/*.md`）:
```
agents/adversarial-verifier.md:6:tools: Bash, Read, Grep, Glob
agents/code-reviewer.md:8:tools: Bash, Read, Grep, Glob
agents/ai-antipattern-reviewer.md:7:tools: Bash, Read, Grep, Glob
agents/git-composer.md:8:tools: Bash, Read, Grep, Glob, Edit, Write
agents/testability-architect.md:8:tools: Bash, Read, Grep, Glob, Skill, TodoWrite, WebSearch, WebFetch, mcp__shelf__consult, mcp__shelf__list_notebooks
agents/implementation-coder.md:8:tools: Bash, Read, Grep, Glob, Edit, Write, Skill, TodoWrite
agents/tdd-strict-coder.md:8:tools: Bash, Read, Grep, Glob, Edit, Write, Skill, TodoWrite
agents/test-runner.md:8:tools: Bash, Read, Grep, Glob
```
Write/Edit を持つエージェント: git-composer / implementation-coder / tdd-strict-coder。read-only 群（adversarial-verifier / code-reviewer / ai-antipattern-reviewer / testability-architect / test-runner）は構成通り。

### check-agent-blocks.sh の実地検証
```
$ bash generators/check-agent-blocks.sh
agent-blocks: 6 blocks × 24 targets OK
```
OK 出力を確認。テスト期待値が現行構成に合致している。

### git log -S での確認
```
$ git log -S "ワーカーの報告契約は5項目" --oneline
8ef7f58 rules/agents/skillsの変更をdist配布物へ再生成同期
a3564c8 本リポジトリ自身でtrial-log/ADR運用を開始し、正準ブロック方式と書き手ロスターの決定を記録
3edc8fb trial-log・モデルピン・エージェント一覧の正準を一本化し重複記述をポインタ化
1b441d0 試行と棄却理由をlive-docsとして記録し、繰り返し失敗と棄却案の再試行を防ぐためtrial-logスキルを同梱
```
該当語は導入コミット `1b441d0` 由来の経過的表現であることを確認。現状では rules/94-self-improvement-protocol.md（「ワーカー出力契約」欄の 5 項目）が実効的な定義である。
