# 92. 計画立案プロトコル（探索役の並列調査）
非自明な計画立案（plan mode を持つ provider ではその突入）で、推測ではなく調査に基づく実行プランを策定するための戦略。
**手続きの本体は `plan-deep-research` 手順書**にあり、本ルールは「いつ発火し、どの優先度か」を定める薄い参照層である。発火条件は provider 中立（正本: `05-stance-and-triggers.md`）。

## トリガと発火
- 非自明な計画（前提が崩れると高くつく・複数ファイルや複数関心事に跨る・設計判断を含む）で plan mode に入った時点、または同様の計画依頼を受けた時、本ルールを最優先で適用する（エントリの次に優先）。ツール呼び出し 1〜2 回で足りる調査や数行の変更計画は対象外で、メインが直接行う。
- **plan mode 機構を持たない provider** は計画依頼を受けた時点を発火点とする（`05-stance-and-triggers.md`「機構非対応時の縮退」）。
- 発火したら `plan-deep-research` 手順書をロードして従う（Skill 機構があれば `/plan-deep-research`、無ければ `~/.claude/skills/plan-deep-research/SKILL.md` を直読）。担当の選定と論理ロールでの指名は `95-orchestration-protocol.md`「委譲先の選定」。

---
**適用優先度**: 🔴 最高（計画立案時。全 provider）
