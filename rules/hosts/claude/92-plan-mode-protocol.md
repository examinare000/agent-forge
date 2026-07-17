# 92. Plan Mode プロトコル（Explorer 並列調査）
plan mode（計画立案）に入ったら、推測ではなく調査に基づく実行プランを必ず策定するための戦略。
**手続きの本体は Skill `plan-deep-research` に切り出してある**（記事ベストプラクティス: 手続き→Skills）。
本ルールは「いつ発火し、どの優先度か」を定める薄い参照層。

## トリガと発火
- plan mode に入った時点、または「計画して」「プランを立てて」等の計画依頼を受けた時、
  本ルールを最優先で適用する（CLAUDE.md の次に優先）。
- そのとき**必ず Skill `plan-deep-research` をロードして従う**（`/plan-deep-research`）。
- 注: 「plan mode 突入」を検知する専用フックは Claude Code に存在しないため、
  メインエージェント自身が本ルールに従って Skill を起動すること。

## 要点（詳細は Skill 参照）
- plannerペルソナ（テスト容易性最重視のアーキテクト）で、コードは書かず調査と設計に徹する。
- 観点分解 → `Explore` を**同一メッセージ内で並列起動**して調査 → `path:line` 根拠で統合。
- プランは**エージェント実行計画**として作る: 各極小タスクに担当エージェント
  （`testability-architect` / `tdd-strict-coder` / `implementation-coder` / `code-reviewer` /
  `adversarial-verifier` / `git-composer`。モデルピン一覧は `02-model-fallback-matrix.md`
  （Claude 対応表）参照）・依存/並列可否・受け入れ条件を明記。
- ExitPlanMode で提示し、承認後に計画どおり Task ツールで各エージェントを起動して実行する。

---
**適用優先度**: 🔴 最高（plan mode 時）
