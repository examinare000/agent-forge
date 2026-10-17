# ADR-005: rules の再同期（provider 中立化）とエージェントのティア方針

- ステータス: 採用済み
- 日付: 2026-10-17
- 最終更新日: 2026-10-17

## 背景

姉妹の private リポジトリで 2026-09〜10 に運用実証された rules・エージェント定義の現行形へ、agent-forge を再同期する。主な差分は (1) Claude 固有ルール群 `rules/hosts/claude/` の存在、(2) 論理ロールとエージェントの対応の置き場、(3) 参照資料の置き場、(4) エージェントのモデル・effort・ターン予算の方針である。

## 決定

### (a) `rules/hosts/claude/` を解消する
rules は provider 中立とし、Claude 固有の動作制約は `claude/CLAUDE.core.md`「動作制約」節を正本とする。`hosts/claude/{01,02,91,92}` は廃止し、ティア表とエージェントのモデルピンは `rules/02`、品質ゲートと plan mode は中立の `91` / `92` に一本化した。

### (b) 論理ロール対応表は `rules/95` に置く
README は dist から除外され、また置換による誤変換を受けうるため、対応表の置き場に向かない。生成物にも載る `95-orchestration-protocol.md` を正本とする。

### (c) `reference/` は `rules/` の外に置く
`~/.claude/rules/` は再帰的かつ無条件にロードされるため、常時ロードしたくない参照資料を置くと文脈を恒常的に消費する。参照資料は `~/.claude/reference/` に置き、必要時のみ読む。

### (d) エージェントのティア方針
ティアは「運用上の許可範囲」（どの役割を担えるか。`rules/02`）であり、能力順位でも effort の指定でもない。effort はロール別の下限として frontmatter で課す。

- 検証役（`adversarial-verifier`）を opus / high、`code-reviewer` を sonnet / high とする（従来は xhigh）。
- `implementation-coder` を sonnet / medium とする（従来は haiku / low）。仕様固定の実装でも適用判断が入るため、判断を要する作業は sonnet 以上が担う。haiku は単一ソースの決定的な変換・実行報告に限る。
- `memory: user` を外す。エージェントが個別に永続メモリを持つ構成をやめ、観察はオーケストレーターへ返して一元的に扱う。
- `maxTurns` でターン予算を明示する（12〜25）。

8 エージェントの変更（model / effort / maxTurns。旧は全員 `memory: user`・maxTurns なし）:

| エージェント | 旧 | 新 |
|---|---|---|
| adversarial-verifier | opus / xhigh | opus / high / 20 |
| ai-antipattern-reviewer | sonnet / high | sonnet / high / 20 |
| code-reviewer | sonnet / xhigh | sonnet / high / 20 |
| git-composer | sonnet / medium | sonnet / medium / 25 |
| implementation-coder | haiku / low | sonnet / medium / 20 |
| tdd-strict-coder | sonnet / high | sonnet / high / 20 |
| test-runner | haiku / low | haiku / low / 12 |
| testability-architect | opus / xhigh | opus / high / 20 |

新: `memory` は全員削除。

### (e) 00（憲法）の文言変更
- 原則 3 は姉妹リポジトリの TDD 版にせず、forge 旧来の「検証をもって完了とする」に据え置く。TDD は採用者が 10〜29 番帯に置く個人嗜好として、forge の核に含めない方針と整合させるため。
- 原則 1 は姉妹リポジトリの「ロールバックしてよい（fix-forward 可）」に追従する。
- 優先度行の「変更禁止」を「改訂はユーザー承認と PR 経由」に改める。

### (f) 94 の教訓保存
教訓の保存先を `~/.claude/lessons/inbox/` とし、昇格の自動適用は採用者の明示許可がある場合に限る。

### ADR-003 との関係
ADR-003（クロスベンダー最上位ティアを Tier A 同格の判断役として扱う）は変更しない。検証者の独立性（read-only・名指しゲート）と検証役の Tier A ピンは維持する。変わるのは、検証役に暗黙に求めていた「最大 effort」を「Tier A + ロール別 effort 下限（high）」の要件に置き換える点のみである。

## 理由

effort を最大にしても検証の独立性や反証の質は比例して上がらず、ターンとコストを恒常的に消費する。独立性（別コンテキスト・read-only）と Tier A ピンが品質担保の核であり、effort は下限で足りることが運用で確認された。

## 結果

- `rules/02` のピン表に effort と maxTurns の列を追加し、`implementation-coder` を Tier B へ更新した。
- `agents/*.md` の frontmatter は本 PR で本方針に合わせて適用済み。
- 出所は姉妹の private リポジトリでの 2026-09〜10 の運用実証であり、本リポジトリ固有の再実測は未実施。
