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
- N/A

### Security
- N/A

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
