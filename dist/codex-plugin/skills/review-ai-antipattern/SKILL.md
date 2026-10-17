---
name: review-ai-antipattern
description: 作業差分を専用 reviewer サブエージェントに委譲し、AI が混入させがちなアンチパターン（スコープ逸脱・過剰設計・未完了の偽装・表層 slop・幻覚 API）を path:line 根拠付きで検出する手続き。「AI アンチパターンをレビュー」「slop チェック」の明示依頼時、および `AGENTS.md 内の該当節` の品質ゲートで Worker 差分を完了扱いにする前に使う。バグ・正確性のレビュー（/code-review）には使わない。
allowed-tools: Bash(git diff *) Bash(git status *) Bash(git log *)
---

# review-ai-antipattern（AI アンチパターン検出レビューの手続き）

「動くが、依頼の範囲・意図から逸脱している／不誠実な」コードを狙う。バグ検出（`/code-review`）とは観点が異なり、併用する。
レビュー本体はメインで行わず、`ai-antipattern-reviewer`（対応表: `AGENTS.md 内の該当節`。専用定義が無い環境は `general-purpose` を read-only・修正禁止で起動）に委譲し結論だけ受け取る。検査軸の正本は `references/checklist.md`。

## 手順
1. **差分の確定**: 既定は `git diff`（未コミット）／`git diff <base>...HEAD`（ブランチ）。submodule は各リポジトリで個別に取得する（`cd <submodule> && git -c core.excludesFile=/dev/null diff`）。
2. **タスク文脈の収集**: 元の指示・Issue・PR 説明・参照資料。これが無いとスコープ逸脱を判定できないので、不明なら推測でレビューせずユーザーに一度だけ確認する。
3. **委譲**: 下記テンプレートで reviewer を起動する。差分が大きく観点が独立なら 5 軸を並列（1 軸 = 1 reviewer）にしてよい。
4. **統合・提示**: 指摘を `path:line` 根拠付きで重複排除し、重大度順に「どの明示要求に反するか」を添えて提示する。修正はユーザー判断で別タスク（coder）に渡す。

## reviewer への指示テンプレート
> 【タスク文脈】<依頼原文・参照資料・既に決まっている事項>
> 【差分】<取得コマンドと対象範囲。submodule は個別>
> `<この SKILL.md と同じディレクトリの references/checklist.md を絶対パスに展開して記入>` の 5 軸で検出すること。判定根拠は差分内の `path:line`。タスク文脈で明示的に指示・正当化されている変更は指摘しない。確証が持てない疑いは「要確認」として severity を下げる。修正はしない。
> 【出力】各指摘を `{軸 / severity(高・中・低) / path:line / 何が問題か / どの明示要求・指示に反するか / 推奨対応}` で列挙し、最後に「重大なアンチパターン有無」の総括を述べる。

## 禁止
- タスク文脈を持たずにスコープ逸脱を判定する（誤検知の温床）。
- reviewer に修正させる、バグ・正確性の指摘で代替する。
