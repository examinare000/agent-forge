# 02. モデルティア運用マトリクス

メインセッションを担うモデルのティアに応じて、役割分担と義務を切り替えるための**正本**。
**メインのティアは、設定キーによる固定ではなく実際に選択されている実効モデル**（フォールバック等の override 適用後）で判定する。**Tier S と Tier A はいずれも標準運用**であり、適用される義務は同一。
**ティアは運用上の許可範囲**（どの役割を担ってよいか・どの義務を負うか）であり、能力順位ではない。同じティアに入ることは、異なるモデルの実測性能が同等である証明にはならない。ベンダー横断の同条件比較は未実施であり、モデル間の絶対順位は本書で定めない。
最上位モデルが暗黙にこなす深い推論・自己懐疑は、**構造（発火義務・検証強化・独立多数決）で常時補う**。この構造は全ティア共通に適用し、Tier B 以下では追加義務を重ねる。

> **単一更新点**: モデル ID をリテラルで持つ実体の一覧と、改名・世代交代・降格時の更新手順は `~/.claude/reference/model-id-update-points.md`。他のルール・スキルの本文はティア名（S/A/B/C）でのみ参照し、リテラル ID を書かない。

## ティア定義（ベンダー中立）

| ティア | 定義 | 位置づけ |
|---|---|---|
| **Tier S** | ベンダーが提供する最上位ティア（無いベンダーでは定義しない） | 標準運用の一つ。義務は Tier A と同一。担当の推奨: 曖昧な要求から長い工程を通して判断を続ける仕事。フォールバック先は動的なので**実効モデルを照会して判定する** |
| **Tier A** | 各ベンダーの現行世代の上位推論モデル | **標準運用**（義務定義の基準ティア）。推論の明示化と独立検証を常時義務付ける。担当の推奨: 普段の判断、対話的な設計、分解、レビュー。effort はハーネスまたは API の既定に従い、ロールごとの下限は「effort 下限」の表で別途課す（既定値と下限は別項目） |
| **Tier B** | 各ベンダーの標準・中位モデル | 降格運用（Tier A 不在時）。単独判断を制限し検証を最大化する。実装役では標準構成の一部。担当の推奨: 範囲が明確な実装と反復修正。メインを担う時は「降格時の追加義務」に従う |
| **Tier C** | 軽量・高速系モデル | 委譲・リレー・機械的作業専用（機械的＝**単一ソースの決定的コピー/変換**に限る。複数ソースの再構成・形式規約の適用など判断を要する作業は Tier B 以上へ）。**判断役（設計・レビュー・オーケストレーター）禁止** |

## Claude のモデル対応

<!-- host:claude -->
Claude におけるティアとモデルの対応（provider 固有。他ホスト向け生成物には含めない）。モデル ID の更新手順は `~/.claude/reference/model-id-update-points.md`。

| ティア | Claude モデル | 備考 |
|---|---|---|
| **Tier S** | `claude-fable-5-1`（Fable） | 安全クラシファイア由来の refusal 偽陽性がセキュリティ隣接のコーディング（hook・permission・脆弱性対応）で起こりうる。頻発時はメインを Opus へ切り替える（Opus 5.5 にも安全分類器の公式説明があり、切替で必ず解消するとは限らない。経緯は `~/.claude/reference/model-id-update-points.md`「履歴」） |
| **Tier A** | `claude-opus-5-5`（Opus） | メインセッションの標準。検証役のピン先 |
| **Tier B** | `claude-sonnet-5-5`（Sonnet） | 降格運用時のメイン。ワーカー用途では標準構成の一部 |
| **Tier C** | `claude-haiku-5-5`（Haiku） | 委譲・リレー・機械的作業専用。判断役禁止 |

installer が配置する 8 エージェントの frontmatter `model` / `effort` / `maxTurns`（`model` はエイリアス指定のみで ID は直書きしない）:

| エージェント | model | effort | maxTurns | ティア | 役割 |
|---|---|---|---|---|---|
| `testability-architect` | opus | high | 20 | A | 設計・境界・タスク分解 |
| `adversarial-verifier` | opus | high | 20 | A | 推論成果物の反証ファースト検証 |
| `tdd-strict-coder` | sonnet | high | 20 | B | 実装・バグ修正 |
| `code-reviewer` | sonnet | high | 20 | B | フレッシュコンテキストのコードレビュー |
| `ai-antipattern-reviewer` | sonnet | high | 20 | B | AI アンチパターン検査 |
| `git-composer` | sonnet | medium | 25 | B | git/gh 変更系の一元実行 |
| `implementation-coder` | sonnet | medium | 20 | B | 仕様固定の忠実実装（判断を要する作業を含むため Tier B 以上） |
| `test-runner` | haiku | low | 12 | C | テスト・lint・型チェックの実行報告（read-only） |

ティアは運用上の許可範囲であり、effort はロール別の下限として frontmatter で課す（ADR-005）。

検証役ピンの降格手順（最終手段）は `~/.claude/reference/model-id-update-points.md`「エージェントピンの降格手順」。
<!-- /host:claude -->

## クロスベンダーのティア対応

**正本規則（抽象）**: ティアは**ツールではなく、解決後の (model, reasoning effort) の組に付く**。各ベンダーのモデルを 3 系統に分け、系統ごとに effort 下限でティアを判定する:
- **フラッグシップ推論モデル（現行世代の最上位）**: effort **medium 以上 = Tier A 相当** / low 以下 = Tier B 相当
- **中位（同世代のワークホース・前世代のフラッグシップ）**: high 以上 = Tier A 相当 / それ未満 = Tier B 相当
- **軽量（mini・nano・flash・fast 級）**: high 以上 = Tier B 相当 / それ未満 = Tier C 相当（判断役不可。`95-orchestration-protocol.md` 第1段）

Tier S 相当は定義しない。現行モデル名の例示は `~/.claude/reference/model-id-update-points.md`（非正本）。
担当の推奨（公式資料に基づく。実測順位ではない）: Codex 側で完結する実装・テスト追加・調査・通常修正は中位、難しい障害解析・設計上の難所・別ベンダーからの検証はフラッグシップ。中位モデルの実装推奨を理由に、中位 / `medium` を標準のオーケストレーターへ無条件に昇格させない。

**判定ティアが担える役割の上限**: Tier A 相当 = 判断役を含む全ロール（第2票・第3票の担い手として。検証役ロールの Tier A ピンの置換ではない） / Tier B 相当 = 実装・code-review・test-execution・第3票は code-review 側のみ / Tier C 相当 = 定型変換・探索のみ。

### Codex 側のモデル解決
**Main と native SubAgent を分ける**。Main は指示解釈・全体把握・独立に検証できる小さなタスクへの分解・実行指示・最終判断を担う。Main のモデル設定は `~/.codex/config.toml` またはセッションで選択した実効値に従い、SubAgent へ一律に継承しない。

カスタム agent ファイルに設定した `model` / `model_reasoning_effort` が優先する。未設定分は起動時の明示値、`[agents]` の既定、親の値の順に解決する（モデルだけを起動時または `[agents]` で指定した場合はそのモデルの既定 effort）。config の値だけで実効モデルを断定しない。実行機構の詳細と独立レビューの起動方法は `~/.claude/reference/delegation-routes.md`。

### effort 下限
外部 Codex 委譲の effort 下限は次表を維持する。外部委譲は model 未指定を既定とし、利用経路が解決した model と指定 effort の組でティアを判定する。

| ロール | effort 下限 |
|---|---|
| architecture | xhigh |
| adversarial-review / code-review / ai-antipattern-review / tdd-implementation | high |
| faithful-implementation / test-execution / git-compose / 定型変換 | 指定なし（config 既定） |

Codex 側で tdd-implementation と faithful-implementation を同一エージェントが兼任する場合は high で運用する。**優先規則**: 判定ティアの足切りと上記下限表の両方を満たした時だけそのロールを担える。限定用途を拡大して下限を回避しない。

### 義務の代替
非 Claude 環境で Tier 義務が参照するエージェント（`adversarial-verifier` 等）の起動経路が無い場合は、クロスベンダー相互検証（Gemini ⇄ Codex）または**ユーザー承認**で代替する（実行不能な義務を課さない）。Codex 単独セッションは同名のカスタムエージェントで義務を履行する。

## 役割 × ティア割当表（正本。役割は論理ロールIDで書く）

「標準（S / A）」はメインを Tier S または Tier A が担う運用、「B 降格時」はメインを Tier B が担う運用。
**B 降格時も、サブエージェント用途で Tier A が呼び出せる限り検証役の Tier A ピンは維持する**。Tier A がサブ用途でも完全に不在の場合のみ、検証役を Tier B に降格し、代償として 91 のクロスベンダー多数決を**常時必須**とする。

| 役割 | 標準（S / A メイン） | B 降格時 |
|---|---|---|
| オーケストレーター（メイン） | Tier S または Tier A（effort はハーネス既定）。93 は前提が崩れると高くつく時に発火してよい（`05-stance-and-triggers.md`「判断の構え」） | Tier B + 同左 |
| 設計・タスク分解 | メインが行ってよい。大コンテキスト隔離・専門判断が効く時は `architecture` ロール (Tier A) へ委譲。**アーキテクチャ級決定は独立 2 票（91）を必須** | `architecture` ロールへの委譲を推奨。アーキテクチャ級は 91 の多数決検証 |
| 敵対的検証（推論成果物） | 高リスク（アーキテクチャ・セキュリティ・非可逆）の計画承認・完了宣言前に `adversarial-review` ロール (Tier A / high) を起動する。起動したゲートは PASS 取得後に完了宣言する（ループの終了条件は `91-subagent-quality-gate.md`「品質ゲートの運用フロー」）。通常作業では起動しない | 同左。加えて不一致時クロスベンダー第3票 |
| AI アンチパターン検査 | 91 のゲート発動中に Worker が生成した実装差分は完了宣言前に `ai-antipattern-review` ロールを必須実行（single-loop の通常作業では任意。明示依頼時は実行） | 同左 |
| 実装・テスト・git | Tier B / Tier C（現行構成） | 同左 |

## 標準運用の義務（Tier S / Tier A）と降格時の追加義務（Tier B）

**非自明タスクの定義**: Skill `deep-reasoning` の発火チェックリストに該当するタスク。発火するかは構えとして選ぶ（`05-stance-and-triggers.md`「判断の構え」）。ティアで閾値を変えない。

- **標準運用（Tier S / Tier A メイン）**: 上記「役割 × ティア割当表」の標準列がそのまま義務。通常作業は single-loop で完結してよく、routine double gate は行わない。
- **Tier B メイン。標準義務に加えて**:
  - 設計判断は `architecture` ロールへの委譲を推奨する。アーキテクチャ級は 91 の多数決手順にかける。
  - `03-agent-behavior.md` のエスカレーション閾値を**強化**（修正 2 回失敗 ➔ 1 回失敗で `systematic-debugging`、未検証前提 3 件 ➔ 1 件で質問）。

## 格下げの順序（検証役は最後まで守る）

コスト等の理由でエージェントのモデルピンを下げる場合、順序は **実装役 ➔ メイン ➔ 検証役**。
検証役ロール（`architecture` / `adversarial-review`）の Tier A ピンは、Tier A が（サブエージェント用途を含め）存在する限り**維持する**。検証側の厚みが品質担保の核であり、検証役を Tier B まで落とす場合に 91 のクロスベンダー多数決を代償として要求しているのは能力差を埋めるためである。
要求は「検証役を Tier A 以上に保つ」ことであり、メインが Tier S なら検証役は 1 つ下、Tier A なら同格でよい（検証役を Tier S へ引き上げる必要はない）。降格の実手順は `~/.claude/reference/model-id-update-points.md`。

## 自己ティア判定（セッション開始時・モデル変更時）

1. 自分の**実効モデル**を確認する。refusal が疑われる挙動を認めたら実効モデルを照会し、フォールバックのラッチ継続中は**そのモデルのティアで運用する**（照会できなければ 3. の安全側デフォルト）。
2. **標準ティア（S / A）のいずれでもなければ**、作業開始前に適用ティアを 1 行宣言する（例: 「**Tier B 運用**: 設計自前確定禁止・エスカレーション閾値強化を適用します」）。標準運用では宣言不要。
3. 自モデルのティアを判定できない場合は **Tier B の義務を適用する**（安全側デフォルト）。
4. 宣言したティアの義務を、そのセッション中は解除しない。

---
**適用優先度**: 🔴 絶対（全員・常時。deep-reasoning の発火条件は `93-deep-reasoning-protocol.md` が担う）
