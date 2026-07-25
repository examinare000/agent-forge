# trial-log: クロスベンダー最上位ティアの Tier A 同格判断役への格上げ

日付: 2026-07-25（更新: 2026-07-25）

関連: ブランチ `feature/codex-tier-parity`（ベース `feature/token-efficiency`）

## 目的
クロスベンダー最上位ティアモデル（Codex 等）の位置づけを「オフロード先」から「Tier A 同格の判断役（設計第2案・第3票・敵対的検証の代替）」へ、モデル名をハードコードせず能力ベースで格上げする。対象: `rules/02-model-fallback-matrix.md` / `claude/CLAUDE.core.md` / `skills/dual-track-proposals/SKILL.md` / `CHANGELOG.md` + `dist/` 再生成分。

## 現在地
`ai-antipattern-reviewer` によるレビュー実施済み（判定: WARNING）。指摘は以下2件。メイン側で対応要否を判断のうえ、対応した場合はこのファイルへ追記すること。

## レビュー指摘（ai-antipattern-reviewer → メイン転記）

### 1. 「敵対的検証の代替検証役」の適用範囲が未確定ゲートと衝突しうる
- `rules/02-model-fallback-matrix.md:40`（`dist/AGENTS.md:60` / `dist/GEMINI.md:60` に伝播）は、**標準運用（Tier A メイン・降格していない状態）**の独立2票の段落に「他ベンダーの最上位ティアモデルは...敵対的検証の代替検証役を含む」を追記した。これは降格時（`検証役を Tier B に降格せざるを得ない場合`）に限定された line 55 の追記とは異なり、平常運用でも `adversarial-verifier` サブエージェントをクロスベンダーモデルへ差し替えてよいと読める。
- `claude/CLAUDE.core.md:84`「完了ゲートは順に積み重なる...→ `adversarial-verifier` PASS」および同 `:39` は特定のサブエージェント名を名指しして必須ゲートとしている。両者の関係（「代替」は名指しゲートの**免除**を意味するのか、それとも名指しゲートに**加えて**任意に使える追加の判断入力に過ぎないのか）が本文に明記されておらず、拡大解釈により必須ゲートが恣意的にバイパスされうる。
- さらに `rules/02:39` は同じ文中で「手順の正本: `03-agent-behavior.md`『委譲と検証の原則』」を明示しているが、`03-agent-behavior.md` は本ブランチで未変更であり、「設計の代替提案者」「敵対的検証の代替検証役」という新しい用法の起動手順・独立起動要件（票の独立起動など）を一切定義していない（`grep` で該当語ゼロを確認済み）。正本ポインタが指す先に実体が無い状態。
- 再検証条件: `rules/02:40` の文言に「（`adversarial-verifier` PASS ゲート自体の代替にはならない。追加の判断入力として用いる）」等の限定を加えるか、あるいは `03-agent-behavior.md` 側に起動手順を追記して整合させる。どちらを採るかは仕様判断のためメインで決定する。

### 2. `skills/dual-track-proposals/SKILL.md:30` の言語一貫性
- 追加された `- 未導入時は Sonnet 独立2案で実施する。` は全文英語のステップリスト（他の全箇条書きは英語主文 + 日本語の括弧注記という既存パターン）の中で唯一、独立した全文日本語の文になっている。既存の混在パターン（英語主文＋日本語括弧注記）を破っており、英語ファイルとしての一貫性を欠く。
- 提案: 前段の bullet（`codex:codex-rescue` 行）の括弧注記に戻すか、`If not installed, fall back to two independent Sonnet proposals.` のように英語化する。

## 判明した事実
- `python3 generators/build.py` 実行後も `dist/` に追加差分は出ず（既に正しく再生成済み）。`bash generators/selftest.sh`（86 pass / 0 fail）・`bash generators/check-agent-blocks.sh`（6 blocks × 24 targets OK）とも green。
- モデル名（GPT-x 等）のハードコードは無し（`git diff` の追加行に該当パターンなし）。`dist/AGENTS.md` / `dist/GEMINI.md` に `codex:codex-rescue` 等 Claude 専用機構への言及の漏れ無し。
- スコープ逸脱（依頼外ファイルの変更）は無し。`git status --short` は依頼で明示された7ファイルのみ。

## adversarial-verifier REJECT の処置（メイン転記・2026-07-25）
指摘 1（限定節の不備）への当初対応は不十分と判定され、以下で再修正した:
- (a) 常時ロードされる CLAUDE.core.md 側にも「名指しゲートの免除ではない / 代替検証役は自ベンダー Tier A で維持できない場合のみ / read-only 起動」の限定を明記。
- (b) 「Tier B 降格運用時のみ」の表現は rules/02 の用語法で「メインの降格運用」（同運用では adversarial PASS が必須）を指してしまい自己矛盾だったため、「検証役の Tier A ピン維持の文脈で自ベンダー Tier A を充てられない場合」へ書き換え。
- (c) 代替検証役に read-only 制約を明記（adversarial-verifier の read-only 性を引き継ぐ）。
- (d) rules/02 の追記文は「Tier A ピン維持の手段」（クロスベンダー最上位ティアを検証役に用いればピンを維持できる。下位ティア降格はその手段も無い場合の最終手段）へ再構成し、到達不能条件を解消。
- 新規の Sonnet ハードコード（SKILL.md fallback 行）を implementer-tier 表現へ修正（rules/02 のティア名参照規則に整合）。既存の見出し・冒頭の codex × sonnet 表現は既存記述としてスコープ外（将来課題）。
- 「同格・内容で評価」と矛盾する「通常はクロスベンダー案が主案になる」文を削除。
- rules/03「委譲と検証の原則」にクロスベンダー同格判断役の起動規律（反証ファースト前置き・独立起動・read-only）を追加し、rules/02 からのポインタの実体を用意。
- CLAUDE.core.md の dual-track 行にも「両案は同格 — 出自ではなく内容で評価」を反映。

## adversarial-verifier 再検証 CONDITIONAL PASS の条件処置（メイン転記・2026-07-25）
- C1: hosts/claude/02 の降格手順に「クロスベンダー read-only 代替検証役で Tier A ピン維持 → それも不可なら sed 降格」の中間段を追加（正本 rules/02 と発動条件を一致させた）。
- C2: rules/02 の参照を実在見出し「格下げの順序（検証役は最後まで守る）」へ修正。
- C3: rules/03 に read-only の実現手段（タスク文で read-only / propose-only を明示しフォワーダの既定 --write を封じる）を明記。
- C4: 例外発動時の 1 行宣言義務を rules/02 に追加（自己ティア判定の宣言義務と同型）。
- C5: 「implementer-tier」未定義語を「Tier B coders」へ修正（ティア名参照規則に整合）。
- C6: CLAUDE.core.md の dual-track 行の sonnet 表記をティア表現 + ホスト対応表ポインタへ抽象化。
- C7: 本ファイルの残タスク重複を解消（旧節を解消済み注記へ置換）。
- C8: CHANGELOG の記述に限定（通常ゲート維持・代替は Tier A 維持不能時のみ・read-only）を反映。

## 残タスク
- なし（adversarial-verifier 最終判定 PASS。宣言義務の常時ロード側反映も適用済み。ADR-003 へ昇格済み）
