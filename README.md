# agent-forge

**agent-forge** teaches AI coding assistants like Claude Code (and OpenAI Codex CLI / Google's Gemini CLI or Antigravity) to work with discipline — plan, split the work, check in, and reflect — instead of improvising. Install it once, and every new project starts with that discipline already built in. The guide below is in Japanese; English speakers can skim [詳細（開発者向け）](#詳細開発者向け) for the technical reference.

---

## これは何？

**agent-forge** は、Claude Code のような AI コーディングアシスタントに「仕事の進め方」の規律を与える設定フレームワークです。大きな依頼に対していきなり実装へ着手するのではなく、**計画 → 分担 → 確認 → 振り返り**というオーケストレーションの型に沿って進めるようにします。

導入すると、AI が場当たり的に実装して終わるのではなく、テストを先に書く・実装差分をレビューする・取り返しのつかない操作の前に確認を挟む、といった手順を自動的に踏むようになります。中身は役割別のサブエージェント定義・手続きスキル・強制フックを組み合わせた設定集で、`forge` CLI が導入・プロジェクト生成・診断までを一括で担います。

## 必要なもの（前提ツール）

| ツール | 必須/任意 | 説明 | インストール |
|---|---|---|---|
| **Claude Code** | 必須（主対象） | Anthropic 製の AI コーディングアシスタント。**利用には Claude アカウント（Pro/Max プラン、または API キー）が必要です** | npm 経由（要 Node.js）: `npm install -g @anthropic-ai/claude-code`<br>macOS/Linux: `curl -fsSL https://claude.ai/install.sh \| bash`<br>公式ドキュメント: https://code.claude.com/docs |
| Google Antigravity / Gemini CLI（代替） | 任意 | Claude Code の代わりに使える Google 製CLI。agent-forge は `dist/GEMINI.md` を生成物として提供します。名称・提供形態が変わりつつあるため、詳細は各公式サイトを参照してください（参考: Gemini CLI リポジトリ https://github.com/google-gemini/gemini-cli 、Google Antigravity https://antigravity.google ） | 各公式サイト参照 |
| OpenAI Codex CLI（代替） | 任意 | Claude Code の代わりに使える OpenAI 製CLI。agent-forge は `dist/AGENTS.md` を生成物として提供します | `npm install -g @openai/codex`（公式: https://github.com/openai/codex） |
| git | 必須 | バージョン管理 | macOS: `brew install git` / Windows: `winget install Git.Git` |
| jq | 必須 | インストーラが内部で使うJSON処理ツール | macOS: `brew install jq` / Windows: `winget install jqlang.jq` |

## 10分セットアップ

```bash
# 1. リポジトリを取得
git clone https://github.com/examinare000/agent-forge.git ~/git/agent-forge
cd ~/git/agent-forge

# 2. rules・skills・agents・hooks 一式を ~/.claude へ導入
./bin/forge install

# 3. 新規プロジェクトの雛形を生成（既存ファイルは上書きしない）
./bin/forge new ~/projects/my-app

# 4. 生成したプロジェクトで Claude Code を起動
cd ~/projects/my-app && claude
```

起動後に「この repo の CLAUDE.md を読んで、何ができるか教えて」と尋ねると、導入されたルール・スキル・サブエージェント構成を AI 自身が説明します。あとは通常どおり実装やバグ修正を依頼すれば、計画→分担→確認→振り返りの手順で進みます。

## 導入で何が変わるか

- **大きな依頼を自動で小さな作業に分解して進める** — 「認証機能を作って」のような大きな依頼も、設計・実装・テスト実行・レビューといった役割別のサブエージェントに分解・委譲されます
- **実装のたびにテストとレビューが挟まる** — 先にテストを書いてから実装する手順（TDD）と、AIが混入させがちな手抜き・過剰実装を検出するレビューが標準で入ります
- **危険な操作の前に確認が入る** — mainブランチへの直接コミットや強制pushなど、取り返しのつかないgit操作の前に確認が挟まります
- **作業の教訓が蓄積され、繰り返し起きる問題がルール化されていく** — セッションの振り返りから再発パターンを見つけ、スキルやルールに反映する仕組みがあります
- **Claude Code 以外でも同じ規律を使い回せる** — OpenAI Codex CLI や Google のCLIでも、生成物（`dist/`）経由で同じルール・スキルを利用できます

上記は実際に同梱されている仕組み（`agents/`・`skills/`・`hooks/`・`rules/94-self-improvement-protocol.md` 等）に基づく説明です。詳細は [詳細（開発者向け）](#詳細開発者向け) を参照してください。

## トラブルシューティング

- `./bin/forge check` で、`~/.claude` への導入状態（symlinkの健全性・前提CLIの有無・設定ファイル）を read-only で診断できます
- 特定プロジェクトの状態を診断したい場合: `./bin/forge check ~/projects/my-app`
- それでも解決しない場合は、GitHub の Issue で質問・報告してください（日本語可）。背景や再現手順を書いてもらえると対応しやすくなります: https://github.com/examinare000/agent-forge/issues
- 脆弱性や悪意あるコード・プロンプト混入を見つけた場合は、公開Issueではなく [SECURITY.md](SECURITY.md) の手順（GitHubのPrivate vulnerability reporting）で報告してください
- 貢献のルール（PRの条件・テストの実行方法・ブランチ運用）は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください

---

## 詳細（開発者向け）

以降はアーキテクチャと各コンポーネントの技術リファレンスです。

### 概要

命名規則で整理された `agent-rules` により、AIコーディングエージェントがモデル選択・作業分解・タスク委譲・自己改善ループを自律的に回す設定を自動で行うフレームワークです。個人の工学的嗜好（git戦略・テスト戦略・Docker・フロントエンド設計）はコアから外し、番号体系は採用者が自分の規約を追加する受け皿として残します。これからAI駆動で開発やビジネスを始める人が、最短で「規律ある運用」から着手できることを目指しています。中身は次の「何が手に入るか」を参照してください。

### 何が手に入るか

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

### 対応ホスト

- **Claude Code（ネイティブ対応）** — `.claude/` 配下に配置して即運用可能
- **OpenAI Codex / Gemini CLI** — `dist/` 生成物経由（`generators/build.py` が自動生成。`AGENTS.md`/`GEMINI.md` は `forge new` がプロジェクトへ配置、`codex-agents` はプロジェクトの `.codex/agents/` へ自動配置）

### ステータス

v0.1.0 開発中

### ディレクトリ構成

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

### コマンドリファレンス

- `forge install --check` はいつでも read-only で導入状態を診断できます（doctorモード。`~/.claude` のsymlink健全性・prereqs CLI・superpowers・settings.jsonを検査）。
- `forge new` は git初期化（`main`のみ）・`AGENTS.md`/`GEMINI.md`のコピー・`.mcp.json`等のプロジェクト固有設定・`scripts/check-agent-assets.sh`の設置までを一括で行います。既存ファイルは上書きしないため再実行しても安全です。
- 生成したプロジェクトの状態は `forge check ~/projects/my-app`（または `cd ~/projects/my-app && bash scripts/check-agent-assets.sh`）でいつでも検証できます。

### 使用例

#### テスト駆動開発
```
Claude Code: /test-driven-development
→ 試験ファースト（Red）→ 最小実装（Green）→ リファクタ（Refactor）
```

#### レビュー前の品質検査
```
Claude Code: /review-ai-antipattern
→ 実装差分をチェック、AIが混入させやすいアンチパターン（過剰設計・未完了の偽装・幻覚API等）を検出
```

#### ブランチの完結
```
Claude Code: /finishing-a-development-branch
→ テスト通過確認 → プリコミットチェック → ブランチ保護 → PR作成まで自動化
```

### 発展

#### `--mode link`（installer導入済み前提）

`forge install` 済みであれば、`forge new <dir> --mode link` で `CLAUDE.md` を `~/.claude/CLAUDE.core.md` へ絶対パスsymlinkとして張ります。ルール更新が生成済みの全プロジェクトへ即座に波及するため、複数プロジェクトを横断管理する場合に向きます。`.claude/rules/README.md`（自分の規約を追加する導線）はcopy/linkどちらのモードでも常に実体コピーします。`forge install` が未実施の環境では明示的にエラーで停止します。

#### Codex / Gemini CLI ユーザー向け

Claude Code以外のホストは `generators/build.py` が `rules/`・`skills/` から生成した `dist/` の成果物を使います。

- `dist/AGENTS.md` — Codex CLI 向けの統合ルール
- `dist/GEMINI.md` — Gemini CLI 向けの統合ルール
- `dist/codex-plugin/` — Codex CLI のプラグインとして読み込めるskill群（`plugin.json` + `skills/`）
- `dist/codex-agents/` — Codex用エージェント定義（`.toml`。`agents/` の8体に対応）

`forge new` はcopy/linkいずれのモードでも `dist/AGENTS.md`・`dist/GEMINI.md` を生成先プロジェクトへ自動コピーします。再生成が必要な場合は `python3 generators/build.py` を実行してください（`dist/` 配下は直接編集しない）。

#### コンパニオンプロジェクト

- **agent-recall**（`../agent-recall`）— セッションの教訓・振り返りを蓄積し自己改善サイクルに繋げるプラグイン（URL: `https://github.com/examinare000/agent-recall`）
- **agent-shelf**（`../agent-shelf`）— 書籍・ドキュメントのコーパスに対するcited Q&A形式のRAG知識書庫MCP（URL: `https://github.com/examinare000/agent-shelf`）

**独立導入性**：agent-forge / agent-shelf / agent-recall は互いに独立して導入可能です。任意の組み合わせで動作し、併用時のみ連携機能（shelf=外部知識の証拠源、recall=rule 94 の検索・蒸留基盤）が有効になります。

### Third-party notices

- **skills/frontend-design/** — MIT License (see `skills/frontend-design/LICENSE.txt`)
- **superpowers** — 依存関係であり同梱していません。Claude Code 環境で別途構成してください。

### ライセンス

MIT License — Copyright (c) 2026 Ryosuke Ikeda

### 貢献

Issues・PRを歓迎します。日本語・英語どちらでも可。詳細は [CONTRIBUTING.md](CONTRIBUTING.md) を参照。脆弱性報告は [SECURITY.md](SECURITY.md) を参照。
