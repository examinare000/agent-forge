# 91. Claude サブエージェント品質ゲート戦略
サブエージェントを Worker / Reviewer として Task ツールで起動し、品質を担保するための戦略。
委譲・検証のホスト非依存な原則（反証ファースト・独立多数決・コンテキスト最小主義）は
`03-agent-behavior.md`「委譲と検証の原則」が正本。本ファイルは Claude Code の起動機構と運用フローを定める。

## 適用条件＆エージェント一覧
- 専門的なレビュー・実装・タスク分割が必要な場合に、メイン（オーケストレーター）が Task ツールで起動する。

同梱 8 エージェント（installer が `~/.claude/agents/` に配置。モデルピンは `02-model-fallback-matrix.md`（Claude 対応表）参照）:

- **testability-architect**: 設計・境界・タスク分解（➔ 設計方針・タスク分割案）
- **tdd-strict-coder**: 実装/TDD（Red-Green-Refactor ➔ 実装・テストコード）
- **implementation-coder**: 仕様固定の忠実実装・レビュー指摘の適用（➔ 差分）
- **test-runner**: テスト・lint・型チェックの実行と報告（read-only ➔ 結果要約）
- **code-reviewer**: コード/総合品質レビュー（TDD遵守・コミット粒度・規約含む ➔ 改善指摘/承認）
- **ai-antipattern-reviewer**: AI手抜き検出（➔ 手抜き指摘/リファクタ案）
- **adversarial-verifier**: 推論成果物（計画/設計/完了宣言/調査結論）の反証ファースト検証（➔ PASS/REJECT）
- **git-composer**: コミット・統合（完了直前 ➔ アトミックコミット/PR）

## 品質ゲートの運用フロー
1. **Worker起動**: メイン Claude が適切なサブエージェントを Task ツールで起動。
2. **ルール遵守**: 各エージェントは `00-core-principles.md`（言語規約・検証義務）を完全遵守。
3. **AIアンチパターン検査（必須）**: Worker が実装差分を生成したら、完了宣言前に Skill `review-ai-antipattern`（`ai-antipattern-reviewer`）を必ず実行する（依頼の有無によらず必須。実行責任はオーケストレーター。正本: `02-model-fallback-matrix.md`）。
4. **品質判定**: Reviewer系が `PASS` / `REJECT` を判定。antipattern の重大指摘も REJECT 扱い。
5. **ループ**: `REJECT` の場合は実装ステップへ戻り修正。完了条件に antipattern PASS を含む。

## 起動プロンプト（テンプレート）
```markdown
あなたは <エージェント名> です。`~/.claude/agents/<ファイル名>.md` に従ってください。
タスク: <目的・対象ファイル・境界（触らない領域）> / コンテキスト: <仕様・設計の抜粋>
完遂条件: `00-core-principles.md`（言語規約・検証義務）を完全遵守し、次のステップへの判定条件（PASS）を満たすこと。出力は事実ベースで簡潔に。
```

検証系エージェントには `03-agent-behavior.md`「委譲と検証の原則」の反証ファースト起動テンプレートを前置きする。
アーキテクチャ級判断の独立 2 票＋クロスベンダー第3票も同節が正本。

## 注意事項
- **コンテキスト**: 必要最小限のファイル・情報のみをサブに渡し効率化（正本: `03-agent-behavior.md`）。
- **権限**: 破壊的なファイル削除はメインまたは `git-composer` のみに限定（正本: `03-agent-behavior.md`）。
- **git/gh の委譲（推奨）**: 変更系 git/gh はオーケストレーターが直接実行せず `git-composer` へ委譲することを推奨する。
- **委譲は 1 タスク 1 回にまとめる**: 関連する一連の操作（ステージ→commit→push→PR→マージ→main 最新化 等）は、操作ごとに git-composer を起動せず 1 回の委譲にまとめる（操作単位の逐次起動はコスト浪費）。

---
**適用優先度**: 🔴 最高（サブエージェント使用時）
