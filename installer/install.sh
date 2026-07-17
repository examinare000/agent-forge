#!/usr/bin/env bash
# agent-forge 頒布用インストーラ。任意の clone 位置から実行できる
# （require_repo_at_canonical_path 相当の固定パス前提は持たない）。
# 既定（引数なし）: インストール実行。--check / --force / --uninstall を持つ。
set -euo pipefail

CHECK_MODE=false
FORCE_MODE=false
UNINSTALL_MODE=false

usage() {
  cat <<'EOF'
使い方: install.sh [--check] [--force] [--uninstall]

  --check        doctorモード（read-only）。~/.claude の状態を検査し、異常があれば exit 1
  --force        symlink期待位置に実ファイル/別リンクがある場合、置換を許可する
  --uninstall    このインストーラが張ったsymlinkと .core-install.json のみ除去する
  -h, --help     このヘルプを表示
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_MODE=true ;;
    --force) FORCE_MODE=true ;;
    --uninstall) UNINSTALL_MODE=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "不明な引数です: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

INSTALL_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./lib/common.sh
source "${INSTALL_SH_DIR}/lib/common.sh"

MANIFEST_JSON="${REPO_ROOT}/installer/manifest.json"
if [ ! -f "${MANIFEST_JSON}" ]; then
  log_error "manifest.json が見つかりません: ${MANIFEST_JSON}"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  log_error "jq が見つかりません。manifest.json の読み込みに必須です"
  exit 1
fi
jq empty "${MANIFEST_JSON}" || {
  log_error "manifest.json が不正な JSON です"
  exit 1
}

# manifest.json内の ${REPO_ROOT} ${CLAUDE_DIR} トークンを実値へ展開する。
expand_tokens() {
  local s="$1"
  s="${s//\$\{REPO_ROOT\}/${REPO_ROOT}}"
  s="${s//\$\{CLAUDE_DIR\}/${CLAUDE_DIR}}"
  printf '%s' "${s}"
}

# --- linkEntries（パラレル配列。bash 3.2には連想配列が無いため） -------------
LINK_NAMES=()
LINK_REPO_PATHS=()
LINK_CLAUDE_PATHS=()
while IFS=$'\t' read -r name repo_path claude_path; do
  LINK_NAMES+=("${name}")
  LINK_REPO_PATHS+=("${repo_path}")
  LINK_CLAUDE_PATHS+=("${claude_path}")
done < <(jq -r '.linkEntries[] | [.name, .repoPath, .claudePath] | @tsv' "${MANIFEST_JSON}")

REQUIRED_PREREQS=()
while IFS= read -r line; do
  REQUIRED_PREREQS+=("${line}")
done < <(jq -r '.prereqs.required[]' "${MANIFEST_JSON}")

OPTIONAL_PREREQS=()
while IFS= read -r line; do
  OPTIONAL_PREREQS+=("${line}")
done < <(jq -r '.prereqs.optional[]' "${MANIFEST_JSON}")

SUPERPOWERS_URL="$(jq -r '.repos.superpowers.url' "${MANIFEST_JSON}")"
SUPERPOWERS_DIR="$(expand_tokens "$(jq -r '.repos.superpowers.dir' "${MANIFEST_JSON}")")"
SUPERPOWERS_LOCK_FILE="$(expand_tokens "$(jq -r '.repos.superpowers.lockFile' "${MANIFEST_JSON}")")"

# Linuxは公式検証対象外だが、bash実装自体はdarwinとほぼ同じコマンド体系
# （brew系ではないが）で動く可能性が高いため即failさせず、manifest.jsonに
# 専用エントリを持たないOSではdarwinのヒントをbest-effortとして流用する
# （Windowsはinstall.ps1側の管轄で、この分岐には来ない）。
if [ "$(uname -s)" != "Darwin" ]; then
  log_warn "Linux/その他OSは公式サポート外です（best-effort）"
fi

install_hint_for() {
  local name="$1" os_key
  case "$(uname -s)" in
    Darwin) os_key="darwin" ;;
    *) os_key="darwin" ;;
  esac
  jq -r --arg os "${os_key}" --arg name "${name}" '.prereqs.installHints[$os][$name] // ""' "${MANIFEST_JSON}"
}

# --- prereq -------------------------------------------------------------
check_prereqs_or_fail() {
  log_info "--- prereq検査 ---"
  local missing=0 name hint
  for name in "${REQUIRED_PREREQS[@]}"; do
    if command -v "${name}" >/dev/null 2>&1; then
      log_info "  必須CLI検出: ${name}"
    else
      hint="$(install_hint_for "${name}")"
      log_error "  必須CLIが見つかりません: ${name} (${hint})"
      missing=1
    fi
  done
  if [ "${#OPTIONAL_PREREQS[@]}" -gt 0 ]; then
    for name in "${OPTIONAL_PREREQS[@]}"; do
      if command -v "${name}" >/dev/null 2>&1; then
        log_info "  任意CLI検出: ${name}"
      else
        log_warn "  任意CLIが見つかりません（続行します）: ${name}"
      fi
    done
  fi
  if [ "${missing}" -eq 1 ]; then
    log_error "必須CLIが不足しているため中断します"
    exit 1
  fi
}

# --- symlink作成 ----------------------------------------------------------
link_entries() {
  log_info "--- ~/.claude へのsymlink作成 ---"
  mkdir -p "${CLAUDE_DIR}"
  local i name live repo
  for i in "${!LINK_NAMES[@]}"; do
    name="${LINK_NAMES[$i]}"
    live="${CLAUDE_DIR}/${LINK_CLAUDE_PATHS[$i]}"
    repo="${REPO_ROOT}/${LINK_REPO_PATHS[$i]}"
    mkdir -p "$(dirname "${live}")"

    if is_symlink_with_target "${live}" "${repo}"; then
      log_info "skip（既に正しいsymlink）: ${name}"
      continue
    fi

    if [ -L "${live}" ]; then
      if [ "${FORCE_MODE}" != "true" ]; then
        log_warn "${name} は別ターゲットを指すsymlinkです（現在: $(readlink "${live}")）。置換するには --force を指定してください"
        continue
      fi
      rm -f "${live}"
      ln -s "${repo}" "${live}"
      log_info "絶対パスsymlinkを張り替えました: ${name}"
      continue
    fi

    if [ -e "${live}" ]; then
      if [ "${FORCE_MODE}" != "true" ]; then
        log_warn "${name} は実ファイル/ディレクトリです。上書きしません（置換するには --force を指定してください）"
        continue
      fi
      rm -rf "${live}"
      ln -s "${repo}" "${live}"
      log_info "実体を置換してsymlinkを作成しました: ${name}"
      continue
    fi

    ln -s "${repo}" "${live}"
    log_info "絶対パスsymlinkを作成しました: ${name} （${live} -> ${repo}）"
  done
}

# --- superpowers -----------------------------------------------------------
ensure_superpowers() {
  log_info "--- superpowers ---"
  local lock_sha
  lock_sha="$(tr -d '[:space:]' < "${SUPERPOWERS_LOCK_FILE}")"
  if [ ! -d "${SUPERPOWERS_DIR}/.git" ]; then
    log_info "cloneします: ${SUPERPOWERS_DIR}"
    mkdir -p "$(dirname "${SUPERPOWERS_DIR}")"
    git clone --quiet "${SUPERPOWERS_URL}" "${SUPERPOWERS_DIR}"
    log_info "lock済みSHAへ固定します: ${lock_sha}"
    git -C "${SUPERPOWERS_DIR}" checkout --quiet "${lock_sha}"
    return 0
  fi
  local current_sha
  current_sha="$(git -C "${SUPERPOWERS_DIR}" rev-parse HEAD)"
  if [ "${current_sha}" != "${lock_sha}" ]; then
    log_info "lock済みSHAへ合わせます（現在: ${current_sha} / lock: ${lock_sha}）"
    git -C "${SUPERPOWERS_DIR}" fetch --quiet origin
    git -C "${SUPERPOWERS_DIR}" checkout --quiet "${lock_sha}"
  else
    log_info "lock済みSHAと一致しています"
  fi
}

# --- settings配線 ----------------------------------------------------------
sync_settings() {
  log_info "--- settings.json ---"
  local live="${CLAUDE_DIR}/settings.json"
  local repo="${REPO_ROOT}/claude/settings.base.json"
  if [ -e "${live}" ]; then
    log_info "settings.json は既に存在するため自動変更しません"
    log_info "差分を取り込みたい場合は次のコマンドで手動マージしてください:"
    log_info "  jq -s '.[0] * .[1]' '${live}' '${repo}' > '${live}.merged' && mv '${live}.merged' '${live}'"
    return 0
  fi
  if [ ! -f "${repo}" ]; then
    log_warn "settings.base.json が見つからないためskipします: ${repo}"
    return 0
  fi
  cp "${repo}" "${live}"
  log_info "settings.json を settings.base.json から作成しました"
}

# --- インストール記録 --------------------------------------------------------
resolve_version() {
  (cd "${REPO_ROOT}" && git describe --tags --always 2>/dev/null) || echo "dev"
}

write_install_record() {
  log_info "--- インストール記録 ---"
  local record="${CLAUDE_DIR}/.core-install.json"
  local version installed_at
  version="$(resolve_version)"
  installed_at="$(date +%s)"
  jq -n --arg repoRoot "${REPO_ROOT}" --arg version "${version}" --argjson installedAt "${installed_at}" \
    '{repoRoot: $repoRoot, version: $version, installedAt: $installedAt}' > "${record}"
  log_info "書き込みました: ${record}"
}

# --- doctor（--check） ------------------------------------------------------
doctor_check_link_entries() {
  log_info "--- ~/.claude へのsymlink健全性 ---"
  local i name live repo
  for i in "${!LINK_NAMES[@]}"; do
    name="${LINK_NAMES[$i]}"
    live="${CLAUDE_DIR}/${LINK_CLAUDE_PATHS[$i]}"
    repo="${REPO_ROOT}/${LINK_REPO_PATHS[$i]}"
    if is_symlink_with_target "${live}" "${repo}"; then
      report_ok "${name}: 正しい絶対パスsymlink（${live} -> ${repo}）"
    elif is_clobbered_by_real_entry "${live}"; then
      report_fail "${name}: DRIFT: clobbered（symlink期待位置に実ファイル/ディレクトリが存在）"
    elif [ -L "${live}" ]; then
      report_fail "${name}: 別ターゲットを指すsymlinkです（$(readlink "${live}")）"
    else
      report_fail "${name}: 存在しません"
    fi
  done
}

doctor_check_prereqs() {
  log_info "--- prereq CLI ---"
  local name hint
  for name in "${REQUIRED_PREREQS[@]}"; do
    if command -v "${name}" >/dev/null 2>&1; then
      report_ok "${name}: 検出"
    else
      hint="$(install_hint_for "${name}")"
      report_fail "${name}: 未検出（必須, ${hint}）"
    fi
  done
  if [ "${#OPTIONAL_PREREQS[@]}" -gt 0 ]; then
    for name in "${OPTIONAL_PREREQS[@]}"; do
      if command -v "${name}" >/dev/null 2>&1; then
        report_ok "${name}: 検出（任意）"
      else
        report_warn "${name}: 未検出（任意）"
      fi
    done
  fi
}

doctor_check_superpowers() {
  log_info "--- superpowers ---"
  if [ ! -d "${SUPERPOWERS_DIR}/.git" ]; then
    report_fail "superpowersが存在しません: ${SUPERPOWERS_DIR}"
    return 0
  fi
  if [ ! -f "${SUPERPOWERS_LOCK_FILE}" ]; then
    report_warn "superpowers.lock が存在しません"
    return 0
  fi
  local lock_sha current_sha
  lock_sha="$(tr -d '[:space:]' < "${SUPERPOWERS_LOCK_FILE}")"
  current_sha="$(git -C "${SUPERPOWERS_DIR}" rev-parse HEAD 2>/dev/null || true)"
  if [ "${current_sha}" = "${lock_sha}" ]; then
    report_ok "superpowers: lock済みSHAと一致 (${current_sha})"
  else
    report_warn "superpowers: SHA不一致（現在: ${current_sha} / lock: ${lock_sha}）"
  fi
}

doctor_check_settings() {
  log_info "--- settings.json ---"
  if [ -f "${CLAUDE_DIR}/settings.json" ]; then
    report_ok "settings.json: 存在します"
  else
    report_fail "settings.json: 存在しません"
  fi
}

doctor_check_install_record() {
  log_info "--- インストール記録 ---"
  if [ -f "${CLAUDE_DIR}/.core-install.json" ]; then
    report_ok ".core-install.json: 存在します"
  else
    report_warn ".core-install.json: 存在しません（install.shが未実行の可能性）"
  fi
}

doctor() {
  log_info "=== doctor（read-only チェック） ==="
  doctor_check_link_entries
  doctor_check_prereqs
  doctor_check_superpowers
  doctor_check_settings
  doctor_check_install_record

  echo ""
  log_info "=== サマリ: WARN ${DOCTOR_WARN_COUNT}件 / FAIL ${DOCTOR_FAIL_COUNT}件 ==="
  if [ "${DOCTOR_FAIL_COUNT}" -gt 0 ]; then
    log_error "doctor: FAILがあります"
    exit 1
  fi
  log_info "doctor: FAILなし"
}

# --- uninstall ---------------------------------------------------------------
# 本インストーラが張ったsymlinkと.core-install.jsonのみ除去する。実ファイル
# （settings.json・superpowers clone等）や、symlinkでない先住実体には触れない。
uninstall_entries() {
  log_info "--- インストーラが張ったsymlinkの除去 ---"
  local i name live repo
  for i in "${!LINK_NAMES[@]}"; do
    name="${LINK_NAMES[$i]}"
    live="${CLAUDE_DIR}/${LINK_CLAUDE_PATHS[$i]}"
    repo="${REPO_ROOT}/${LINK_REPO_PATHS[$i]}"
    if is_symlink_with_target "${live}" "${repo}"; then
      rm -f "${live}"
      log_info "symlinkを除去しました: ${name}"
    elif [ -L "${live}" ]; then
      log_warn "${name} は別ターゲットを指すsymlinkのため触れません（$(readlink "${live}")）"
    elif [ -e "${live}" ]; then
      log_warn "${name} は実ファイル/ディレクトリのため触れません"
    else
      log_info "${name} は既に存在しません（skip）"
    fi
  done

  local record="${CLAUDE_DIR}/.core-install.json"
  if [ -f "${record}" ]; then
    rm -f "${record}"
    log_info "インストール記録を除去しました: ${record}"
  fi
  log_info "アンインストール完了（symlink管理外の実ファイル・superpowers cloneは残しています）"
}

main_install() {
  check_prereqs_or_fail
  link_entries
  ensure_superpowers
  sync_settings
  write_install_record
  log_info "インストール完了。'install.sh --check' で状態を確認できます"
}

if [ "${INSTALL_SH_NO_MAIN:-false}" != "true" ]; then
  if [ "${CHECK_MODE}" = "true" ]; then
    doctor
  elif [ "${UNINSTALL_MODE}" = "true" ]; then
    uninstall_entries
  else
    main_install
  fi
fi
