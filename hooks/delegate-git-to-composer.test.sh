#!/usr/bin/env bash
# delegate-git-to-composer.sh のスモークテスト。
#
# なぜ bats 等の外部フレームワークを使わないのか:
# この1ファイルのためだけに新規依存を増やすのはスコープ過剰。exit code の
# 一致だけを見れば十分検証できるため、素の bash + assert 関数で完結させる。
#
# フックは stdin JSON の .agent_type と .tool_input.command のみ読む実装なので、
# HOME 偽装や実ファイル配置は不要。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/delegate-git-to-composer.sh"

pass=0
fail=0

# $1: label, $2: expected exit code, $3: json stdin
assert_exit() {
  local label="$1" expected="$2" json="$3"
  local actual
  bash "$HOOK" <<<"$json" >/tmp/delegate-git-test-stdout.$$ 2>/tmp/delegate-git-test-stderr.$$
  actual=$?
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected=$expected actual=$actual)"
    echo "  stdout: $(cat /tmp/delegate-git-test-stdout.$$)"
    echo "  stderr: $(cat /tmp/delegate-git-test-stderr.$$)"
    fail=$((fail + 1))
  fi
  rm -f /tmp/delegate-git-test-stdout.$$ /tmp/delegate-git-test-stderr.$$
}

# --- 許可されるべき (exit 0) ---

assert_exit "format-patch は常に許可（パッチファイル出力のみ）" \
  0 '{"agent_type":"","tool_input":{"command":"git format-patch -1"}}'

assert_exit "request-pull は常に許可（stdout 出力のみ）" \
  0 '{"agent_type":"","tool_input":{"command":"git request-pull v1.0 origin master"}}'

assert_exit "apply は常に許可（Edit/patch と等価）" \
  0 '{"agent_type":"","tool_input":{"command":"git apply foo.patch"}}'

assert_exit "apply --check は常に許可" \
  0 '{"agent_type":"","tool_input":{"command":"git apply --check foo.patch"}}'

assert_exit "stash（引数なし=push）は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git stash"}}'

assert_exit "stash push は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git stash push -m wip"}}'

assert_exit "stash pop は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git stash pop"}}'

assert_exit "stash apply は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git stash apply stash@{1}"}}'

assert_exit "stash list は許可（回帰）" \
  0 '{"agent_type":"","tool_input":{"command":"git stash list"}}'

assert_exit "merge --abort は許可（進行中操作の復旧）" \
  0 '{"agent_type":"","tool_input":{"command":"git merge --abort"}}'

assert_exit "rebase --abort は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git rebase --abort"}}'

assert_exit "cherry-pick --abort は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git cherry-pick --abort"}}'

assert_exit "am --abort は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git am --abort"}}'

assert_exit "restore --staged は許可（unstage のみ）" \
  0 '{"agent_type":"","tool_input":{"command":"git restore --staged foo.txt"}}'

assert_exit "restore --staged 複数ファイルは許可" \
  0 '{"agent_type":"","tool_input":{"command":"git restore --staged src/a.c src/b.c"}}'

assert_exit "pull --ff-only は許可（マージコミット判断なし）" \
  0 '{"agent_type":"","tool_input":{"command":"git pull --ff-only"}}'

assert_exit "pull origin main --ff-only は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git pull origin main --ff-only"}}'

assert_exit "status は読み取り専用で許可" \
  0 '{"agent_type":"","tool_input":{"command":"git status"}}'

assert_exit "diff は読み取り専用で許可" \
  0 '{"agent_type":"","tool_input":{"command":"git diff HEAD"}}'

assert_exit "switch -c はブランチ作成のみで許可" \
  0 '{"agent_type":"","tool_input":{"command":"git switch -c feature/x"}}'

assert_exit "checkout -b はブランチ作成のみで許可" \
  0 '{"agent_type":"","tool_input":{"command":"git checkout -b feature/y"}}'

assert_exit "gh pr view は読み取り専用で許可" \
  0 '{"agent_type":"","tool_input":{"command":"gh pr view 12"}}'

assert_exit "空 stdin は fail-open で許可" \
  0 ''

assert_exit "agent_type=git-composer はサブエージェント免除で許可" \
  0 '{"agent_type":"git-composer","tool_input":{"command":"git commit -m x"}}'

assert_exit "agent_type=git-composer + push もサブエージェント免除で許可" \
  0 '{"agent_type":"git-composer","tool_input":{"command":"git push origin feature/x"}}'

assert_exit "agent_type=code-reviewer + status は読み取りとして全サブエージェント許可のまま" \
  0 '{"agent_type":"code-reviewer","tool_input":{"command":"git status"}}'

assert_exit "agent_type=antigravity-delegate + apply は許可カテゴリとして全サブエージェント許可のまま" \
  0 '{"agent_type":"antigravity-delegate","tool_input":{"command":"git apply foo.patch"}}'

# --- ブロックされるべき (exit 2) ---

assert_exit "stash drop はブロック（非可逆破棄）" \
  2 '{"agent_type":"","tool_input":{"command":"git stash drop"}}'

assert_exit "stash drop stash@{0} はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git stash drop stash@{0}"}}'

assert_exit "stash clear はブロック（非可逆破棄）" \
  2 '{"agent_type":"","tool_input":{"command":"git stash clear"}}'

assert_exit "merge（--abort なし）はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git merge feature/x"}}'

assert_exit "rebase（--abort なし）はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git rebase main"}}'

assert_exit "rebase --continue はコミット生成し得るためブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git rebase --continue"}}'

assert_exit "cherry-pick（--abort なし）はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git cherry-pick abc1234"}}'

assert_exit "am（--abort なし）はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git am series.mbox"}}'

assert_exit "restore（--staged なし）は作業ツリー復元でブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git restore foo.txt"}}'

assert_exit "restore --staged --worktree は作業ツリーも含むためブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git restore --staged --worktree foo.txt"}}'

assert_exit "restore -S -W は結合短フラグでもブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git restore -S -W foo.txt"}}'

assert_exit "plain pull はマージコミット判断が発生し得るためブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git pull"}}'

assert_exit "pull --rebase はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git pull --rebase"}}'

assert_exit "commit はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git commit -m x"}}'

assert_exit "push はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git push"}}'

assert_exit "add はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git add foo.txt"}}'

assert_exit "reset --hard はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git reset --hard HEAD~1"}}'

assert_exit "checkout -- <path> は作業ツリー復元でブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git checkout -- path/file"}}'

assert_exit "branch -d はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git branch -d old"}}'

assert_exit "gh pr create はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"gh pr create --title x"}}'

assert_exit "複合コマンド（; 区切り）の後半でブロック検出" \
  2 '{"agent_type":"","tool_input":{"command":"git status && git stash drop"}}'

assert_exit "-C グローバルオプション越しでも stash drop はブロック" \
  2 '{"agent_type":"","tool_input":{"command":"git -C /some/repo stash drop"}}'

# --- レビュー指摘の追加ケース（fail-open 穴の再発防止） ---

# json_escape: コミットメッセージ内にダブルクォートを含むコマンド文字列を
# 手組みエスケープせず JSON に安全に埋め込むため、エンコードを python3 の
# json.dumps に委譲する。
json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

merge_quoted_abort_cmd='git merge -m "note --abort here" feature/x'
merge_quoted_abort_json="$(json_escape "$merge_quoted_abort_cmd")"

assert_exit "merge: コミットメッセージ内の --abort 文字列には反応せずブロック（fail-open 修正）" \
  2 '{"agent_type":"","tool_input":{"command":'"$merge_quoted_abort_json"'}}'

assert_exit "pull --rebase --ff-only は --rebase 優先でブロック（fail-open 修正）" \
  2 '{"agent_type":"","tool_input":{"command":"git pull --rebase --ff-only"}}'

assert_exit "pull --ff-only --rebase も順序によらずブロック（fail-open 修正）" \
  2 '{"agent_type":"","tool_input":{"command":"git pull --ff-only --rebase"}}'

assert_exit "merge --abort extra-arg は厳密一致でないためブロック（fail-open 修正）" \
  2 '{"agent_type":"","tool_input":{"command":"git merge --abort extra-arg"}}'

assert_exit "stash push -m drop-old-work は第2語が push なので許可（部分文字列誤検知の修正）" \
  0 '{"agent_type":"","tool_input":{"command":"git stash push -m drop-old-work"}}'

assert_exit "restore -S file.txt は短形式単独で許可" \
  0 '{"agent_type":"","tool_input":{"command":"git restore -S file.txt"}}'

assert_exit "stash show は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git stash show"}}'

assert_exit "stash branch fix/x は許可" \
  0 '{"agent_type":"","tool_input":{"command":"git stash branch fix/x"}}'

# --- git-composer 以外のサブエージェントは変更系をブロック（P3: 免除を git-composer のみに限定） ---

assert_exit "agent_type=tdd-strict-coder + push はブロック（サブエージェント免除の限定）" \
  2 '{"agent_type":"tdd-strict-coder","tool_input":{"command":"git push origin feature/x"}}'

assert_exit "agent_type=implementation-coder + commit はブロック（サブエージェント免除の限定）" \
  2 '{"agent_type":"implementation-coder","tool_input":{"command":"git commit -m x"}}'

assert_exit "agent_type=tdd-strict-coder + gh pr create はブロック（サブエージェント免除の限定）" \
  2 '{"agent_type":"tdd-strict-coder","tool_input":{"command":"gh pr create --title x"}}'

assert_exit "agent_type=retrospective-analyst + add はブロック（サブエージェント免除の限定）" \
  2 '{"agent_type":"retrospective-analyst","tool_input":{"command":"git add ."}}'

# --- ブロック文面: agent_type によって案内文が分岐すること ---
#
# なぜ最小の assert_stderr ヘルパーを追加するのか:
# block-debug-log-residue.test.sh (:85-100) に前例があるとおり、grep -qF による
# stderr 内容検証は exit code だけでは検出できない「文面の誤り」を捕捉するのに必要。
# ここでは must_not_contain も検証したいため、空文字列ならスキップする形で
# contains/not-contains 両方を1つのヘルパーに統合する（コード重複を避ける）。
#
# $1: label, $2: expected exit code, $3: stderr に含まれるべき文字列（空なら未検証）,
# $4: stderr に含まれてはならない文字列（空なら未検証）, $5: json stdin
assert_stderr() {
  local label="$1" expected="$2" must_contain="$3" must_not_contain="$4" json="$5"
  local actual ok=1
  bash "$HOOK" <<<"$json" \
    >/tmp/delegate-git-test-stdout.$$ 2>/tmp/delegate-git-test-stderr.$$
  actual=$?
  [ "$actual" = "$expected" ] || ok=0
  if [ -n "$must_contain" ]; then
    grep -qF "$must_contain" /tmp/delegate-git-test-stderr.$$ || ok=0
  fi
  if [ -n "$must_not_contain" ]; then
    grep -qF "$must_not_contain" /tmp/delegate-git-test-stderr.$$ && ok=0
  fi
  if [ "$ok" = 1 ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected actual=$actual, must_contain=[$must_contain], must_not_contain=[$must_not_contain])"
    echo "  stderr: $(cat /tmp/delegate-git-test-stderr.$$)"
    fail=$((fail + 1))
  fi
  rm -f /tmp/delegate-git-test-stdout.$$ /tmp/delegate-git-test-stderr.$$
}

assert_stderr "サブエージェント向け文面はリトライ禁止を含み、Agentツールでの起動指示を含まない" \
  2 "リトライするな" "Agent ツールで" \
  '{"agent_type":"tdd-strict-coder","tool_input":{"command":"git commit -m x"}}'

assert_stderr "サブエージェント向け文面は「git-composer サブエージェントを起動」という主旨の指示を含まない" \
  2 "" "git-composer サブエージェントを起動" \
  '{"agent_type":"tdd-strict-coder","tool_input":{"command":"git commit -m x"}}'

assert_stderr "main向け文面は従来通りAgentツールでの起動指示を含む（回帰確認）" \
  2 "Agent ツールで" "" \
  '{"agent_type":"","tool_input":{"command":"git commit -m x"}}'

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
