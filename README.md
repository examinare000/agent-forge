# agent-forge

**agent-forge** — A discipline framework for AI coding agents (Claude Code, OpenAI Codex, Gemini CLI). Rules, skills, subagents, hooks, and evals for orchestrator-style agent operation. Documentation is in Japanese.

---

## 概要

AIコーディングエージェントに規律あるオーケストレーション運用を与えるフレームワークです。

- **rules/** — エージェント設計の規範・戦略（コア原則、git戦略、テスト戦略、セキュリティ、深度推論等）
- **skills/** — 手続き化された作業フロー（TDD、コードレビュー、ブランチ完結、検証等）
- **agents/** — サブエージェント定義（アーキテクト、コーダー、テスト実行者、レビュワー等）
- **hooks/** — git操作・編集の強制ゲート（保護ブランチ、デバッグログ残留検出、コンポーザー委譲等）
- **evals/** — エージェント挙動の回帰テスト基盤（決定的アサート、確認ゲート付き）

## 対応ホスト

- **Claude Code（ネイティブ対応）** — `.claude/` 配下に配置して即運用可能
- **OpenAI Codex / Gemini CLI** — `dist/` 生成物経由（準備中）

## ステータス

v0.1.0 開発中

## ディレクトリ構成

```
agent-forge/
├── rules/                          # 規範・戦略ドキュメント
│   ├── 00-core-principles.md      # コア原則
│   ├── 03-agent-behavior.md       # エージェント挙動規範
│   ├── 10-git-strategy.md         # Git戦略
│   ├── 11-testing-strategy.md     # テスト戦略
│   ├── 12-security-guidelines.md  # セキュリティ
│   ├── 13-readability.md          # 可読性
│   ├── 15-frontend-design.md      # フロントエンド設計
│   ├── 30-documentation-management.md  # ドキュメント管理
│   ├── 50-production-reliability.md    # 本番信頼性
│   ├── 70-docker-environments.md       # Docker環境
│   ├── 93-deep-reasoning-protocol.md   # 深度推論プロトコル
│   ├── 94-self-improvement-protocol.md  # 自己改善プロトコル
│   ├── hosts/claude/              # Claude固有の規範
│   │   ├── 01-claude-behavior.md
│   │   ├── 02-model-fallback-matrix.md
│   │   ├── 91-claude-subagent-coding.md
│   │   └── 92-plan-mode-protocol.md
│   └── README.md
├── skills/                        # 手続きスキル
│   ├── baseline-ui/
│   ├── dual-track-proposals/
│   ├── frontend-design/
│   ├── deep-reasoning/
│   ├── plan-deep-research/
│   └── review-ai-antipattern/
├── agents/                        # サブエージェント定義
│   ├── testability-architect.md
│   ├── tdd-strict-coder.md
│   ├── implementation-coder.md
│   ├── test-runner.md
│   ├── code-reviewer.md
│   ├── git-composer.md
│   ├── adversarial-verifier.md
│   └── ai-antipattern-reviewer.md
├── hooks/                         # Gitフック・編集ゲート
│   ├── backup-before-compact.sh
│   ├── block-debug-log-residue.sh
│   ├── block-debug-log-residue.test.sh
│   ├── block-protected-branch-commit.sh
│   ├── delegate-git-to-composer.sh
│   ├── delegate-git-to-composer.test.sh
│   └── lint-after-edit.sh
├── evals/                         # 回帰テスト
│   ├── run-evals.sh
│   ├── harness-selftest.sh
│   ├── README.md
│   └── tasks/
├── claude/                        # Claude Code用設定（.claudeから参照）
├── installer/                     # インストール関連
├── generators/                    # コード生成
├── dist/                          # 生成物・配布
├── LICENSE
├── README.md
├── CONTRIBUTING.md
└── CHANGELOG.md
```

## セットアップ

Claude Code のプロジェクト設定で agent-forge を参照：

```bash
ln -s <clone位置>/agent-forge/{rules,skills,agents,hooks,evals} ~/.claude/
```

（詳細は `installer/` 配下のセットアップスクリプトを準備中）

## 使用例

### テスト駆動開発
```
Claude Code: /test-driven-development
→ 試験ファースト（Red）→ 最小実装（Green）→ リファクタ（Refactor）
```

### レビュー前の品質検査
```
Claude Code: /review-ai-antipattern
→ 実装差分をチェック、AIが混入させやすいアンチパターン（過剰設計・未完了の偽装・幻覚API等）を検出
```

### ブランチの完結
```
Claude Code: /finishing-a-development-branch
→ テスト通過確認 → プリコミットチェック → ブランチ保護 → PR作成まで自動化
```

## Third-party notices

- **skills/frontend-design/** — MIT License (see `skills/frontend-design/LICENSE.txt`)
- **superpowers** — 依存関係であり同梱していません。Claude Code 環境で別途構成してください。

## ライセンス

MIT License — Copyright (c) 2026 Ryosuke Ikeda

## 貢献

Issues・PRを歓迎します。日本語・英語どちらでも可。詳細は [CONTRIBUTING.md](CONTRIBUTING.md) を参照。
