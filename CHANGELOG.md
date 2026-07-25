# Changelog

すべての重要な変更はこのファイルに記録されます。

フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に従います。

## [未リリース]

## [0.4.0] - 2026-07-25

### Added
- **trial-log スキル同梱**: 開発中の試行記録（docs/trial-log/）を live-docs として運用する手続きスキルを新規追加。ワーカーが試行を1つ終えるたび自発的に記録し、同じ失敗の繰り返し・棄却済み案の再試行を防ぐメカニズムを実装
- trial-log 記録義務を 4 エージェント（`implementation-coder` / `tdd-strict-coder` / `code-reviewer` / `testability-architect`）に配線
- `rules/30-documentation-management.md` に trial-log 節を拡充（配置・単位・読む義務・ライフサイクルの詳細）
- `rules/94-self-improvement-protocol.md` に in-flight 記録セクション（trial-log）と (t2)(t3) トリガ（棄却・REJECT に基づく方針変更）を追記

### Fixed
- ai-antipattern-reviewer に effort: high を明示（0.3.0 の effort 明示化で唯一漏れていたエージェント）

## [0.3.0] - 2026-07-25

エージェント定義の正規化と hook テスト整備。

### Added
- Hook テストスイート整備: lint-after-edit.test.sh・backup-before-compact.test.sh を CI に統合
- claude/settings.base.json に hook タイムアウト設定を明示化（lint-after-edit=30s, block-debug-log-residue=15s, backup-before-compact=30s）
- baseline-ui スキルの SKILL.md に WHEN 節（「any web UI」トリガー）を追記し、発見可能性向上

### Changed
- 全エージェント定義から Persistent Agent Memory セクション (Claude Code ハーネス自動注入による重複) を削除（implementation-coder -144行、tdd-strict-coder -140行、testability-architect -139行、dist/ 生成物 -422 行）
- implementation-coder.md のプロジェクト規約セクションを参照型に短縮（冗長性排除）
- effort 設定を frontmatter に明示化: implementation-coder=low、test-runner=low、git-composer=medium

### Removed
- testability-architect エージェント frontmatter から Edit・Write ツール除去（read-only 宣言強化）→ Codex 側で sandbox_mode=read-only に自動変換

### Fixed
- N/A

### Security
- N/A

## [0.2.1] - 2026-07-17

同梱スキルの帰属表記を是正するパッチリリース。

### Fixed
- 第三者由来スキルの帰属表記を是正（frontend-design のライセンスを Apache-2.0 / Anthropic に訂正、baseline-ui に ibelick/ui-skills の MIT ライセンス全文を同梱）

## [0.2.0] - 2026-07-17

OSS運用基盤の整備リリース。CI・セキュリティ窓口・コントリビューションガイドを新設し、リリース運用に耐える体制を確立。

### Added
- **CI** — GitHub Actions によるテスト自動実行基盤
- **Dependabot** — 依存更新の自動追従
- **SECURITY.md** — 脆弱性報告窓口の新設
- **CONTRIBUTING.md** — mainへの直接push不可（PR+CI必須）を明示したコントリビューションガイド

### Changed
- README をターゲット層に合わせて再構成（前提ツールのインストール案内と10分セットアップを追加、技術詳細は開発者向け節へ）
- shelf MCP 参照の任意性を明記し、3リポジトリの独立導入可能性を README に明示

### Fixed
- CIランナーに `claude` CLI が無い環境でも installer 検証が通るようスタブを供給しハーミティック化
- CIの git identity 未設定で初期コミット検証が落ちる問題を環境変数の明示で解消
- Python 実行で生成される `__pycache__` を追跡対象外に

## [0.1.0] - 2026-07-17

初回公開リリース。AI駆動開発の基盤フレームワークを確立し、テストファースト・自己改善ループ・マルチベンダー対応を実現。

### Added
- **Rules orchestration** — オーケストレーション核9本のルール（コア原則・モデルティア・セキュリティ・可読性・信頼性・プロトコル等）と採用者が拡張できる番号体系
- **Subagents** — 8体の専門サブエージェント（アーキテクト・TDDコーダー・実装コーダー・テスト実行・コードレビュワー・gitコミット・反証検証・アンチパターンレビュワー）
- **Skills** — 手続きスキル群（TDD・レビュー・ブランチ完結・深度推論等）
- **Hooks** — 編集ゲート3本（デバッグログ検出・コンパクト前バックアップ・編集後lint）
- **Evals framework** — 決定的アサートに基づくエージェント挙動の回帰テスト基盤
- **Installer** — `~/.claude/` へのグローバル導入・診断・アンインストール機構
- **Forge new** — `forge new` コマンドによる統一的なプロジェクト雛形生成
- **Multi-vendor generators** — `dist/` 生成物（Codex向けAGENTS.md・Gemini向けGEMINI.md・Codexプラグイン・Codexエージェント定義）
- Claude Code native support (.claude/ 参照)
- MIT License

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A
