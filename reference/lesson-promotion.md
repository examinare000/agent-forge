# 資料: 教訓昇格の基盤と記録形式（`94-self-improvement-protocol.md` の補足）

## 前提となる基盤（provider 固有 — 現状の実体は Claude 側インフラ）

| 層 | 実体 | 備考 |
|---|---|---|
| 生ログ蓄積 | `~/.claude/corpus/claude-code/` | アーカイブ機構（SessionEnd フック等）は導入環境のみ。本リポジトリは同梱しない |
| 意味検索 | recall MCP（`memory_search` / `memory_get`） | 導入環境のみ。アーカイブ後に自動インデクス |
| 教訓候補 | `~/.claude/lessons/inbox/` | 本ルールのキャプチャ先（git 管理外） |
| 昇格先 | `rules/` / `.claude/skills/` / hooks / auto-memory / docs(ADR) | 分類基準は 94 |

## trial-log と lessons/inbox の棲み分け

| | trial-log | lessons/inbox |
|---|---|---|
| 性格 | 開発ノート（ADR の補助ドキュメント。試行の過程） | 教訓カード（再発防止の材料） |
| 対象範囲 | 当該タスク・ブランチ限定 | プロジェクト横断 |
| 抽象度 | 具体（目的・前提・やったこと・結果・残課題） | 抽象化済み（構造としての失敗様式と対策） |
| タイミング | 進行中（その場） | 事後（根本原因確定・修正サイクル完了後） |
| 保存先 | 対象リポジトリ内（git 管理・レビュー対象） | `~/.claude/lessons/inbox/`（git 管理外） |
| 主な消費者 | レビュアー・次セッション・同ブランチの再開者 | `retrospect` 手順書（昇格判定） |

## 記録形式（1教訓 = 1ファイル）

`~/.claude/lessons/inbox/<YYYY-MM-DD>-<slug>.md`:

```markdown
---
type: bug | review | antipattern | feedback | pattern
project: <リポジトリ名 or global>
date: <YYYY-MM-DD>
summary: <1行要約>
evidence: <セッションID / path:line / PR番号>
origin: session:<id> | web:<url> | user | agent:<name>
mast: FM-x.x
---

**前提**: <何をしていた時か>
**目的**: <本来達成したかったこと>
**失敗様式/指摘**: <何が起きたか・何を指摘されたか>
**対策/学び**: <どうすれば防げるか（抽象化した形で）>
```

- `origin` は必須。`web:` 由来の教訓を rules/skills へ昇格させる際は通常以上に人間承認を厳格化する。
- `mast` は任意（オーケストレーション失敗系のみ）。分類表は振り返り分析ロール定義の付録が正本。

## 実測の記録（姉妹の private リポジトリでの実測）
- 2026-07-26 に `03-agent-behavior.md`「横断的な変更は列挙で閉じ、件数を貼る」として昇格した規律が、5 日後の別ブランチで再違反された（`git grep` と `command grep` を混ぜた期待値）。散文追記が無症状クラスに効かないのか、該当場面で当該ファイルが読まれなかったのかは未切り分け。
- 提案書が 4 日間滞留した間に同型が 3 ラウンド連続再発した（到達性判定の根拠）。
- 2026-08-27: retrospect の主要昇格先である rules・skills は無人ジョブへの書込許可付与により到達可能化済み。到達性判定は hook・他リポジトリ・スキル配下データファイル等へ引き続き適用する。
