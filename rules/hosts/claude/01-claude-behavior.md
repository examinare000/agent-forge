# 01. Claude Code動作制約
共通:`03-agent-behavior.md`、Git:`10-git-strategy.md`

## 動作モード
- **サブエージェント品質ゲート**: 専門レビュー必要時 ➔ `91-claude-subagent-coding.md`
  - メインはオーケストレーターに徹し、サブエージェントをTaskツールで起動。
- **plan mode**: 突入時 ➔ `92-plan-mode-protocol.md`（Skill `plan-deep-research`）
- **深い推論**: 非自明タスク（発火チェックリスト 1 項目以上該当） ➔ `93-deep-reasoning-protocol.md`（Skill `deep-reasoning`。上記モードと重ねて適用）
- **自己成長**: 教訓トリガー該当（バグ根本原因確定・レビュー指摘サイクル完了・ユーザー訂正） ➔ `94-self-improvement-protocol.md`

## タスク管理
- **TodoWrite基準**:
  - 適用: ≥3ステップ、複数ファイル、複数タスク、段階的作業（テスト→実装→統合）
  - 非適用: 単一ファイル修正、1〜2ステップ、情報収集のみ
- 同時実行は1件のみ。完了後即completedへ。サブタスクはtodo追加。

## レスポンス
- 4行以内（コード・ツール出力除く）。前置き・総括なしで直接回答。
- **例外**: `93-deep-reasoning-protocol.md` 発火時・plan mode 時は構造化出力（前提台帳・代替案・プレモーテム等）を優先し、本制約を適用しない。
- パス・コマンド・識別子はバッククォート明示。

## ファイル操作
- 既存編集優先。Edit/Write前は必ずReadで確認。
- 1 Edit = 1論理変更。*.mdは明示指示時のみ作成。

## 検索・分析
- オープンエンド検索はサブエージェント（Task tool）を使用。
- 独立した情報収集は並列実行。特定可能な場合は直接Read。
- コード外の知識（設計原則・ベストプラクティス・外部仕様）は WebSearch と `mcp__shelf__consult`（導入環境のみ。未導入なら WebSearch のみで可）を同格の第一級証拠源として照会。使い分け・裏取り規律 ➔ Skill `plan-deep-research` ドメイン知識節。

## プロアクティブ実行
- **許可**: 検索/分析（WebSearch・`mcp__shelf__consult`（導入環境のみ）等の read-only 外部照会を含む）、テスト実行、lint/typecheck、セキュリティ検証
- **禁止**: 新規ファイル作成（特にドキュメント）、git commit（要指示）、設定変更、書き込み・副作用を伴う外部アクセス

## モードB（サブエージェント品質ゲート）追加制約
- **委譲（メイン禁止）**: Edit/Write（`tdd-strict-coder` / `implementation-coder`）、プラン設計（`testability-architect`）、レビュー（`code-reviewer` 等の Reviewer 系）、Git（`git-composer`）
- **メイン実行**: ユーザー応答、タスク分解・指示
- **例外（メイン可）**: 1〜2行の自明修正、Worker完了後の整合性確認Read

## 優先度
- 🔴 高（Claude Code動作時必須）。`00-core-principles.md` は憲法であり常に最上位。それ以外は番号大を優先。
