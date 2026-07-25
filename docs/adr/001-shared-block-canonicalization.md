# ADR-001: エージェント共有ブロックは正準文言コピーペースト + CI 検査で管理する

- ステータス: 採用済み
- 日付: 2026-07-25
- 最終更新日: 2026-07-25

## 背景

agents/*.md には報告規範・trial-log 義務・no-nesting 規律などの定型ブロックが 6〜8 ファイルに複製され、見出し・文言が徐々に乖離していた（3 種の見出し揺れ、code-reviewer のみ別文言の trial-log 節など）。重複はトークンを浪費し、乖離は挙動の不整合を生む。

## 検討した選択肢

1. **ビルド時パーシャル展開（agents/ を生成物化）** — 同期は自動になるが、installer の symlink 正本という前提が崩れ連鎖改修が必要。棄却（詳細: [docs/trial-log/shared-block-canonicalization.md](../trial-log/shared-block-canonicalization.md)「棄却した案」）。
2. **正準文言コピーペースト + CI ドリフトチェック** — `generators/agent-blocks/*.md` を正本とし、対象ファイルへのバイト一致包含を `generators/check-agent-blocks.sh` が CI で検査。編集時の同期は手動だが、乖離は CI が事後検知する。採用。

## 決定

選択肢 2 を採用。正準ブロックは `generators/agent-blocks/` に置き（agents/ 配下に置くと symlink 経由で配布物に露出するため）、CI の generators selftest 直後に検査を実行する。

## 理由

共有ブロックは高々 6 種 × 24 対象で変更頻度が低く、機械展開の恒常的な複雑さ（編集フロー・installer・降格手順の改修）に投資が見合わない。既存 CI の dist ドリフトチェックと同型の安価な検査 1 本で乖離を防げる。

## 結果

- エージェント本文の重複が正準 6 ブロックへ統一され、文言ドリフトが CI でブロックされる。
- ブロック変更時は `generators/agent-blocks/` と全対象ファイルを同時に更新する必要がある（CI が失敗で教える）。
- 再検討条件: エージェント数の大幅増、またはブロック変更頻度の上昇。
