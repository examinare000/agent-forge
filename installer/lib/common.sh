#!/usr/bin/env bash
# installer/ 配下のスクリプトが共有する基礎関数群。
# ログ出力・symlink検査・REPO_ROOT自己解決など、install.sh単体では
# 読みにくくなる補助ロジックをここに集約する。
set -euo pipefail

# sh経由(POSIXモード)ではプロセス置換<(...)が後続の関数定義の時点で構文エラーに
# なるため、bash実行を必須にする。install.sh は関数定義より先にここをsourceする。
if [ -z "${BASH_VERSION:-}" ]; then
  echo "エラー: bash で実行してください（例: bash installer/install.sh）" >&2
  exit 1
fi
case ":${SHELLOPTS:-}:" in
  *:posix:*)
    echo "エラー: sh ではなく bash で実行してください（例: bash installer/install.sh）" >&2
    exit 1 ;;
esac

# Git BashなどMSYS環境の `ln -s` はNTFS symlink権限が無いと黙ってコピーを
# 作ってしまい、後続のsymlink前提ロジック（doctor判定・uninstall等）が
# サイレントに壊れる。実体コピーが作られてから気づくのを防ぐため、
# bashエントリポイントの入口で確実に弾く（Windowsは install.ps1 を使う）。
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    echo "エラー: WindowsではGit Bash経由のinstallをサポートしません（MSYSのln -sはsymlinkでなくコピーを作るため）。" >&2
    echo "PowerShell 7 で実行してください: pwsh -File installer\\install.ps1" >&2
    exit 1 ;;
esac

# 二重source時に副作用（REPO_ROOT再計算など）を起こさないためのガード。
if [ -n "${COMMON_SH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
COMMON_SH_LOADED=1

# --- 色付きログ -----------------------------------------------------------
# 非ttyへの出力（ログファイル等）でエスケープシーケンスが混入しないよう、
# tty接続時のみ色を使う。
if [ -t 1 ]; then
  COMMON_COLOR_RED=$'\033[31m'
  COMMON_COLOR_YELLOW=$'\033[33m'
  COMMON_COLOR_GREEN=$'\033[32m'
  COMMON_COLOR_RESET=$'\033[0m'
else
  COMMON_COLOR_RED=""
  COMMON_COLOR_YELLOW=""
  COMMON_COLOR_GREEN=""
  COMMON_COLOR_RESET=""
fi

log_info() {
  printf '%s[INFO]%s %s\n' "${COMMON_COLOR_GREEN}" "${COMMON_COLOR_RESET}" "$*"
}

log_warn() {
  printf '%s[WARN]%s %s\n' "${COMMON_COLOR_YELLOW}" "${COMMON_COLOR_RESET}" "$*" >&2
}

log_error() {
  printf '%s[ERROR]%s %s\n' "${COMMON_COLOR_RED}" "${COMMON_COLOR_RESET}" "$*" >&2
}

# doctor（--check）の集計カウンタ。install.sh が最後にこれを見てexitコードを決める。
DOCTOR_FAIL_COUNT=0
DOCTOR_WARN_COUNT=0

report_ok() {
  printf '  %s[OK]%s   %s\n' "${COMMON_COLOR_GREEN}" "${COMMON_COLOR_RESET}" "$*"
}

report_warn() {
  printf '  %s[WARN]%s %s\n' "${COMMON_COLOR_YELLOW}" "${COMMON_COLOR_RESET}" "$*"
  DOCTOR_WARN_COUNT=$((DOCTOR_WARN_COUNT + 1))
}

report_fail() {
  printf '  %s[FAIL]%s %s\n' "${COMMON_COLOR_RED}" "${COMMON_COLOR_RESET}" "$*"
  DOCTOR_FAIL_COUNT=$((DOCTOR_FAIL_COUNT + 1))
}

# --- パス解決 ---------------------------------------------------------------
# common.sh 自身の物理パスから逆算する（呼び出し元の置き場所や配布先の
# clone位置に依存させないため。require_repo_at_canonical_path 相当の固定パス
# 前提は持たない — 頒布用インストーラは任意の clone 位置で動く必要がある）。
# common.sh は installer/lib/ にあるので2階層上がrepo root。
COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${COMMON_SH_DIR}/../.." && pwd -P)"

# テストから差し替え可能にするため、既に環境変数で与えられていればそれを使う。
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

# --- symlink検査ヘルパ ------------------------------------------------------

# $1: パス, $2: 期待するsymlinkターゲット（readlinkの生の返り値と一致するか）
is_symlink_with_target() {
  local path="$1"
  local expected_target="$2"
  [ -L "${path}" ] && [ "$(readlink "${path}")" = "${expected_target}" ]
}

# symlinkだが実体が存在しない（壊れている）か
is_broken_symlink() {
  local path="$1"
  [ -L "${path}" ] && [ ! -e "${path}" ]
}

# 期待するsymlink位置に実ファイル/実ディレクトリが居座っていないか
# （atomic-write事故等でsymlinkが実体に化けた「DRIFT: clobbered」状態の検出）
is_clobbered_by_real_entry() {
  local path="$1"
  [ -e "${path}" ] && [ ! -L "${path}" ]
}
