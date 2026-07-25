# trial-log: trial-log 書き手指定とツール権限の整合

範囲: どのエージェントが trial-log を「自分で書く」義務を負えるか（frontmatter tools との整合）。trial-log の書式・配置は扱わない（`shared-block-canonicalization.md` と rules/30 の領分）。

関連: ブランチ `feature/token-efficiency`

## 目的
skills/trial-log と rules/30 が書き手に指定するエージェント集合を、実際の tools 権限と矛盾しない形に修正する。

## 現在地
実装完了。`skills/trial-log/SKILL.md`「書き手」節を、Write を持つワーカー（`tdd-strict-coder` / `implementation-coder` / `testability-architect` + メイン）のみが自分で追記する方式へ書き換え、read-only レビュアー（`code-reviewer` / `ai-antipattern-reviewer` / `adversarial-verifier`）は「読む義務 + 報告に含める（メインが転記）」に統一した（agent 定義側の trial-log-reviewer ブロックとも整合）。「いつ書くか」節のレビュアー自書き記述も同時に修正済み。rules/30-documentation-management.md は既存の未コミット変更（本タスク外・rules/ 配下は編集対象外）で既に「書き手の詳細は Skill `trial-log` が正本」へ委譲済みのため、今回の SKILL.md 修正だけで両者は整合する。

## 観測（矛盾の内容）
- rules/30「書き手」および skills/trial-log は `code-reviewer` / `ai-antipattern-reviewer` / `adversarial-verifier` を「Write/Edit 権限を持つワーカー」として書き手に列挙している。
- しかし本リポジトリの agents/ 定義では、この 3 エージェントの frontmatter tools は `Bash, Read, Grep, Glob` のみ（Write/Edit なし）。code-reviewer は本文の禁止事項でも「コードの修正（Edit/Write は持っていない）」と自認。ai-antipattern-reviewer は検疫（quarantine）設計として意図的に read-only。

## 棄却した案

### レビュアー系に Write を付与して自書きさせる案
- 棄却理由（観測): ai-antipattern-reviewer の検疫設計（AI 生成 diff = 未信頼コンテンツを扱うため書き込み経路を持たせない）と衝突する。adversarial-verifier / code-reviewer も read-only であることが検証の独立性の担保になっている。trial-log 1 用途のために書き込み権限を開けるのはリスク対効果が合わない。
- 採用した代替: レビュアーは読む義務のみ負い、棄却理由への異議・新たな棄却知見は報告に含め、オーケストレーターが trial-log へ転記する。

## adversarial-verifier 再検証 PASS 時の補足（メイン転記）
- 「ワーカーの報告契約は5項目」という語は導入コミット由来の経過的な念押しで、本リポジトリ内に定義実体が存在しなかったことを `git log -S` で確認。今後この語を正本として参照しない（実効的な出力契約は CLAUDE.core.md の「ワーカー出力契約」）。
- 残存リスクとして受容: check-agent-blocks.test.sh は期待文字列 `6 blocks × 24 targets OK` をハードコードしており、ブロック・対象を増やす際はテスト更新が必須。
