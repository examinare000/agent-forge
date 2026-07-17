#!/usr/bin/env bash
# evals/run-evals.sh — エージェント定義（agents/*.md。インストール後は
# ~/.claude/agents/*.md に相当）とスキルのゴールデンタスク回帰ハーネス。
#
# 【手動実行専用・CI/cron組み込み禁止】
# モデル更新時・エージェント定義変更時・フック変更時に手動で叩く。
# 1回の実行で実claude CLIを複数回（opus系エージェントを含む）呼び出すため、
# 1回あたり数万トークン規模のAPI利用が発生する。CIやcronに組み込むとコストが
# 静かに積み上がるため、意図的に自動実行経路を用意していない。
#
# 判定方式について:
# ここでのPASS/FAILはすべて決定的アサート（exit code・git状態・文字列一致/grep）
# のみで行う。LLMによる自己採点・LLM-as-judgeは使わない
# （エージェント自身の出力を別のLLMに「合格か」聞く方式は、退行検知の土台として
# 弱く再現性がないため採用しない）。
#
# 実行方法: bash evals/run-evals.sh --yes
# （--yes省略時は確認プロンプトで停止する。ASSUME_YES=true環境変数でも代替可）。
#
# タスクの追加方法: evals/tasks/*.task.sh を追加する。1ファイル1タスク。
# ファイルはこのスクリプトからsourceされ、run_task という引数なし関数を
# 定義することが契約。run_task の返り値:
#   0 = PASS / 1 = FAIL / 2 = SKIP（理由は事前にstdoutへ出力すること）
# 判定は決定的アサートのみ（LLM判定禁止）。各タスクは自分のフィクスチャの
# 作成・後始末に責任を持つ（mktemp -d + trap rm -rf EXIT）。このスクリプトは
# 各タスクをサブシェルで実行するため、タスク内のtrapはそのタスク専用の
# サブシェルにのみ効き、他タスクや本スクリプト自身には波及しない。
# 詳細はevals/README.mdを参照。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# テスト容易性のためのシーム: 既定はevals/tasks/。evals/harness-selftest.shは
# ここを一時ディレクトリの合成ダミータスクに差し替えて、ハーネス自体の制御フロー
# （プローブ失敗時スキップ・タスクloop集計・サマリ）を実claude呼び出しなしで検証する。
# 本番実行（--yes運用）では常に既定値が使われるため、この変数の存在は挙動に影響しない。
TASKS_DIR="${EVAL_TASKS_DIR:-"$SCRIPT_DIR/tasks"}"

# 実行CLIの間接化シーム: 既定はclaude。将来Codex/Gemini CLI等へ差し替え可能に
# するため、呼び出しは常にハードコードの`claude`ではなく$AGENT_CLI経由にする。
# v1ではclaude以外での動作は保証しない（実験的差し替え、README.md参照）。
# タスク（evals/tasks/*.task.sh）側からも参照できるようexportする。
AGENT_CLI="${AGENT_CLI:-claude}"
export AGENT_CLI

if ! command -v "$AGENT_CLI" >/dev/null 2>&1; then
  echo "エラー: ${AGENT_CLI} コマンドがPATH上に見つかりません。" >&2
  exit 1
fi

# --- 確認プロンプト -------
ASSUME_YES="${ASSUME_YES:-false}"
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
  esac
done

confirm() {
  local prompt="$1"
  if [ "$ASSUME_YES" = "true" ]; then
    return 0
  fi
  local reply=""
  read -r -p "$prompt [y/N]: " reply || true
  case "$reply" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

if ! confirm "本ハーネスは実際に${AGENT_CLI}を複数回呼び出し、opus系エージェントを含め1回あたり数万トークン規模のAPI利用が発生します。続行しますか？"; then
  echo "中止しました（確認プロンプトでキャンセル、または--yes未指定）。" >&2
  exit 1
fi

# --- 能力プローブ: --agent がuser-scopeエージェントを解決できる環境かを確認 ---
# --json-schemaは使わない（判定は出力テキストとgit状態の決定的検査で行うため
# プローブする必要がない）。判定はexit codeのみで行い、出力内容の妥当性は見ない。
echo "=== 能力プローブ: ${AGENT_CLI} --agent git-composer の解決確認 ==="
probe_output="$("$AGENT_CLI" --agent git-composer -p '準備確認。OKとだけ返せ' --output-format json 2>&1)"
probe_rc=$?
if [ "$probe_rc" -ne 0 ]; then
  echo "$probe_output"
  # 注意: 全角記号（）が変数展開に直接隣接すると、bash 3.2 + ja_JP.UTF-8ロケール下で
  # 変数名の一部として誤認識され"unbound variable"になる既知の罠がある
  # （$var）ではなく必ず${var}で囲むこと。evals/README.mdにも記載）。
  echo "能力プローブ失敗（exit=${probe_rc}）: --agent がuser-scopeエージェントを解決できない環境の可能性があります。以降のタスクは実行せずスキップします。" >&2
  exit 1
fi
echo "能力プローブ: OK"

# --- タスクループ -----------------------------------------------------------
# 空配列 "${arr[@]}" 展開はbash 3.2のset -uでunbound variableになる
# （bootstrap.test.shで確立済みの既知の罠）。事前にlengthを見てからでないと
# forループ自体が空配列展開を発生させてクラッシュするため、要素数チェックで
# 空配列時のfor文実行そのものを回避する。
shopt -s nullglob
task_files=("$TASKS_DIR"/*.task.sh)
shopt -u nullglob

pass=0
fail=0
skip=0

if [ "${#task_files[@]}" -eq 0 ]; then
  echo "警告: $TASKS_DIR に *.task.sh が見つかりません。" >&2
else
  for task_file in "${task_files[@]}"; do
    task_name="$(basename "$task_file" .task.sh)"
    echo ""
    echo "=== タスク: $task_name ==="
    (
      source "$task_file"
      run_task
    )
    rc=$?
    case "$rc" in
      0)
        echo "PASS: $task_name"
        pass=$((pass + 1))
        ;;
      2)
        echo "SKIP: $task_name"
        skip=$((skip + 1))
        ;;
      *)
        echo "FAIL: $task_name (exit=$rc)"
        fail=$((fail + 1))
        ;;
    esac
  done
fi

echo ""
echo "----"
echo "pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
