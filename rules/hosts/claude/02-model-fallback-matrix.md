# 02. Claude モデル対応（ホスト固有マッピング）

**正本は `../../02-model-fallback-matrix.md`**（ティア定義・義務・格下げ順序・自己ティア判定）。
本ファイルは Claude ホストにおける**具体的なモデル名対応とエージェントのモデルピン**のみを定める。

## ティア ↔ Claude モデル対応表

| ティア | Claude モデル | 備考 |
|---|---|---|
| **Tier A** | `claude-opus-*` | メインセッションの標準。検証役（`testability-architect` / `adversarial-verifier`）のピン先 |
| **Tier B** | `claude-sonnet-*` | 降格運用時のメイン。ワーカー用途では標準構成の一部（コーディングで旧上位世代級） |
| **Tier C** | `claude-haiku-*` | 委譲・リレー・機械的作業専用。判断役禁止（正本のティア定義に従う） |

## 同梱エージェントのモデルピン一覧

installer が `~/.claude/agents/` に配置する 8 エージェントの frontmatter `model` 行:

| エージェント | model | ティア | 役割 |
|---|---|---|---|
| `testability-architect` | opus | A | 設計・境界・タスク分解 |
| `adversarial-verifier` | opus | A | 推論成果物の反証ファースト検証 |
| `tdd-strict-coder` | sonnet | B | 実装・バグ修正 |
| `code-reviewer` | sonnet | B | フレッシュコンテキストのコードレビュー |
| `ai-antipattern-reviewer` | sonnet | B | AI アンチパターン検査 |
| `git-composer` | sonnet | B | git/gh 変更系の一元実行 |
| `implementation-coder` | haiku | C | 仕様固定の忠実実装 |
| `test-runner` | haiku | C | テスト・lint・型チェックの実行報告（read-only） |

## 降格手順（最終手段。opus が完全不在の時のみ）

正本の「格下げの順序」（実装役 ➔ メイン ➔ 検証役）に従う。opus がサブエージェント用途でも
呼び出せなくなった場合、まず**クロスベンダー最上位ティアを read-only の代替検証役として用いて
Tier A ピンを維持する**（正本: `../../02-model-fallback-matrix.md`「格下げの順序」。起動規律は
`../../03-agent-behavior.md`「委譲と検証の原則」— タスク文で read-only / propose-only を明示する）。
検証役のピン降格（下記 sed）は、その手段も使えない場合の最終手段:

```bash
# 対象: ~/.claude/agents/ の frontmatter model 行のみ（sed -i '' は BSD/macOS 構文。Linux では sed -i）
sed -i '' 's/^model: opus$/model: sonnet/' \
  ~/.claude/agents/testability-architect.md ~/.claude/agents/adversarial-verifier.md
# 降格したらクロスベンダー多数決（第3票）を常時必須に切り替える（正本「格下げの順序」参照）
```

---
**適用優先度**: 🔴 絶対（Claude ホスト時。義務の定義は正本 `../../02-model-fallback-matrix.md`）
