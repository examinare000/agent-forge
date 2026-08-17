# ADR-004: 既知の安全な rm -rf を PreToolUse hook で自動承認する

- ステータス: 採用済み
- 日付: 2026-08-17
- 最終更新日: 2026-08-17

## 背景

`rm -rf` に対する broad な ask/deny 権限ルールは、`rm -rf node_modules` のようなビルドキャッシュ削除まで毎回止めてしまい、エージェントの自走を阻害する。一方で無条件の allow は危険な削除（`rm -rf /`・`rm -rf ~`・親ディレクトリ参照等）まで自動承認してしまう。「既知のビルド生成物・自セッション scratchpad の削除だけを自動承認し、それ以外は従来の確認・遮断フローに委ねる」設計が必要だった。

本設計は姉妹の private リポジトリ（personalized-claude）で先行実装され、adversarial-verifier による反証検証6ラウンド（REJECT 5回 → ACCEPT）を経て確定したものを agent-forge へ移植した。

## 決定

`hooks/approve-safe-rm.sh`（PreToolUse/Bash）を追加する。以下の不変条件を移植元から維持する。

- **出力は allow か無出力の2値のみ**: `permissionDecision:"allow"` の JSON か、空 stdout のいずれかしか返さない。ask・deny・exit 2・非 0 終了を決して出さない。PreToolUse hook の結果統合は並列実行 + last-writer-wins で、exit-2 の blockingError も同じイベント型に統合されるため、本 hook が ask/deny/非 0 終了を出すと同一コマンドを見た他 hook（ブランチ保護等）の deny 判定を降格させうる。「allow 以外を出さない」ことでこの衝突クラスを構造的に排除する。素通し（無出力）は保護を追加も除去もしない中立動作であり、判定に迷う入力は常に素通しに倒す。
- **ターゲット安全性判定は文字ホワイトリスト方式**（英数字・`.`・`_`・`/`・`-` のみ許可）であり、禁止文字を列挙するブラックリスト方式は採らない。移植元の検証過程でブラックリスト方式がブレース展開 `{..,x}/node_modules` の列挙漏れによる実測バイパスを許した経緯があり、その教訓を反映した設計として固定する。
- ターゲットは (a) 一時領域: `/tmp/claude-*` または `/private/tmp/claude-*` で始まる**絶対綴り**かつ `scratchpad` という完全なパスセグメントを含み `..` セグメントを含まないもの、(b) それ以外: `..` セグメント・絶対パス・語頭 `-` を含まず、末尾 `/` を除去した basename が固定 whitelist（node_modules・dist・build・target・out・coverage 等のビルド生成物ディレクトリ）に完全一致するもの、のいずれかのみを安全とする。
- 変数展開（`$TMPDIR` 等）・コマンド置換・glob・チルダ展開など、hook がリテラルとして検証できない入力は allow の根拠にしない。

## 検討した選択肢

移植元（personalized-claude）で検討済みの選択肢の記録は本リポジトリの範囲外のため割愛する。agent-forge 側での選択肢は「そのまま移植する」の一択であり、移植先固有の JSON 抽出は本リポジトリの共通 lib（`hooks/lib/json.sh`）に合わせて書き換えた（ロジック自体は変更していない）。

## 結果

- `claude/settings.base.json` に本リポジトリ初の `PreToolUse` エントリ（matcher: `Bash`）を追加した。
- `hooks/approve-safe-rm.test.sh` にスモークテストを同梱し、allow/passthrough 双方の境界ケース（ブレース展開・変数展開・複合コマンド・許可外フラグ等）を固定した。
- rm 全般に対する新たな ask/deny 権限ルールの追加は本 ADR の範囲外（`claude/settings.base.json` に `permissions` ブロックは追加していない）。
