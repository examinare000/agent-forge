#!/bin/bash
# scaffold/new-project.sh のスモークテスト。
#
# installer/install.test.sh と同じ理由でBASH_BIN(/bin/bash固定)を使い、bash 3.2の
# 回帰を確実に踏む。new-project.shはDEST（一時ディレクトリ）と、linkモード時のみ
# CLAUDE_DIR（読み取りのみ）に触れるだけで、実HOME/実~/.claudeは一切変更しないため、
# install.test.shのように「repo一式を一時ディレクトリへ複製する」必要はない
# （REPO_ROOTは実際のagent-forgeチェックアウトのまま使ってよい。読み取り専用のため）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
NEW_PROJECT_SH="${SCRIPT_DIR}/new-project.sh"
BASH_BIN="/bin/bash"
if [ ! -x "${BASH_BIN}" ]; then
  echo "エラー: ${BASH_BIN} が見つかりません（bash 3.2でのregressionテストが実施できません）" >&2
  exit 1
fi

pass=0
fail=0

WORKDIR="$(mktemp -d)"
WORKDIR="$(cd "${WORKDIR}" && pwd -P)"
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
    echo "  --- output ---"
    printf '%s\n' "${output}" | sed 's/^/  /'
    echo "  --------------"
    fail=$((fail + 1))
  fi
}

assert_exists() {
  local label="$1" path="$2"
  if [ -e "${path}" ]; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} (存在すべきパスが無い: ${path})"
    fail=$((fail + 1))
  fi
}

assert_file_content() {
  local label="$1" path="$2" expected="$3" actual
  actual="$(cat "${path}" 2>/dev/null || echo MISSING)"
  if [ "${actual}" = "${expected}" ]; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} (期待='${expected}' 実際='${actual}')"
    fail=$((fail + 1))
  fi
}

assert_symlink_target() {
  local label="$1" path="$2" expected="$3" actual
  if [ ! -L "${path}" ]; then
    echo "FAIL: ${label} (symlinkではありません: ${path})"
    fail=$((fail + 1))
    return
  fi
  actual="$(readlink "${path}")"
  if [ "${actual}" = "${expected}" ]; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} (期待=${expected} 実際=${actual})"
    fail=$((fail + 1))
  fi
}

# link モード用: installerが導入した体でCLAUDE_DIRにダミーfixtureを用意する。
build_fake_claude_dir() {
  local dir="$1"
  mkdir -p "${dir}/rules"
  echo "# dummy CLAUDE.core.md" > "${dir}/CLAUDE.core.md"
  echo "# dummy 11" > "${dir}/rules/11-testing-strategy.md"
  echo "# dummy 15" > "${dir}/rules/15-frontend-design.md"
  echo "# dummy 70" > "${dir}/rules/70-docker-environments.md"
}

# $1: dest, 残りをnew-project.shへ単語分割で渡す。CLAUDE_DIRは常に一時ディレクトリに固定する
# （実HOME/~/.claudeへは一切依存させない）。
run_new_project() {
  local dest="$1" claude_dir="$2"
  shift 2
  CLAUDE_DIR="${claude_dir}" "${BASH_BIN}" "${NEW_PROJECT_SH}" "${dest}" "$@" 2>&1
}

EMPTY_CLAUDE_DIR="${WORKDIR}/empty-claude-dir"
mkdir -p "${EMPTY_CLAUDE_DIR}"

echo "=== ①: copyモード(既定)の新規プロジェクト生成 ==="
DEST1="${WORKDIR}/proj-copy"
out="$(run_new_project "${DEST1}" "${EMPTY_CLAUDE_DIR}" --name "デモプロジェクト")"
rc=$?
assert_rc "copyモード生成: exit 0" 0 "${rc}"

assert_exists "AGENTS.mdがコピーされる" "${DEST1}/AGENTS.md"
assert_exists "GEMINI.mdがコピーされる" "${DEST1}/GEMINI.md"
assert_exists "CLAUDE.mdが生成される" "${DEST1}/CLAUDE.md"
assert_exists ".claude/rules/testing.mdが生成される" "${DEST1}/.claude/rules/testing.md"
assert_exists ".claude/rules/frontend.mdが生成される" "${DEST1}/.claude/rules/frontend.md"
assert_exists ".claude/rules/docker.mdが生成される" "${DEST1}/.claude/rules/docker.md"
assert_exists ".mcp.jsonが生成される" "${DEST1}/.mcp.json"
assert_exists ".claude/settings.local.jsonが生成される" "${DEST1}/.claude/settings.local.json"
assert_exists "scripts/check-agent-assets.shがコピーされる" "${DEST1}/scripts/check-agent-assets.sh"
assert_exists "scripts/check-docs.shがコピーされる" "${DEST1}/scripts/check-docs.sh"
assert_exists ".gitignoreが生成される" "${DEST1}/.gitignore"
assert_exists "README.mdが生成される" "${DEST1}/README.md"
assert_exists "gitリポジトリが初期化される(.git)" "${DEST1}/.git"

if [ -L "${DEST1}/CLAUDE.md" ]; then
  echo "FAIL: copyモードのCLAUDE.mdはsymlinkであってはならない"
  fail=$((fail + 1))
else
  echo "PASS: copyモードのCLAUDE.mdは実体ファイル"
  pass=$((pass + 1))
fi

claude_md_text="$(cat "${DEST1}/CLAUDE.md" 2>/dev/null || echo MISSING)"
assert_contains "CLAUDE.mdにプロジェクト名が反映される" "${claude_md_text}" "デモプロジェクト"
assert_not_found_placeholder="$(printf '%s' "${claude_md_text}" | grep -c '{{PROJECT_NAME}}' || true)"
if [ "${assert_not_found_placeholder:-0}" -eq 0 ]; then
  echo "PASS: CLAUDE.mdに未置換の{{PROJECT_NAME}}が残らない"
  pass=$((pass + 1))
else
  echo "FAIL: CLAUDE.mdに未置換の{{PROJECT_NAME}}が残っている"
  fail=$((fail + 1))
fi

[ -x "${DEST1}/scripts/check-agent-assets.sh" ] && echo "PASS: check-agent-assets.shは実行権限付き" && pass=$((pass + 1)) \
  || { echo "FAIL: check-agent-assets.shに実行権限が無い"; fail=$((fail + 1)); }

# dist/codex-agents/*.toml は installer が ~/.claude に codex 資産を置かない（symlink先が無い）ため、
# copy/linkどちらのモードでもプロジェクトの.codex/agents/へ実体コピーする。
codex_agents_count="$(find "${DEST1}/.codex/agents" -maxdepth 1 -type f -name '*.toml' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${codex_agents_count}" = "8" ]; then
  echo "PASS: .codex/agents/に8個のtomlがコピーされる"
  pass=$((pass + 1))
else
  echo "FAIL: .codex/agents/のtoml数が8ではない(実際: ${codex_agents_count})"
  fail=$((fail + 1))
fi
assert_exists ".codex/agents/tdd-strict-coder.tomlがコピーされる" "${DEST1}/.codex/agents/tdd-strict-coder.toml"

branch_name="$(git -C "${DEST1}" branch --show-current 2>/dev/null || echo MISSING)"
if [ "${branch_name}" = "main" ]; then
  echo "PASS: 初期ブランチはmain"
  pass=$((pass + 1))
else
  echo "FAIL: 初期ブランチがmainではない(実際: ${branch_name})"
  fail=$((fail + 1))
fi
if git -C "${DEST1}" show-ref --verify --quiet refs/heads/develop; then
  echo "FAIL: developブランチは作られてはいけない"
  fail=$((fail + 1))
else
  echo "PASS: developブランチは作られない"
  pass=$((pass + 1))
fi

echo ""
echo "=== ②: check-agent-assets.sh / check-docs.sh が生成直後のプロジェクトに対してexit 0 ==="
rc=0
out="$(cd "${DEST1}" && bash scripts/check-agent-assets.sh 2>&1)" || rc=$?
assert_rc "check-agent-assets.sh: exit 0" 0 "${rc}"
# .codex/agentsは常に自動配置されるためパリティ検査は実際に発動する（.claude/agentsを
# project-scopedで持たない既定構成のためスキップ判定に入るが、これはfalse-positiveでは
# なく意図した挙動であることをスキップ理由の文言で確認する）。
assert_contains "check-agent-assets.sh: .codex/agentsは常に配置されるがproject-scoped .claude/agentsが無い既定構成のためスキップと判定される" "${out}" "スキップ"
if [ "${rc}" -ne 0 ]; then
  printf '%s\n' "${out}" | sed 's/^/  /'
fi

echo ""
echo "=== ③: 冪等性(同一destへの再実行) ==="
out2="$(run_new_project "${DEST1}" "${EMPTY_CLAUDE_DIR}" --name "デモプロジェクト")"
rc2=$?
assert_rc "2回目の実行もexit 0" 0 "${rc2}"
assert_contains "2回目は既存ファイルをskipする" "${out2}" "skip(既存)"
assert_contains "2回目はgit初期化をskipする" "${out2}" "既に git リポジトリのため初期化をスキップします"

echo ""
echo "=== ④: 既存の編集済みファイルは上書きされない ==="
DEST2="${WORKDIR}/proj-preserve"
mkdir -p "${DEST2}"
printf '編集済みのカスタムCLAUDE.md\n' > "${DEST2}/CLAUDE.md"
out="$(run_new_project "${DEST2}" "${EMPTY_CLAUDE_DIR}")"
rc=$?
assert_rc "既存ファイルがあってもexit 0" 0 "${rc}"
assert_file_content "編集済みCLAUDE.mdの内容が保持される" "${DEST2}/CLAUDE.md" "編集済みのカスタムCLAUDE.md"

echo ""
echo "=== ⑤: linkモードは ~/.claude(相当)未導入ならforge installを案内してfail ==="
DEST3="${WORKDIR}/proj-link-missing"
out="$(run_new_project "${DEST3}" "${EMPTY_CLAUDE_DIR}" --mode link)"
rc=$?
assert_rc "linkモード未導入時: exit 1" 1 "${rc}"
assert_contains "linkモード未導入時: forge installを案内する" "${out}" "forge install"

echo ""
echo "=== ⑥: linkモードは導入済み環境で ~/.claude 配下への絶対symlinkを張る ==="
FAKE_CLAUDE_DIR="${WORKDIR}/fake-claude-dir"
build_fake_claude_dir "${FAKE_CLAUDE_DIR}"
DEST4="${WORKDIR}/proj-link-ok"
out="$(run_new_project "${DEST4}" "${FAKE_CLAUDE_DIR}" --mode link)"
rc=$?
assert_rc "linkモード導入済み時: exit 0" 0 "${rc}"
assert_symlink_target "CLAUDE.mdはCLAUDE_DIR/CLAUDE.core.mdへのsymlink" "${DEST4}/CLAUDE.md" "${FAKE_CLAUDE_DIR}/CLAUDE.core.md"
assert_symlink_target "testing.mdはCLAUDE_DIR/rules/11-testing-strategy.mdへのsymlink" "${DEST4}/.claude/rules/testing.md" "${FAKE_CLAUDE_DIR}/rules/11-testing-strategy.md"
assert_symlink_target "frontend.mdはCLAUDE_DIR/rules/15-frontend-design.mdへのsymlink" "${DEST4}/.claude/rules/frontend.md" "${FAKE_CLAUDE_DIR}/rules/15-frontend-design.md"
assert_symlink_target "docker.mdはCLAUDE_DIR/rules/70-docker-environments.mdへのsymlink" "${DEST4}/.claude/rules/docker.md" "${FAKE_CLAUDE_DIR}/rules/70-docker-environments.md"
assert_exists "linkモードでもAGENTS.mdは実体コピー" "${DEST4}/AGENTS.md"
if [ -L "${DEST4}/AGENTS.md" ]; then
  echo "FAIL: AGENTS.mdはlinkモードでもsymlinkであってはならない(installerがAGENTS.mdを~/.claudeへ張らないため)"
  fail=$((fail + 1))
else
  echo "PASS: AGENTS.mdはlinkモードでも実体ファイル"
  pass=$((pass + 1))
fi

echo ""
echo "=== ⑦: 既存gitリポジトリの内部への作成は拒否する ==="
OUTER_REPO="${WORKDIR}/outer-repo"
mkdir -p "${OUTER_REPO}"
git -C "${OUTER_REPO}" init --quiet -b main
NESTED_DEST="${OUTER_REPO}/nested-project"
out="$(run_new_project "${NESTED_DEST}" "${EMPTY_CLAUDE_DIR}")"
rc=$?
assert_rc "既存repo内部への作成: exit 1" 1 "${rc}"
assert_contains "既存repo内部への作成: エラーメッセージに既存リポジトリである旨が出る" "${out}" "既存のgitリポジトリの内部"

echo ""
echo "=== ⑧: 引数不足はexit 1でusageを表示する ==="
rc=0
out="$("${BASH_BIN}" "${NEW_PROJECT_SH}" 2>&1)" || rc=$?
assert_rc "引数無し: exit 1" 1 "${rc}"
assert_contains "引数無し: 使い方が表示される" "${out}" "使い方"

echo ""
echo "----"
echo "pass=${pass} fail=${fail}"
[ "${fail}" -eq 0 ]
