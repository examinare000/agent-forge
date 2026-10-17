# trial-log: 姉妹 private リポジトリの rules 改善の一方向移植

日付: 2026-10-17

関連: ブランチ `feature/sync-*`（rules 再同期）、`docs/adr/005-rules-resync-and-agent-tier-policy.md`

## 目的
姉妹の private リポジトリで実証済みの改善のうち、OSS の目的に合う generic なものだけを一方向（private から OSS）に移植する。個人識別子と private 固有の運用は持ち込まない。

## 前提
- 最終同期は 2026-08-17。以降の差分が移植対象。
- 制約 1: 位置除外。移植元で private 固有の節は位置（節単位）で除外し、残りを取り込む。
- 制約 2: host フェンス。provider 別の記述は `host:` フェンスで囲み、dist 生成時に該当 provider 以外から除く。
- 制約 3: 正準ブロック。`generators/agent-blocks/` の 7 種は 27 箇所にバイト一致で埋め込む必要がある。
- 未検証: 移植元の将来の変更が本ブランチの取り込み粒度と衝突するか。

## やったこと
1. `hosts.toml` に置換規則（reference 案内・SendMessage・maxTurns）を追加し、selftest に host フェンス漏れの検出を加えた。
2. `reference/` を新設し、installer に `~/.claude/reference` の symlink を追加した。
3. rules 00/02/03/12/13/30/50/93/94 を再同期した（本文は「トリガと義務」、手順は `reference/`）。
4. `rules/hosts/claude/{01,02,91,92}` を廃止し、91/92 を top-level 化、01 を `CLAUDE.core.md` の「動作制約」へ統合した。索引・README・`hosts.toml` の死文を削除した。
5. rules 04/05/95 を新設した（95 末尾に論理ロール対応表）。
6. skills 4 本を `SKILL.md` + `references/` へ slim 化し、`long-running-tasks` skill を追加した。
7. 正準ブロック `trial-report` を新設し、`trial-log-reviewer` ブロックに追記した（7 blocks × 27 targets）。
8. `CLAUDE.core.md` を構え層へ書き換え、02 のピン表を更新し、agents 8 本の frontmatter（model/effort/maxTurns/memory/disallowedTools）と本文を更新した（方針は ADR-005）。
9. `generators/check-private-refs.sh` とそのテスト、CI step を追加した。
10. `CHANGELOG.md` の未リリース節を更新し、本ファイルを記録した。

## 結果
- 全ゲート ok（selftest、check-agent-blocks、各テスト）。
- dist への host フェンス漏れ 0。
- `check-private-refs.sh` の個人識別子ヒット 0。

## 残課題
- agents の effort 方針変更（検証役 opus/high ほか）は、実運用で品質とコストを観察して見直す。
- `scaffold/new-project.sh` と `build.py` に旧出所の注記が残っている。
- `strip_host_fences` が行頭固定でないため、インデントされたフェンス行の扱いが曖昧。行頭固定にする改修候補。
- `deep-reasoning` の発火チェックリストを rule 05 へ移す案は未実施。

## 棄却した案

### OSS 完成形ファイルの丸ごと置換
- 棄却理由: OSS 側にだけある正準ブロックの埋め込みが失われ、check-agent-blocks が落ちる。差分を位置単位で取り込む方式にした。

### `reference/` を `rules/` 配下へ置く
- 棄却理由: `rules/` は常時ロードされるため、手順書を置くと毎セッションのトークンを消費する。`rules/` の外に置いた（ADR-005）。

### `Fable` 不在での漏れ検出
- 棄却理由: 既存の置換規則が先に走って `Fable` を消すため、不在を条件にした検出は無効になる。フェンスの閉じ漏れ自体を selftest で検出する方式にした。

### `trial-log` skill へのブロック埋め込み
- 棄却理由: ブロックは agents 向けの文言で、skill の文脈と一致しない。agents と `trial-log-reviewer` にのみ埋め込んだ。
