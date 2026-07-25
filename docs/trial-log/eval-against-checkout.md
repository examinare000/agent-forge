# trial-log: checkout 中の agents/ を evals で検証する方法

範囲: `~/.claude/agents` が別リポジトリ（personalized-claude 等）を指す環境で、evals/run-evals.sh に「この checkout の agents/*.md」を検証させる方法。eval タスクの中身は扱わない。

関連: ブランチ `feature/token-efficiency`

## 目的
エージェント定義を編集したブランチの挙動退行を、ユーザーの実環境 symlink を差し替えずに evals で検証する。

## 現在地
AGENT_CLI シームにラッパースクリプトを渡す方式で確立（3/3 PASS）。ラッパーは fixture（cwd）に `.claude/agents/` として checkout の agents/*.md を複製し、`.git/info/exclude` に `.claude/` を追記してから `exec claude "$@"` する。プロジェクトレベル agents がユーザーレベルより優先されることを利用する。

## 棄却した案

### ~/.claude/agents の symlink を一時的に差し替える案
- 棄却理由（観測）: 実行中の他セッション（このオーケストレータ自身を含む）のサブエージェント解決に影響する。並行作業中の差し替えはレースを生む。

### ラッパーで複製だけして git exclude しない案（初回実装）
- 棄却理由（観測）: 注入した `.claude/agents/` 8 ファイルが fixture の未追跡変更として eval の対象に混ざり、git-composer-atomic-split が「無関係な 2 目的の変更」と正しく判断して別ブランチへ分割 → コミット数アサート（HEAD 上 4 件以上）が崩れて偽 FAIL。エージェントの挙動は正しく、eval フィクスチャの汚染が原因。`.git/info/exclude` への追記で解消。
