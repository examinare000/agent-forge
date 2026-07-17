#!/bin/bash
# installer/install.sh のスモークテスト。
#
# 前提: /bin/bash (3.2系) での実行を前提にしている。bootstrap.test.sh と同様、
# 空配列展開のset -u回帰やbash 3.2固有の挙動を確実に踏むため、内部の
# 再帰呼び出しは全て `bash` ではなく `$BASH_BIN`（/bin/bash固定）を使う。
#
# なぜ実HOME/実CLAUDE_DIRを一切変更しないのか:
# install.sh はデフォルト実行で ~/.claude を書き換える破壊的スクリプトのため、
# 全シナリオで HOME / CLAUDE_DIR を一時ディレクトリへ差し替えて実行する。
# REPO_ROOT は common.sh が「自分自身の物理パス」から逆算する設計（頒布用
# インストーラのため固定clone位置を前提にしない）なので、install.sh一式を
# 一時ディレクトリへコピーして実行するだけでREPO_ROOTも一時ツリーに固定できる。
#
# なぜ claude/CLAUDE.core.md や claude/settings.base.json を本物からコピー
# しないのか:
# これらは並行タスクが作成中のため、テストでは中身を問わないダミー
# フィクスチャで代替する（install.sh 側は「存在すればlink/copyする」という
# 契約だけを検証すればよい）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BASH_BIN="/bin/bash"
if [ ! -x "${BASH_BIN}" ]; then
  echo "エラー: ${BASH_BIN} が見つかりません（bash 3.2でのregressionテストが実施できません）" >&2
  exit 1
fi

pass=0
fail=0

WORKDIR="$(mktemp -d)"
# install.sh 内部は REPO_ROOT を `pwd -P` で解決するため、macOSの
# /tmp -> /private/tmp のようなsymlink付き一時パスをテスト側も正規化しておく
# （でないと期待値と実際値が単なる表記違いでFAILする）。
WORKDIR="$(cd "${WORKDIR}" && pwd -P)"
trap 'rm -rf "${WORKDIR}"' EXIT

# --- 必須CLIスタブ（ハーミティック化） ---------------------------------------
# なぜ claude をスタブするのか:
# install.sh の prereq検査は `command -v claude` の可否のみを見る（実行はしない）。
# claude CLI は開発機にはあるがCIランナーには存在しないため、このテストは
# 「ローカルではgreen・CIでは大半FAIL」という環境依存（非ハーミティック）な
# 状態になっていた。実行されない前提のCLIなので `exit 0` の空スタブで十分。
# git/jq は install.sh が実際にサブコマンドとして使う（git clone/checkout,
# jq -r 等）ため実物が必要 — スタブせず、CIランナーにプリインストール済みの
# ものをそのまま使う。
# ⑥番シナリオ（必須CLI不足時にfailすることの検証）だけは意図的にこの
# STUB_BINを含まないPATHへ絞り込んでいるため影響を受けない。
STUB_BIN="${WORKDIR}/stub-bin"
mkdir -p "${STUB_BIN}"
cat > "${STUB_BIN}/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${STUB_BIN}/claude"
PATH="${STUB_BIN}:${PATH}"

# $1: label, $2: expected exit code, $3: actual exit code
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

# $1: label, $2: output全体, $3: 含まれるべき文字列
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

# $1: label, $2: output全体, $3: 含まれてはいけない文字列
assert_not_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "${output}" | grep -qF -- "${needle}"; then
    echo "FAIL: ${label} (unexpected needle found: ${needle})"
    fail=$((fail + 1))
  else
    echo "PASS: ${label}"
    pass=$((pass + 1))
  fi
}

# $1: label, $2: 実際のパス, $3: 期待するsymlinkターゲット
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

# --- スタブ superpowers 用のローカルbare相当repo -----------------------------
# ネットワーク不要のsuperpowers cloneスタブとして、file://経由で参照できる
# ローカルgit repoを1つ作り、全ケースで使い回す（コミットが同じなら
# lockFileのSHAも固定できるため、fixtureとして安定する）。
SUPERPOWERS_ORIGIN="${WORKDIR}/superpowers-origin"
mkdir -p "${SUPERPOWERS_ORIGIN}"
git -C "${SUPERPOWERS_ORIGIN}" init --quiet --initial-branch=main
git -C "${SUPERPOWERS_ORIGIN}" config user.email "test@example.com"
git -C "${SUPERPOWERS_ORIGIN}" config user.name "test"
echo "dummy skill" > "${SUPERPOWERS_ORIGIN}/dummy-skill.md"
git -C "${SUPERPOWERS_ORIGIN}" add dummy-skill.md
git -C "${SUPERPOWERS_ORIGIN}" commit --quiet -m "dummy commit"
SUPERPOWERS_ORIGIN_SHA="$(git -C "${SUPERPOWERS_ORIGIN}" rev-parse HEAD)"

# $1: ケース名, $2: manifest.jsonに追加で当てるjqフィルタ（無ければ"."）
# stdout: "repo home" （作成した一時repo/homeの絶対パス、1行2フィールド）
build_fake_repo() {
  local case_name="$1" extra_filter="${2:-.}"
  local repo="${WORKDIR}/${case_name}/repo"
  local home="${WORKDIR}/${case_name}/home"
  mkdir -p "${repo}/installer/lib" "${repo}/agents" "${repo}/hooks" "${repo}/skills" "${repo}/rules" "${repo}/claude"
  mkdir -p "${home}"

  cp "${SCRIPT_DIR}/lib/common.sh" "${repo}/installer/lib/common.sh"
  cp "${SCRIPT_DIR}/install.sh" "${repo}/installer/install.sh"
  chmod +x "${repo}/installer/install.sh"

  # linkEntries が指す実体（存在前提のダミーフィクスチャ）
  echo "dummy agent" > "${repo}/agents/dummy-agent.md"
  echo "dummy hook" > "${repo}/hooks/dummy-hook.sh"
  echo "dummy skill" > "${repo}/skills/dummy-skill.md"
  echo "dummy rule" > "${repo}/rules/00-core-principles.md"
  echo "# dummy CLAUDE.core.md" > "${repo}/claude/CLAUDE.core.md"
  echo '{"model": "dummy"}' > "${repo}/claude/settings.base.json"

  # superpowers.lockはスタブ origin の実コミットSHAで固定する
  printf '%s' "${SUPERPOWERS_ORIGIN_SHA}" > "${repo}/installer/superpowers.lock"

  jq --arg url "file://${SUPERPOWERS_ORIGIN}" \
     '.repos.superpowers.url = $url' \
     "${SCRIPT_DIR}/manifest.json" | jq "${extra_filter}" > "${repo}/installer/manifest.json"

  printf '%s %s' "${repo}" "${home}"
}

# install.sh を CLAUDE_DIR="$home/.claude" で実行する。
# $1: repo dir, $2: home dir, $3: install.sh へ渡す追加引数（複数可、単語分割で渡す）
run_install() {
  local repo="$1" home="$2"
  shift 2
  CLAUDE_DIR="${home}/.claude" HOME="${home}" "${BASH_BIN}" "${repo}/installer/install.sh" "$@" 2>&1
}

echo "=== ①: 新規環境へのインストール ==="

read -r repo home < <(build_fake_repo "fresh-install")
out="$(run_install "${repo}" "${home}")"
rc=$?
assert_rc "新規インストール: exit 0" 0 "${rc}"

assert_symlink_target "agents: 絶対パスsymlink" "${home}/.claude/agents" "${repo}/agents"
assert_symlink_target "hooks: 絶対パスsymlink" "${home}/.claude/hooks" "${repo}/hooks"
assert_symlink_target "skills: 絶対パスsymlink" "${home}/.claude/skills" "${repo}/skills"
assert_symlink_target "rules: 絶対パスsymlink" "${home}/.claude/rules" "${repo}/rules"
assert_symlink_target "CLAUDE.core.md: 絶対パスsymlink" "${home}/.claude/CLAUDE.core.md" "${repo}/claude/CLAUDE.core.md"

if [ -f "${home}/.claude/settings.json" ]; then
  echo "PASS: settings.json がコピーされている"
  pass=$((pass + 1))
else
  echo "FAIL: settings.json が存在しません"
  fail=$((fail + 1))
fi

if [ -f "${home}/.claude/.core-install.json" ]; then
  echo "PASS: .core-install.json が書かれている"
  pass=$((pass + 1))
  record_repo_root="$(jq -r '.repoRoot' "${home}/.claude/.core-install.json")"
  if [ "${record_repo_root}" = "${repo}" ]; then
    echo "PASS: .core-install.json のrepoRootが正しい"
    pass=$((pass + 1))
  else
    echo "FAIL: .core-install.json のrepoRootが不正 (期待=${repo} 実際=${record_repo_root})"
    fail=$((fail + 1))
  fi
else
  echo "FAIL: .core-install.json が存在しません"
  fail=$((fail + 1))
fi

if [ -d "${home}/.claude/plugins/superpowers/.git" ]; then
  echo "PASS: superpowersがcloneされている"
  pass=$((pass + 1))
  sp_sha="$(git -C "${home}/.claude/plugins/superpowers" rev-parse HEAD)"
  if [ "${sp_sha}" = "${SUPERPOWERS_ORIGIN_SHA}" ]; then
    echo "PASS: superpowersがlock済みSHAにcheckoutされている"
    pass=$((pass + 1))
  else
    echo "FAIL: superpowersのSHAがlockと不一致 (期待=${SUPERPOWERS_ORIGIN_SHA} 実際=${sp_sha})"
    fail=$((fail + 1))
  fi
else
  echo "FAIL: superpowersがcloneされていません"
  fail=$((fail + 1))
fi

echo "=== ②: 冪等性（2回実行で差分なし） ==="

read -r repo home < <(build_fake_repo "idempotent")
run_install "${repo}" "${home}" >/dev/null
# installedAt（エポック秒）が2回目実行で変わりうるため、記録ファイル自体の
# 中身diffは比較対象にせず「同じパス構造か」だけを冪等性の判定基準にする。
find "${home}/.claude" | sort > "${WORKDIR}/idempotent-before.txt"
out2="$(run_install "${repo}" "${home}")"
rc2=$?
assert_rc "2回目の実行: exit 0" 0 "${rc2}"
find "${home}/.claude" | sort > "${WORKDIR}/idempotent-after.txt"
if diff -q "${WORKDIR}/idempotent-before.txt" "${WORKDIR}/idempotent-after.txt" >/dev/null; then
  echo "PASS: 冪等性（パス構造に差分なし）"
  pass=$((pass + 1))
else
  echo "FAIL: 冪等性（パス構造に差分あり）"
  diff "${WORKDIR}/idempotent-before.txt" "${WORKDIR}/idempotent-after.txt" || true
  fail=$((fail + 1))
fi
assert_contains "2回目: 正しいsymlinkはskipログを出す" "${out2}" "skip（既に正しいsymlink）"
assert_contains "2回目: lock済みSHAと一致ログ" "${out2}" "lock済みSHAと一致しています"

echo "=== ③: 既存実体がある場合の非破壊skipと--force置換 ==="

read -r repo home < <(build_fake_repo "existing-real-entry")
mkdir -p "${home}/.claude"
echo "先住の実ファイル" > "${home}/.claude/rules"
out3="$(run_install "${repo}" "${home}")"
rc3=$?
assert_rc "実ファイルがある状態でも全体はexit 0" 0 "${rc3}"
assert_contains "実ファイル居座り: 警告ログ" "${out3}" "実ファイル/ディレクトリです。上書きしません"
if [ -L "${home}/.claude/rules" ]; then
  echo "FAIL: --force無しでsymlinkに置換されてしまった"
  fail=$((fail + 1))
else
  content="$(cat "${home}/.claude/rules")"
  if [ "${content}" = "先住の実ファイル" ]; then
    echo "PASS: --force無しでは実ファイルの中身が保持される"
    pass=$((pass + 1))
  else
    echo "FAIL: 実ファイルの中身が変わってしまった: ${content}"
    fail=$((fail + 1))
  fi
fi

out3f="$(run_install "${repo}" "${home}" --force)"
rc3f=$?
assert_rc "--force指定時: exit 0" 0 "${rc3f}"
assert_symlink_target "--force指定時: rulesがsymlinkに置換される" "${home}/.claude/rules" "${repo}/rules"

echo "=== ④: --check（doctorモード） ==="

read -r repo home < <(build_fake_repo "check-healthy")
run_install "${repo}" "${home}" >/dev/null
out4="$(run_install "${repo}" "${home}" --check)"
rc4=$?
assert_rc "健全な環境での--check: exit 0" 0 "${rc4}"
assert_not_contains "健全な環境: [FAIL]なし" "${out4}" "[FAIL]"
assert_contains "健全な環境: rulesはOK" "${out4}" "[OK]"

read -r repo home < <(build_fake_repo "check-broken")
run_install "${repo}" "${home}" >/dev/null
rm "${home}/.claude/rules"
out4b="$(run_install "${repo}" "${home}" --check)"
rc4b=$?
assert_rc "symlink欠落での--check: exit 1" 1 "${rc4b}"
assert_contains "symlink欠落: [FAIL]あり" "${out4b}" "[FAIL]"

echo "=== ⑤: --uninstall ==="

read -r repo home < <(build_fake_repo "uninstall")
run_install "${repo}" "${home}" >/dev/null
# uninstallの対象外である実ファイル（settings.json, superpowers clone）が
# 誤って除去されないことも併せて確認する。
out5="$(run_install "${repo}" "${home}" --uninstall)"
rc5=$?
assert_rc "--uninstall: exit 0" 0 "${rc5}"

for name in agents hooks skills rules CLAUDE.core.md; do
  if [ -e "${home}/.claude/${name}" ] || [ -L "${home}/.claude/${name}" ]; then
    echo "FAIL: --uninstall後もsymlinkが残っている: ${name}"
    fail=$((fail + 1))
  else
    echo "PASS: --uninstall後にsymlinkが除去されている: ${name}"
    pass=$((pass + 1))
  fi
done

if [ -f "${home}/.claude/.core-install.json" ]; then
  echo "FAIL: --uninstall後も.core-install.jsonが残っている"
  fail=$((fail + 1))
else
  echo "PASS: --uninstall後に.core-install.jsonが除去されている"
  pass=$((pass + 1))
fi

if [ -f "${home}/.claude/settings.json" ]; then
  echo "PASS: --uninstallはsettings.json（実ファイル）を残す"
  pass=$((pass + 1))
else
  echo "FAIL: --uninstallがsettings.jsonまで消してしまった（除去範囲を超えている）"
  fail=$((fail + 1))
fi

if [ -d "${home}/.claude/plugins/superpowers/.git" ]; then
  echo "PASS: --uninstallはsuperpowers cloneを残す"
  pass=$((pass + 1))
else
  echo "FAIL: --uninstallがsuperpowersまで消してしまった（除去範囲を超えている）"
  fail=$((fail + 1))
fi

# 既に実ファイルが居座っている（symlinkではない）エントリはuninstall対象外
read -r repo home < <(build_fake_repo "uninstall-real-file")
mkdir -p "${home}/.claude"
echo "実ファイル" > "${home}/.claude/rules"
run_install "${repo}" "${home}" --uninstall >/dev/null 2>&1 || true
if [ -f "${home}/.claude/rules" ] && [ ! -L "${home}/.claude/rules" ]; then
  echo "PASS: --uninstallは実ファイルのrulesに触れない"
  pass=$((pass + 1))
else
  echo "FAIL: --uninstallが実ファイルのrulesまで消してしまった"
  fail=$((fail + 1))
fi

echo "=== ⑥: 必須CLI（prereqs.required）が不足している場合はfail ==="

# git/jq は install.sh 自身が使うため残し、claude だけをPATHから外して
# 「必須CLI不足」を再現する（/usr/bin, /bin にはgit/jqはあるがclaudeは無い）。
read -r repo home < <(build_fake_repo "missing-required-cli")
out6="$(CLAUDE_DIR="${home}/.claude" HOME="${home}" PATH="/usr/bin:/bin" "${BASH_BIN}" "${repo}/installer/install.sh" 2>&1)"
rc6=$?
assert_rc "claude CLI不足: exit 1" 1 "${rc6}"
assert_contains "claude CLI不足: エラーメッセージ" "${out6}" "必須CLIが見つかりません: claude"
assert_contains "claude CLI不足: installHintが出る" "${out6}" "docs.claude.com"
if [ -e "${home}/.claude/rules" ]; then
  echo "FAIL: prereq不足なのにsymlink作成まで進んでしまった"
  fail=$((fail + 1))
else
  echo "PASS: prereq不足時はsymlink作成まで進まない"
  pass=$((pass + 1))
fi

echo "=== ⑦: settings.jsonが既に存在する場合は自動変更せずマージ手順を案内 ==="

read -r repo home < <(build_fake_repo "settings-exists")
mkdir -p "${home}/.claude"
echo '{"model": "既存の設定"}' > "${home}/.claude/settings.json"
out7="$(run_install "${repo}" "${home}")"
rc7=$?
assert_rc "settings.json既存時: exit 0" 0 "${rc7}"
assert_contains "settings.json既存時: 自動変更しない旨のログ" "${out7}" "自動変更しません"
assert_contains "settings.json既存時: jq -s マージ手順の案内" "${out7}" "jq -s"
existing_model="$(jq -r '.model' "${home}/.claude/settings.json")"
if [ "${existing_model}" = "既存の設定" ]; then
  echo "PASS: settings.jsonの既存内容は書き換わらない"
  pass=$((pass + 1))
else
  echo "FAIL: settings.jsonの既存内容が上書きされた (実際: ${existing_model})"
  fail=$((fail + 1))
fi

echo "=== ⑧: superpowersの既存cloneがlockと不一致な場合はfetch+checkoutで追従 ==="

# origin側に2つ目のコミットを積み、lockは新しい方を指すようにしたうえで、
# 「旧コミットのまま」既にcloneされている状態を再現する。
SUPERPOWERS_ORIGIN_SHA_OLD="${SUPERPOWERS_ORIGIN_SHA}"
echo "2nd commit" >> "${SUPERPOWERS_ORIGIN}/dummy-skill.md"
git -C "${SUPERPOWERS_ORIGIN}" add dummy-skill.md
git -C "${SUPERPOWERS_ORIGIN}" commit --quiet -m "2nd commit"
SUPERPOWERS_ORIGIN_SHA_NEW="$(git -C "${SUPERPOWERS_ORIGIN}" rev-parse HEAD)"

read -r repo home < <(build_fake_repo "superpowers-drift")
git clone --quiet "file://${SUPERPOWERS_ORIGIN}" "${home}/.claude/plugins/superpowers"
git -C "${home}/.claude/plugins/superpowers" checkout --quiet "${SUPERPOWERS_ORIGIN_SHA_OLD}"
printf '%s' "${SUPERPOWERS_ORIGIN_SHA_NEW}" > "${repo}/installer/superpowers.lock"

out8="$(run_install "${repo}" "${home}")"
rc8=$?
assert_rc "superpowers追従: exit 0" 0 "${rc8}"
sp_sha8="$(git -C "${home}/.claude/plugins/superpowers" rev-parse HEAD)"
if [ "${sp_sha8}" = "${SUPERPOWERS_ORIGIN_SHA_NEW}" ]; then
  echo "PASS: 既存cloneが新しいlock SHAへfetch+checkoutされる"
  pass=$((pass + 1))
else
  echo "FAIL: 既存cloneのSHAが更新されない (期待=${SUPERPOWERS_ORIGIN_SHA_NEW} 実際=${sp_sha8})"
  fail=$((fail + 1))
fi

echo "----"
echo "pass=${pass} fail=${fail}"
[ "${fail}" -eq 0 ]
