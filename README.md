# agent-forge

**agent-forge** is an open-source bootstrap framework that automatically configures AI coding agents to follow a naming-convention-organized `agent-rules` set, so they autonomously handle model selection, task decomposition, delegation, and self-improvement loops. It packages rules, skills, subagents, hooks, and evals into a disciplined, orchestrator-style operating model for Claude Code, OpenAI Codex, and Gemini CLI. One installer sets up your global environment; one scaffold command spins up a new project that uses it from day one. The core intentionally excludes personal engineering preferences (git strategy, testing strategy, Docker, frontend design) — the numbered rule bands are left open for adopters to add their own conventions. Whether you're starting your first AI-driven build or hardening an existing one, agent-forge gets you a working baseline in minutes. Documentation below is in Japanese.

---

## 概要

命名規則で整理された `agent-rules` により、AIコーディングエージェントがモデル選択・作業分解・タスク委譲・自己改善ループを自律的に回す設定を自動で行うフレームワークです。個人の工学的嗜好（git戦略・テスト戦略・Docker・フロントエンド設計）はコアから外し、番号体系は採用者が自分の規約を追加する受け皿として残します。これからAI駆動で開発やビジネスを始める人が、最短で「規律ある運用」から着手できることを目指しています。中身は次の「何が手に入るか」を参照してください。

## 何が手に入るか

| 資産 | 役割 | 内容 |
|---|---|---|
| `rules/` | 規範 | エージェントが常に従うべきホスト非依存の基盤原則（コア原則・モデルティア・セキュリティ・深度推論等）。`10-29`（ワークフロー）・`70-89`（言語/環境）は採用者が自分の工学規約を追加する意図的な空き番帯 |
| `skills/` | 手続き | 特定作業の実行手順を型化したスキル（レビュー・ブランチ完結など） |
| `agents/` | サブエージェント（8体） | アーキテクト・TDDコーダー・実装コーダー・テスト実行・コードレビュワー・gitコミット担当・反証検証者・アンチパターンレビュワーの8役に分かれたサブエージェント定義 |
| `hooks/` | 強制ゲート（3本） | デバッグログ残留検出・コンパクト前バックアップ・編集後lintなど、規約を機械的に強制するフック |
| `evals/` | 挙動回帰 | エージェント/スキルのゴールデンタスクを実際の `claude` CLI で手動実行し、決定的アサートのみで退行を検出する回帰基盤 |
| `installer/` | ユーザー環境導入 | `~/.claude/` へ rules・skills・agents・hooks を絶対パスsymlinkで導入・検査（doctor）・アンインストールするインストーラ |
| `scaffold/` + `bin/forge` | 新規プロジェクト生成 | `forge new` で任意ディレクトリに新規プロジェクトの雛形（CLAUDE.md・.mcp.json・AGENTS.md等）を生成する統一CLI |
| `generators/` + `dist/` | Codex・Gemini向け生成物 | rules/skillsを素材に `dist/AGENTS.md`・`dist/GEMINI.md`・Codexプラグイン・Codexエージェント定義を自動生成 |

## 対応ホスト

- **Claude Code（ネイティブ対応）** — `.claude/` 配下に配置して即運用可能
- **OpenAI Codex / Gemini CLI** — `dist/` 生成物経由（`generators/build.py` が自動生成。`AGENTS.md`/`GEMINI.md` は `forge new` がプロジェクトへ配置、`codex-agents` はプロジェクトの `.codex/agents/` へ自動配置）

## ステータス

v0.1.0 開発中

## ディレクトリ構成

```
agent-forge/
├── bin/                            # 統一CLI
│   └── forge                      # install/new/check の薄いディスパッチャ
├── rules/                          # 規範・戦略ドキュメント（10-29・70-89は採用者が追加する意図的な空き番帯）
│   ├── 00-core-principles.md      # コア原則
│   ├── 02-model-fallback-matrix.md # モデルティア運用マトリクス
│   ├── 03-agent-behavior.md       # エージェント挙動規範
│   ├── 12-security-guidelines.md  # セキュリティ
│   ├── 13-readability.md          # 可読性
│   ├── 30-documentation-management.md  # ドキュメント管理
│   ├── 50-production-reliability.md    # 本番信頼性
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
├── hooks/                         # 編集ゲート
│   ├── backup-before-compact.sh
│   ├── block-debug-log-residue.sh
│   ├── block-debug-log-residue.test.sh
│   └── lint-after-edit.sh
├── evals/                         # 回帰テスト
│   ├── run-evals.sh
│   ├── harness-selftest.sh
│   ├── README.md
│   └── tasks/
├── claude/                        # Claude Code用設定（.claudeから参照）
├── installer/                     # インストール関連（install.sh・manifest.json等）
├── scaffold/                      # 新規プロジェクト雛形生成（new-project.sh・templates/）
├── generators/                    # 多ベンダー向け指示ファイル生成器（build.py）
├── dist/                          # 生成物・配布（AGENTS.md・GEMINI.md・codex-plugin/・codex-agents/）
├── LICENSE
├── README.md
├── CONTRIBUTING.md
└── CHANGELOG.md
```

## 15分クイックスタート

### 前提

- `git` / `jq` / `claude`（Claude Code CLI）が必要です。未導入の場合は `installer/manifest.json` の `prereqs.installHints`（OS別コマンド）を参照してください。
- 任意: `gh` / `uv` / `node` / `codex` / `gemini`（無くても動作しますが、Codex/Gemini対応まで進めるなら推奨）

### 手順

```bash
# 1. clone
git clone https://github.com/examinare000/agent-forge.git ~/git/agent-forge
cd ~/git/agent-forge

# 2. ~/.claude へ rules/skills/agents/hooks を導入（グローバル・絶対パスsymlink）
./bin/forge install

# 3. 新規プロジェクトの雛形を作成（既定: copyモード・自己完結）
./bin/forge new ~/projects/my-app

# 4. 開発を開始
cd ~/projects/my-app && claude
```

- `forge install --check` はいつでも read-only で導入状態を診断できます（doctorモード。`~/.claude` のsymlink健全性・prereqs CLI・superpowers・settings.jsonを検査）。
- `forge new` は git初期化（`main`のみ）・`AGENTS.md`/`GEMINI.md`のコピー・`.mcp.json`等のプロジェクト固有設定・`scripts/check-agent-assets.sh`の設置までを一括で行います。既存ファイルは上書きしないため再実行しても安全です。
- 生成したプロジェクトの状態は `forge check ~/projects/my-app`（または `cd ~/projects/my-app && bash scripts/check-agent-assets.sh`）でいつでも検証できます。

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

## 発展

### `--mode link`（上級者向け・installer導入済み前提）

`forge install` 済みであれば、`forge new <dir> --mode link` で `CLAUDE.md` を `~/.claude/CLAUDE.core.md` へ絶対パスsymlinkとして張ります。ルール更新が生成済みの全プロジェクトへ即座に波及するため、複数プロジェクトを横断管理する場合に向きます。`.claude/rules/README.md`（自分の規約を追加する導線）はcopy/linkどちらのモードでも常に実体コピーします。`forge install` が未実施の環境では明示的にエラーで停止します。

### Codex / Gemini CLI ユーザー向け

Claude Code以外のホストは `generators/build.py` が `rules/`・`skills/` から生成した `dist/` の成果物を使います。

- `dist/AGENTS.md` — Codex CLI 向けの統合ルール
- `dist/GEMINI.md` — Gemini CLI 向けの統合ルール
- `dist/codex-plugin/` — Codex CLI のプラグインとして読み込めるskill群（`plugin.json` + `skills/`）
- `dist/codex-agents/` — Codex用エージェント定義（`.toml`。`agents/` の8体に対応）

`forge new` はcopy/linkいずれのモードでも `dist/AGENTS.md`・`dist/GEMINI.md` を生成先プロジェクトへ自動コピーします。再生成が必要な場合は `python3 generators/build.py` を実行してください（`dist/` 配下は直接編集しない）。

### コンパニオンプロジェクト

- **agent-recall**（`../agent-recall`）— セッションの教訓・振り返りを蓄積し自己改善サイクルに繋げるプラグイン（URL: `https://github.com/examinare000/agent-recall`）
- **agent-shelf**（`../agent-shelf`）— 書籍・ドキュメントのコーパスに対するcited Q&A形式のRAG知識書庫MCP（URL: `https://github.com/examinare000/agent-shelf`）

**独立導入性**：agent-forge / agent-shelf / agent-recall は互いに独立して導入可能です。任意の組み合わせで動作し、併用時のみ連携機能（shelf=外部知識の証拠源、recall=rule 94 の検索・蒸留基盤）が有効になります。

## Third-party notices

- **skills/frontend-design/** — MIT License (see `skills/frontend-design/LICENSE.txt`)
- **superpowers** — 依存関係であり同梱していません。Claude Code 環境で別途構成してください。

## ライセンス

MIT License — Copyright (c) 2026 Ryosuke Ikeda

## 貢献

Issues・PRを歓迎します。日本語・英語どちらでも可。詳細は [CONTRIBUTING.md](CONTRIBUTING.md) を参照。
