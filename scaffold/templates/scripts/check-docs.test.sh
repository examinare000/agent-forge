#!/bin/bash
# scaffold/templates/scripts/check-docs.sh のスモークテスト。
#
# check-agent-assets.test.sh と同じ理由で、プロジェクトルートに配置された
# check-docs.sh を「scripts/」配下から実行する形で検証する（スクリプト自身が
# `$(dirname ..)/..` でROOTを解決するため、1階層下に置く必要がある）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK_SH="${SCRIPT_DIR}/check-docs.sh"

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
build_project() {
  local name="$1"
  local proj="${WORKDIR}/${name}"
  mkdir -p "${proj}/scripts"
  cp "${CHECK_SH}" "${proj}/scripts/check-docs.sh"
  chmod +x "${proj}/scripts/check-docs.sh"
  printf '%s' "${proj}"
}

run_check() {
  local proj="$1"
  (cd "${proj}" && bash scripts/check-docs.sh) 2>&1
}

echo "=== ①: docs/ が無ければskipしexit 0 ==="
proj="$(build_project "no-docs")"
out="$(run_check "${proj}")"
rc=$?
assert_rc "exit 0" 0 "${rc}"
assert_contains "スキップ理由が出力される" "${out}" "スキップ"

echo ""
echo "=== ②: 移行済み.mdと同名の手書きHTMLが残っていればexit 1 ==="
proj="$(build_project "html-residue")"
mkdir -p "${proj}/docs/design"
printf '# foo\n' > "${proj}/docs/design/foo.md"
printf '<html></html>\n' > "${proj}/docs/design/foo.html"
out="$(run_check "${proj}")"
rc=$?
assert_rc "HTML残骸でexit 1" 1 "${rc}"
assert_contains "残骸の指摘メッセージが出る" "${out}" "手書き HTML が残っています"

echo ""
echo "=== ③: designディレクトリに.mdが一つも無ければexit 1 ==="
proj="$(build_project "no-md")"
mkdir -p "${proj}/docs/design"
printf 'not markdown\n' > "${proj}/docs/design/notes.txt"
out="$(run_check "${proj}")"
rc=$?
assert_rc "Markdown正本無しでexit 1" 1 "${rc}"
assert_contains "正本が無い指摘メッセージが出る" "${out}" "Markdown 正本がありません"

echo ""
echo "=== ④: .md正本が存在する.htmlへのMarkdownリンクはexit 1 ==="
proj="$(build_project "dangling-html-link")"
mkdir -p "${proj}/docs/design"
printf '# foo\n' > "${proj}/docs/design/foo.md"
printf '[foo](design/foo.html) を参照。\n' > "${proj}/docs/index.md"
out="$(run_check "${proj}")"
rc=$?
assert_rc "張り替え漏れリンクでexit 1" 1 "${rc}"
assert_contains "リンク修正の指摘メッセージが出る" "${out}" "要修正の design HTML リンク"

echo ""
echo "=== ⑤: 奇数個のコードフェンスはexit 1 ==="
proj="$(build_project "odd-fence")"
mkdir -p "${proj}/docs/design"
printf '# foo\n\n```mermaid\ngraph TD\n' > "${proj}/docs/design/foo.md"
out="$(run_check "${proj}")"
rc=$?
assert_rc "フェンス不整合でexit 1" 1 "${rc}"
assert_contains "フェンス不整合の指摘メッセージが出る" "${out}" "コードフェンス"

echo ""
echo "=== ⑥: 健全なdocsはexit 0 ==="
proj="$(build_project "healthy")"
mkdir -p "${proj}/docs/design"
printf '# foo\n\n```mermaid\ngraph TD\n```\n' > "${proj}/docs/design/foo.md"
out="$(run_check "${proj}")"
rc=$?
assert_rc "健全なdocsはexit 0" 0 "${rc}"
assert_contains "OKメッセージが出る" "${out}" "ドキュメントチェック OK"

echo ""
echo "----"
echo "pass=${pass} fail=${fail}"
[ "${fail}" -eq 0 ]
