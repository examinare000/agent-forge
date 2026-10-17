# 資料: モデル ID の単一更新点と降格手順（`02-model-fallback-matrix.md` の補足）

## 単一更新点（モデル ID をリテラルで持つ実体）
改名・世代交代時はここだけを更新する。

1. Claude モデル対応表（`rules/02-model-fallback-matrix.md`。ホスト別マッピングを `rules/hosts/claude/` に分離している構成では、そちらの `02-model-fallback-matrix.md` の「ティア ↔ Claude モデル対応表」）
2. `agents/*.md` の frontmatter `model:` は `opus|sonnet|haiku` のエイリアス指定のみ。ID を直書きしないので世代交代の更新対象外
3. `dist/codex-agents/*.toml` のコメント内のモデル表現は `generators/build.py` の生成物。手編集せず、`agents/*.md` を直したうえで `python3 generators/build.py` で再生成する
4. `~/.codex/config.toml` の `model`（Codex 利用時のみ。Codex Main と、model 未指定の外部起動の既定。native SubAgent のモデルとは分離する）

## 履歴（可用性変動の前例。世代固有の記述は当時の世代に限る）
- Fable 5 は 2026-06 に輸出規制で一時停止→2026-07-01 再デプロイ。再デプロイ声明時点のフォールバック先は Opus 4.8 と記載（以降未確認）。不在時は Tier A メインが標準。
- output-style `fable-like` は 2026-07-26 に廃止済み。「Fable ライク」規範の実体は各エージェント定義内の報告規範と `03-agent-behavior.md` の共通規律。
- Fable 5 は 2026-07-31 から既定（2026-10-12 時点の実効 ID は `claude-fable-5-1`）。1 ターンが数分に及ぶことがあり、従量クレジット（別予算）を消費する。**Opus 5 世代の記述**: コストが半分で多くの領域で肉薄し、refusal クラシファイアが無いためセキュリティ色の強い作業の切替先だった。Opus 5.5 には安全分類器に関する公式説明があるため、この記述を 5.5 へ一般化しない。切替先としての有効性は実測で判断する。
- 2026-10-12: ティア定義表の ID を 5.1 / 5.5 世代へ更新。ティアを「運用上の許可範囲」と明記し、能力順位の記述を分離。

## クロスベンダーのモデル例示（非正本。抽象規則は 02）
- **GPT 系**（2026-10-12 時点の `~/.codex/models_cache.json` 実測）: フラッグシップ = gpt-6-astra / 中位 = gpt-6.1-sol・gpt-6-sol・gpt-5.6-sol・gpt-5.6-terra / 軽量 = gpt-6-luna・gpt-5.6-luna / hidden（gpt-reserve・gpt-5.5）と codex-auto-review（内部用）は委譲先にしない。当時の config 既定は gpt-6.1-sol / medium。2026-10-16 の Main は gpt-6-astra / xhigh、native SubAgent は独立した role profile を使う。
- **Gemini 系**: Pro 世代最上位 → Tier A 相当、Flash 系 → Tier B～C 相当
- 例: gpt-6-astra / medium は Tier A 相当だが adversarial-review は effort 下限 high 未満なので不可。`--effort high` を明示して初めて可。
- 例: gpt-6.1-sol / medium は中位なので Tier B 相当。native の許可済み Git・中継にも使えるが、敵対的検証には足りない。gpt-6.1-sol / high は Tier A 相当となり、第3票（adversarial-review）を担える。

## エージェントピンの降格手順（最終手段。opus が完全不在の時のみ）
正本は `rules/hosts/claude/02-model-fallback-matrix.md`「降格手順」。クロスベンダー最上位ティアを read-only の代替検証役に充てられない場合に限り、検証役のピンを下げる。

```bash
# 対象: ~/.claude/agents/ の frontmatter model 行のみ（sed -i '' は BSD/macOS 構文。Linux では sed -i）
sed -i '' 's/^model: opus$/model: sonnet/' \
  ~/.claude/agents/testability-architect.md ~/.claude/agents/adversarial-verifier.md
# 降格したらクロスベンダー多数決（第3票）を常時必須に切り替える（正本「格下げの順序」参照）
```
