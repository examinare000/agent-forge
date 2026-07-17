#!/bin/bash
# evals/run-evals.sh のハーネス自体（実claude呼び出しロジックを除いた制御フロー）を
# 検証するセルフテスト。
#
# なぜ実claudeを呼ばないのか:
# run-evals.sh本体は実行するたびに数万トークン規模の課金が発生する意図的
# 手動専用ツールであり、CI等での自動実行を想定していない。そのためこの
# セルフテストは「claude」コマンドをPATHスタブに差し替え、
#   1) 確認プロンプトがclaude呼び出し前に安全に停止すること
#   2) 能力プローブが失敗した場合にタスクループへ進まずスキップすること
#   3) タスクループがrun_taskの返り値(0=PASS/1=FAIL/2=SKIP)を正しく集計し
#      サマリを出力すること
# という「ハーネスの制御フロー」だけを、コストゼロ・決定的に検証する。
# evals/tasks/配下の実タスク3本（git-composer/adversarial-verifier/coder-handoff）
# の内容そのものの正しさは、実claude呼び出しを伴うためこのセルフテストの対象外
# （マージ後にオーケストレータがユーザー同席で実行する）。
#
# なぜ本物のevals/tasks/を使わず合成ダミータスクを使うのか:
# ハーネスの集計・分岐ロジックは本来タスクの中身と無関係に成立すべき性質
# （run_taskの返り値だけに依存する）なので、実タスクの複雑な内部実装から
# 切り離して検証するほうが依存が薄く壊れにくいテストになる。run-evals.sh側に
# EVAL_TASKS_DIR環境変数でタスクディレクトリを差し替えるテスト容易性シームを
# 用意した（installer/install.test.sh の fixtureディレクトリ手法と同じシーム設計。
# 本番実行時は既定のevals/tasks/がそのまま使われるので挙動に影響しない）。
#
# なぜ bats 等の外部フレームワークを使わないのか:
# installer/install.test.sh と同じ理由で、exit codeと出力文字列の一致だけで
# 十分検証できるこの規模のテストに新規依存を増やすのはスコープ過剰。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUN_EVALS="$SCRIPT_DIR/run-evals.sh"

pass=0
fail=0

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# $1: label, $2: expected exit code, $3: actual exit code
assert_rc() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected actual=$actual)"
    fail=$((fail + 1))
  fi
}

# $1: label, $2: output全体, $3: 含まれるべき文字列
assert_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (needle not found: $needle)"
    echo "  --- output ---"
    printf '%s\n' "$output" | sed 's/^/  /'
    echo "  --------------"
    fail=$((fail + 1))
  fi
}

# $1: label, $2: 存在してはいけないパス
assert_absent() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then
    echo "FAIL: $label (存在してはいけないファイルが存在: $path)"
    fail=$((fail + 1))
  else
    echo "PASS: $label"
    pass=$((pass + 1))
  fi
}

# 指定した名前のCLIスタブをPATH上に作る。呼ばれるたびにsentinelファイルに
# touchしてからexit_codeで終了する（＝sentinelの有無で「実際に呼ばれたか」を
# 判定できる）。
# $1: スタブを置くbinディレクトリ, $2: コマンド名, $3: exit code, $4: sentinelファイルパス
build_stub_cli() {
  local bindir="$1" name="$2" exit_code="$3" sentinel="$4"
  mkdir -p "$bindir"
  cat > "$bindir/$name" <<EOF
#!/bin/bash
touch "$sentinel"
exit $exit_code
EOF
  chmod +x "$bindir/$name"
}

# claudeという名前でのCLIスタブ作成（既存シナリオ向けの薄いラッパー）。
# $1: スタブを置くbinディレクトリ, $2: exit code, $3: sentinelファイルパス
build_stub_claude() {
  build_stub_cli "$1" "claude" "$2" "$3"
}

# run_taskがrcを返すだけの合成ダミータスクを書く。
# $1: タスクディレクトリ, $2: タスク名(拡張子なし), $3: run_taskの返り値
write_dummy_task() {
  local dir="$1" name="$2" rc="$3"
  mkdir -p "$dir"
  cat > "$dir/$name.task.sh" <<EOF
run_task() {
  echo "dummy task $name executed"
  return $rc
}
EOF
}

# run_taskが実行されたことをsentinelファイルで記録する合成ダミータスクを書く
# （「タスクループへ進まなかったこと」を検証するのに使う）。
# $1: タスクディレクトリ, $2: タスク名(拡張子なし), $3: sentinelファイルパス
write_sentinel_task() {
  local dir="$1" name="$2" sentinel="$3"
  mkdir -p "$dir"
  cat > "$dir/$name.task.sh" <<EOF
run_task() {
  touch "$sentinel"
  return 0
}
EOF
}

# run_task内で見えるAGENT_CLI環境変数の値をcapture_fileへ書き出すだけの合成
# ダミータスクを書く（「run-evals.shがAGENT_CLIをタスクへエクスポートしているか」
# を実claude呼び出しなしで検証するのに使う）。
# $1: タスクディレクトリ, $2: タスク名(拡張子なし), $3: capture先ファイルパス
write_agent_cli_capture_task() {
  local dir="$1" name="$2" capture_file="$3"
  mkdir -p "$dir"
  cat > "$dir/$name.task.sh" <<EOF
run_task() {
  echo "AGENT_CLI=\${AGENT_CLI:-unset}" > "$capture_file"
  return 0
}
EOF
}

echo "=== シナリオD: 確認プロンプトがclaude呼び出し前に安全に停止する（--yesなし・自動入力n） ==="
claude_called_d="$WORKDIR/d-claude-called"
stub_bin_d="$WORKDIR/bin-d"
build_stub_claude "$stub_bin_d" 0 "$claude_called_d"

rc=0
out="$(printf 'n\n' | PATH="$stub_bin_d:$PATH" bash "$RUN_EVALS" 2>&1)" || rc=$?
assert_rc "確認プロンプトでn入力時はexit 1" 1 "$rc"
assert_absent "確認プロンプト段階ではclaudeが一度も呼ばれない" "$claude_called_d"

echo ""
echo "=== シナリオA: 能力プローブ失敗時はタスクループへ進まずスキップする ==="
task_executed_a="$WORKDIR/a-task-executed"
stub_bin_a="$WORKDIR/bin-a"
build_stub_claude "$stub_bin_a" 1 "$WORKDIR/a-claude-called"
tasks_a="$WORKDIR/tasks-a"
write_sentinel_task "$tasks_a" "would-run" "$task_executed_a"

rc=0
out="$(PATH="$stub_bin_a:$PATH" EVAL_TASKS_DIR="$tasks_a" bash "$RUN_EVALS" --yes 2>&1)" || rc=$?
assert_rc "能力プローブ失敗時はexit 1" 1 "$rc"
assert_absent "能力プローブ失敗時はタスクのrun_taskが実行されない" "$task_executed_a"
assert_contains "能力プローブ失敗の理由が出力される" "$out" "能力プローブ失敗"

echo ""
echo "=== シナリオB: タスクループがPASS/FAIL/SKIPを正しく集計しサマリを出す ==="
stub_bin_b="$WORKDIR/bin-b"
build_stub_claude "$stub_bin_b" 0 "$WORKDIR/b-claude-called"
tasks_b="$WORKDIR/tasks-b"
write_dummy_task "$tasks_b" "t1-pass" 0
write_dummy_task "$tasks_b" "t2-fail" 1
write_dummy_task "$tasks_b" "t3-skip" 2

rc=0
out="$(PATH="$stub_bin_b:$PATH" EVAL_TASKS_DIR="$tasks_b" bash "$RUN_EVALS" --yes 2>&1)" || rc=$?
assert_rc "FAILが1件でもあればexitは非0" 1 "$rc"
assert_contains "サマリにpass=1 fail=1 skip=1が出る" "$out" "pass=1 fail=1 skip=1"
assert_contains "PASS行にタスク名が出る" "$out" "PASS: t1-pass"
assert_contains "FAIL行にタスク名が出る" "$out" "FAIL: t2-fail"
assert_contains "SKIP行にタスク名が出る" "$out" "SKIP: t3-skip"

echo ""
echo "=== シナリオC: 全タスクPASSならexit 0でサマリも一致する ==="
stub_bin_c="$WORKDIR/bin-c"
build_stub_claude "$stub_bin_c" 0 "$WORKDIR/c-claude-called"
tasks_c="$WORKDIR/tasks-c"
write_dummy_task "$tasks_c" "t1-pass" 0
write_dummy_task "$tasks_c" "t2-pass" 0

rc=0
out="$(PATH="$stub_bin_c:$PATH" EVAL_TASKS_DIR="$tasks_c" bash "$RUN_EVALS" --yes 2>&1)" || rc=$?
assert_rc "全PASS時はexit 0" 0 "$rc"
assert_contains "サマリにpass=2 fail=0 skip=0が出る" "$out" "pass=2 fail=0 skip=0"

echo ""
echo "=== シナリオE: AGENT_CLIで実行CLIを偽スタブに差し替えられる（indirection確認） ==="
# 実PATH上の本物のclaude等を誤って呼んでしまう余地をなくすため、PAT
# は最小限（/usr/bin:/bin）+スタブbinのみに絞る。スタブ名はclaudeではなく
# 別名にし、「AGENT_CLIで指定した名前がハードコードのclaudeではなく実際に
# 使われているか」を区別できるようにする。
sentinel_e="$WORKDIR/e-fake-cli-called"
stub_bin_e="$WORKDIR/bin-e"
build_stub_cli "$stub_bin_e" "fake-agent-cli" 0 "$sentinel_e"
tasks_e="$WORKDIR/tasks-e"
capture_e="$WORKDIR/e-agent-cli-capture"
write_agent_cli_capture_task "$tasks_e" "capture" "$capture_e"

rc=0
out="$(PATH="$stub_bin_e:/usr/bin:/bin" AGENT_CLI="fake-agent-cli" EVAL_TASKS_DIR="$tasks_e" bash "$RUN_EVALS" --yes 2>&1)" || rc=$?
assert_rc "AGENT_CLI差し替え時もタスクがPASSしexit 0" 0 "$rc"
if [ -e "$sentinel_e" ]; then
  echo "PASS: 能力プローブがAGENT_CLI(fake-agent-cli)を実際に呼び出している"
  pass=$((pass + 1))
else
  echo "FAIL: 能力プローブがAGENT_CLI(fake-agent-cli)を呼び出していない（ハードコードのclaudeのままの可能性）"
  fail=$((fail + 1))
fi
assert_contains "タスクへAGENT_CLIが環境変数としてエクスポートされている" "$(cat "$capture_e" 2>/dev/null || echo "capture_file_missing")" "AGENT_CLI=fake-agent-cli"

echo ""
echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
