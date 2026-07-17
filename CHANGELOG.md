# Changelog

すべての重要な変更はこのファイルに記録されます。

フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に従います。

## [未リリース]

### Added
- N/A

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- 第三者由来スキルの帰属表記を是正（frontend-design のライセンスを Apache-2.0 / Anthropic に訂正、baseline-ui に ibelick/ui-skills の MIT ライセンス全文を同梱）

### Security
- N/A

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
