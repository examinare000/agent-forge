#!/bin/bash
# scaffold/templates/scripts/check-agent-assets.sh のスモークテスト。
#
# この配下のスクリプトは各プロジェクトへコピーされて実行される想定のため、
# 「プロジェクトルートに配置されたcheck-agent-assets.shを実行する」形で検証する
# （scripts/ という中間ディレクトリを1階層作る必要がある — スクリプト自身が
# `$(dirname .. )/..` でROOTを解決するため）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK_SH="${SCRIPT_DIR}/check-agent-assets.sh"

pass=0
fail=0

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

assert_rc() {
  local label="$1" expected="$2" actual="$3"
  if [ "${actual}" = "${expected}" ]; then
    echo "PASS: ${label} (exit=${actual})"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} (expected exit=${expected} actual=${actual})"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "${output}" | grep -qF -- "${needle}"; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} (needle not found: ${needle})"
    fail=$((fail + 1))
  fi
}

# $1: ケース名。stdout: 作成したプロジェクトルートの絶対パス。
# .claude/rules/{testing,frontend,docker}.md は健全な既定状態(paths:frontmatter付き非空ファイル)で作る。
build_project() {
  local name="$1"
  local proj="${WORKDIR}/${name}"
  mkdir -p "${proj}/scripts" "${proj}/.claude/rules"
  cp "${CHECK_SH}" "${proj}/scripts/check-agent-assets.sh"
  chmod +x "${proj}/scripts/check-agent-assets.sh"
  for rule in testing frontend docker; do
    printf -- '---\npaths:\n  - "**/*"\n---\n\n参照ファイル\n' > "${proj}/.claude/rules/${rule}.md"
  done
  printf '%s' "${proj}"
}

run_check() {
  local proj="$1"
  (cd "${proj}" && bash scripts/check-agent-assets.sh) 2>&1
}

echo "=== ①: .codex/agentsが無いプロジェクトはエージェント対応表チェックをskipしexit 0 ==="
proj="$(build_project "no-codex")"
out="$(run_check "${proj}")"
rc=$?
assert_rc "exit 0" 0 "${rc}"
assert_contains "スキップ理由が出力される" "${out}" "スキップ"

echo ""
echo "=== ②a: .codex/agentsのみ存在し.claude/agentsが無ければスキップしexit 0 ==="
# forge new は既定構成(project-scoped .claude/agentsを持たない)でも常に.codex/agentsを
# 自動配置するため、.codex/agentsの存在だけをトリガにすると通常のforge new生成直後の
# プロジェクトが全て「エージェント過剰」判定を受けてしまう回帰。project-scoped .claude/agents
# を上級者が独自追加した場合にのみパリティ検査を発動させる。
proj="$(build_project "codex-only-no-claude-agents")"
mkdir -p "${proj}/.codex/agents"
printf 'name = %s\ndeveloper_instructions = %s\n' "'''solo-codex-agent'''" "'''dummy'''" > "${proj}/.codex/agents/solo-codex-agent.toml"
out="$(run_check "${proj}")"
rc=$?
assert_rc "exit 0" 0 "${rc}"
assert_contains "スキップ理由が出力される" "${out}" "スキップ"

echo ""
echo "=== ②: .codex/agentsがあり.claude/agentsに対応が無ければexit 1(過剰) ==="
proj="$(build_project "codex-excess")"
mkdir -p "${proj}/.codex/agents" "${proj}/.claude/agents"
printf 'name = %s\ndeveloper_instructions = %s\n' "'''orphan-agent'''" "'''dummy'''" > "${proj}/.codex/agents/orphan-agent.toml"
out="$(run_check "${proj}")"
rc=$?
assert_rc "エージェント過剰でexit 1" 1 "${rc}"
assert_contains "過剰の指摘メッセージが出る" "${out}" "エージェント過剰"

echo ""
echo "=== ③: .claude/agentsにあり.codex/agentsに対応が無ければexit 1(欠落) ==="
proj="$(build_project "codex-missing")"
mkdir -p "${proj}/.codex/agents" "${proj}/.claude/agents"
printf -- '---\nname: "solo-agent"\n---\n\ndummy\n' > "${proj}/.claude/agents/solo-agent.md"
out="$(run_check "${proj}")"
rc=$?
assert_rc "エージェント欠落でexit 1" 1 "${rc}"
assert_contains "欠落の指摘メッセージが出る" "${out}" "エージェント欠落"

echo ""
echo "=== ④: name一致(agent-forge実形式の'''リテラル文字列)ならexit 0 ==="
proj="$(build_project "codex-name-match")"
mkdir -p "${proj}/.codex/agents" "${proj}/.claude/agents"
printf -- '---\nname: "sync-agent"\n---\n\ndummy\n' > "${proj}/.claude/agents/sync-agent.md"
printf "name = '''sync-agent'''\ndeveloper_instructions = '''dummy'''\n" > "${proj}/.codex/agents/sync-agent.toml"
out="$(run_check "${proj}")"
rc=$?
assert_rc "name一致でexit 0" 0 "${rc}"

echo ""
echo "=== ⑤: name不一致ならexit 1 ==="
proj="$(build_project "codex-name-mismatch")"
mkdir -p "${proj}/.codex/agents" "${proj}/.claude/agents"
printf -- '---\nname: "sync-agent"\n---\n\ndummy\n' > "${proj}/.claude/agents/sync-agent.md"
printf "name = '''different-name'''\ndeveloper_instructions = '''dummy'''\n" > "${proj}/.codex/agents/sync-agent.toml"
out="$(run_check "${proj}")"
rc=$?
assert_rc "name不一致でexit 1" 1 "${rc}"
assert_contains "name不一致の指摘メッセージが出る" "${out}" "name 不一致"

echo ""
echo "=== ⑥: .claude/rules/の参照ファイルが欠落していればexit 1 ==="
proj="$(build_project "rules-missing")"
rm -f "${proj}/.claude/rules/testing.md"
out="$(run_check "${proj}")"
rc=$?
assert_rc "ルール参照欠落でexit 1" 1 "${rc}"
assert_contains "欠落の指摘メッセージが出る" "${out}" "ルール参照ファイル欠落"

echo ""
echo "=== ⑦: .claude/rules/の参照ファイルがpaths:frontmatterを持たなければexit 1 ==="
proj="$(build_project "rules-no-paths")"
printf 'paths無しの本文だけのファイル\n' > "${proj}/.claude/rules/docker.md"
out="$(run_check "${proj}")"
rc=$?
assert_rc "paths:欠落でexit 1" 1 "${rc}"
assert_contains "paths:欠落の指摘メッセージが出る" "${out}" "paths: frontmatter"

echo ""
echo "=== ⑧: .claude/rules/が壊れたsymlinkならexit 1 ==="
proj="$(build_project "rules-broken-symlink")"
rm -f "${proj}/.claude/rules/frontend.md"
ln -s "/no/such/target-15-frontend-design.md" "${proj}/.claude/rules/frontend.md"
out="$(run_check "${proj}")"
rc=$?
assert_rc "壊れたsymlinkでexit 1" 1 "${rc}"
assert_contains "symlink切断の指摘メッセージが出る" "${out}" "symlink 切断"

echo ""
echo "=== ⑨: 健全なプロジェクトはexit 0(✅) ==="
proj="$(build_project "healthy")"
out="$(run_check "${proj}")"
rc=$?
assert_rc "健全プロジェクトはexit 0" 0 "${rc}"
assert_contains "OKメッセージが出る" "${out}" "エージェント資産チェック OK"

echo ""
echo "----"
echo "pass=${pass} fail=${fail}"
[ "${fail}" -eq 0 ]
