#!/bin/bash
# bin/forge のスモークテスト（ディスパッチャの引数透過を検証する）。
#
# install.sh --check の完全な健全性（doctor判定）自体は installer/install.test.sh の
# 責務なので、本テストでは「forge installが実際にinstall.shへ引数を透過して
# 呼び出しているか」だけを出力の一致で確認する（環境依存のprereq判定結果には依存しない）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
FORGE_BIN="${SCRIPT_DIR}/forge"
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

run_forge() {
  "${BASH_BIN}" "${FORGE_BIN}" "$@" 2>&1
}

echo "=== ①: 引数無しはexit 1でusageを表示 ==="
out="$(run_forge)"
rc=$?
assert_rc "引数無し: exit 1" 1 "${rc}"
assert_contains "引数無し: 使い方が表示される" "${out}" "使い方"

echo ""
echo "=== ②: forge help はexit 0でusageを表示 ==="
out="$(run_forge help)"
rc=$?
assert_rc "help: exit 0" 0 "${rc}"
assert_contains "help: コマンド一覧が出る" "${out}" "install"
assert_contains "help: コマンド一覧が出る" "${out}" "new"
assert_contains "help: コマンド一覧が出る" "${out}" "check"

echo ""
echo "=== ③: 不明なコマンドはexit 1 ==="
out="$(run_forge nonsense)"
rc=$?
assert_rc "不明コマンド: exit 1" 1 "${rc}"
assert_contains "不明コマンド: エラーメッセージが出る" "${out}" "不明なコマンドです"

echo ""
echo "=== ④: forge install -h はinstaller/install.shの使い方へ透過される ==="
direct_out="$(bash "${REPO_ROOT}/installer/install.sh" -h 2>&1)"
forge_out="$(run_forge install -h)"
rc=$?
assert_rc "forge install -h: exit 0" 0 "${rc}"
if [ "${forge_out}" = "${direct_out}" ]; then
  echo "PASS: forge install -h の出力はinstall.sh -h と一致する(引数透過)"
  pass=$((pass + 1))
else
  echo "FAIL: forge install -h の出力がinstall.sh -h と一致しない"
  echo "  --- forge ---"; printf '%s\n' "${forge_out}" | sed 's/^/  /'
  echo "  --- direct ---"; printf '%s\n' "${direct_out}" | sed 's/^/  /'
  fail=$((fail + 1))
fi

echo ""
echo "=== ⑤: forge new <dir>なしはexit 1 ==="
out="$(run_forge new)"
rc=$?
assert_rc "forge new(dir無し): exit 1" 1 "${rc}"

echo ""
echo "=== ⑥: forge new <tmp>/demo でプロジェクトが生成できる(e2e) ==="
DEMO_DIR="${WORKDIR}/demo"
out="$(CLAUDE_DIR="${WORKDIR}/unused-claude-dir" run_forge new "${DEMO_DIR}" --name demo)"
rc=$?
assert_rc "forge new: exit 0" 0 "${rc}"
if [ -f "${DEMO_DIR}/scripts/check-agent-assets.sh" ]; then
  echo "PASS: forge newでscripts/check-agent-assets.shが生成される"
  pass=$((pass + 1))
else
  echo "FAIL: forge newでscripts/check-agent-assets.shが生成されない"
  fail=$((fail + 1))
fi

echo ""
echo "=== ⑦: forge check <dir> は生成済みプロジェクトのcheck-agent-assets.shを実行する(exit 0) ==="
rc=0
out="$(cd "${WORKDIR}" && "${BASH_BIN}" "${FORGE_BIN}" check "${DEMO_DIR}" 2>&1)" || rc=$?
assert_rc "forge check <dir>: exit 0" 0 "${rc}"
assert_contains "forge check <dir>: OKメッセージが出る" "${out}" "エージェント資産チェック OK"

echo ""
echo "=== ⑧: forge check <dir> はcheck-agent-assets.shが無ければexit 1 ==="
EMPTY_DIR="${WORKDIR}/empty-project"
mkdir -p "${EMPTY_DIR}"
out="$(run_forge check "${EMPTY_DIR}")"
rc=$?
assert_rc "forge check <dir(未生成)>: exit 1" 1 "${rc}"
assert_contains "forge check <dir(未生成)>: エラーメッセージが出る" "${out}" "見つかりません"

echo ""
echo "=== ⑨: forge check(引数無し)はinstall.sh --checkへ透過される(doctorバナー出力) ==="
out="$(run_forge check)" || true
assert_contains "forge check: doctorバナーが出る" "${out}" "doctor"

echo ""
echo "----"
echo "pass=${pass} fail=${fail}"
[ "${fail}" -eq 0 ]
