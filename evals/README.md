# evals/ — エージェント/スキルのゴールデンタスク回帰基盤

エージェント定義（本repoでは `agents/*.md`。インストール後は
`~/.claude/agents/*.md` に相当）とスキルはプロンプト資産であり、モデル更新や
定義変更で挙動が静かに変わりうる。ここには、数本のゴールデンタスクを実際の
`claude` CLI で手動実行し、決定的アサートだけで退行を検出する最小基盤を置く。

**LLM判定（LLM-as-judge）は使わない。** エージェントの出力を別のLLMに
「これは合格か」と自己採点させる方式は、退行検知の土台として弱く、
実行のたびに結果がぶれうる。判定はすべて exit code・git状態・
文字列一致/grep といった決定的な検査だけで行う。

## 【手動実行専用・CI/cron組み込み禁止】

`evals/run-evals.sh` は実際に `claude` CLI を複数回（opus系エージェントを
含む）呼び出す。1回の実行で数万トークン規模のAPI利用が発生するため、
CIやcronに自動組み込みしないこと。実行タイミングの目安:

- モデル更新時（例: デフォルトモデルのバージョンアップ）
- エージェント定義変更時（`agents/*.md` の編集後）
- 委譲強制フック等、エージェントの挙動に影響するフック変更時
  （例: `hooks/delegate-git-to-composer.sh`）

## 実行方法

```sh
bash evals/run-evals.sh --yes
```

`--yes` を省略すると、実行前にコスト確認プロンプトで停止する
（`ASSUME_YES=true` 環境変数でも代替可）。`--yes` フラグと `ASSUME_YES` 環境変数は、
evals/run-evals.sh 内の `confirm()` 関数で同じ規約に従う。
実行するとまず能力プローブ
（`claude --agent git-composer -p '準備確認。OKとだけ返せ' --output-format json`
の exit code）を行い、失敗する環境（`--agent` がuser-scopeエージェントを
解決できない環境）ではその時点でタスクを一切実行せず終了する。

`$HOME` は差し替えない。実環境の user-scope エージェント定義をそのまま
使うのが目的だから。フィクスチャは `mktemp -d` + `trap rm -rf` で隔離し、
実リポジトリ・`~/.claude` を書き換えることはない（フィクスチャの外に
影響する操作をタスクに書かないこと）。

## AGENT_CLI: 実行CLIの差し替え（実験的）

`evals/run-evals.sh` は実行するCLIをハードコードせず、環境変数 `AGENT_CLI`
（既定: `claude`）経由で間接化している。`run-evals.sh` は起動時の前提チェック
（`command -v "$AGENT_CLI"`）・能力プローブ・`AGENT_CLI` のタスクへの
エクスポートをすべてこの変数越しに行い、`evals/tasks/*.task.sh` 側も
`"${AGENT_CLI:-claude}"` で参照する（タスク単体実行時にも動くようフォールバック
付き）。

```sh
AGENT_CLI=my-other-cli bash evals/run-evals.sh --yes
```

**v1では `claude` 以外のCLIでの動作は保証しない。** 将来Codex/Gemini CLI等へ
差し替えられるようにするための土台であり、現時点では `--agent` によるuser-scope
エージェント解決・`--permission-mode acceptEdits`・`--output-format json` 等の
オプション体系が `claude` CLI前提のままである（差し替え先CLIが同じ引数体系を
持つ保証はない）。

## タスクを追加する契約

`evals/tasks/*.task.sh` を1本追加する。1ファイル = 1タスク。ファイルは
`run-evals.sh` から `source` され、以下の関数を定義することが契約:

```sh
run_task() {
  # フィクスチャの作成、claude呼び出し、決定的アサートをすべてここで行う。
  # 0 = PASS
  # 1 = FAIL
  # 2 = SKIP（理由を事前にstdoutへ出力すること）
  return 0
}
```

- **判定は決定的アサートのみ**（exit code / git状態 / 文字列一致・grep）。
  LLM判定は禁止。
- `run_task` は `run-evals.sh` によってサブシェルで呼ばれるため、
  `trap ... EXIT` はそのタスク専用のサブシェルにのみ効き、他タスクや
  `run-evals.sh` 本体には波及しない。`mktemp -d` + `trap rm -rf EXIT` で
  各タスクが自分のフィクスチャの後始末に責任を持つこと
  （installer/install.test.sh と同じ隔離様式）。
- 実行環境が前提を満たさない場合（例: 依存するフックの想定バージョンが
  live環境にまだ配備されていない）は `FAIL` ではなく `SKIP`（返り値2）を
  使い、理由をstdoutに出力すること。

## 既知の罠: 全角記号の変数展開直後隣接（bash 3.2 + ja_JP.UTF-8）

`"...（exit=$var）..."` のように、変数展開の直後に全角記号（`）`など）が
空白なしで隣接すると、macOS標準の `/bin/bash`（3.2系）+ `ja_JP.UTF-8`
ロケール環境下で、その全角記号の一部バイトが変数名の続きとして誤認識され
`unbound variable` エラーになることがある（`set -u` 環境で実際に再現・
発見済み）。必ず `${var}` のように波括弧で明示的に囲むこと。

## タスク一覧

| ファイル | 検証対象 |
|---|---|
| `tasks/git-composer-atomic-split.task.sh` | git-composerがテスト/実装/docs混在の未コミット変更をアトミック分割コミットできるか |
| `tasks/adversarial-verifier-refute.task.sh` | adversarial-verifierが「importなしのassert Trueのみで完了宣言」という明確な欠陥を見抜けるか |
| `tasks/coder-commit-handoff.task.sh` | tdd-strict-coderが（git委譲強制フックにより）自分でコミットせずgit-composerへの委譲を報告するか |

## セルフテスト

`evals/harness-selftest.sh` は `run-evals.sh` 本体の制御フロー
（確認プロンプト・能力プローブ失敗時のスキップ・タスクループの集計・
サマリ出力）を、`claude` コマンドをPATHスタブに差し替えて実claude呼び出し
なしで検証する。`evals/tasks/*.task.sh` の内容そのものの正しさ（実際に
git-composerが正しく分割コミットするか等）はこのセルフテストの対象外で、
実claude呼び出しを伴うため別途手動実行で確認する。

```sh
bash evals/harness-selftest.sh
```
