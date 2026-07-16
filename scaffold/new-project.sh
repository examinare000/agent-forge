#!/usr/bin/env bash
# 新規プロジェクトの雛形を生成する（agent-forge導入者向けのブートストラップ支援）。
#
# 背景: ~/git/agentDevTemplate/scripts/create_new_project.sh の設計（絶対パスsymlink正本方式・
# 冪等・既存の編集済みファイルは上書きしない）を踏襲しつつ、agent-forgeの配布モデル
# （エージェント定義・スキルは installer 経由で ~/.claude にグローバル導入する）に合わせて
# 「copyモード（初心者向け既定・自己完結）」と「linkモード（上級者向け・~/.claude 追随）」の
# 2モードを持つ。
#
# なぜ dist/AGENTS.md・GEMINI.md・.mcp.json・settings.local.json・scripts/check-*.sh・
# README・.gitignore は copy/link どちらのモードでも常にコピーなのか:
# これらは (a) ~/.claude 側に同名の symlink 先が存在しない（installer の
# linkEntries に無い）、または (b) 本質的にプロジェクト固有の編集可能設定であり、
# symlink化するとテンプレ更新やclone消失で壊れる。symlink化するのは
# 「installerが実際に~/.claude配下へ張った実体」がある CLAUDE.md と
# .claude/rules/{testing,frontend,docker}.md のみに限定する。
#
# 使い方:   bash scaffold/new-project.sh <作成先ディレクトリ> [--name N] [--mode copy|link]
# 終了コード: 0=成功 / 1=失敗
set -euo pipefail

usage() {
  cat <<'EOF'
使い方: new-project.sh <作成先ディレクトリ> [--name N] [--mode copy|link]

  --name N       プロジェクト名（既定: 作成先ディレクトリのベース名）
  --mode MODE    copy（既定・初心者向け・自己完結）| link（上級者向け・~/.claude追随）
  -h, --help     このヘルプを表示
EOF
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

DEST_RAW="$1"
shift
PROJ_NAME=""
MODE="copy"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)
      PROJ_NAME="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
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
done

case "$MODE" in
  copy | link) ;;
  *)
    echo "エラー: --mode は copy か link のみ対応です: $MODE" >&2
    exit 1
    ;;
esac

SCAFFOLD_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../installer/lib/common.sh
# symlink処理（is_symlink_with_target等）はinstaller/lib/common.shのヘルパを再利用する
# （installer側とscaffold側で同じ判定ロジックを二重実装しない）。
source "${SCAFFOLD_SH_DIR}/../installer/lib/common.sh"

TEMPLATES_DIR="${SCAFFOLD_SH_DIR}/templates"

mkdir -p "${DEST_RAW}"
DEST="$(cd "${DEST_RAW}" && pwd -P)"
[ -z "${PROJ_NAME}" ] && PROJ_NAME="$(basename "${DEST}")"

if [ "${DEST}" = "${REPO_ROOT}" ]; then
  log_error "作成先が agent-forge リポジトリ自身です。別ディレクトリを指定してください: ${DEST}"
  exit 1
fi

# --- 既存gitリポジトリへのnested git init防止 --------------------------------
# DEST自身が既にgitリポジトリ（.git所有）なら後段の git init は冪等にskipされる。
# そうでない場合に限り、DESTが「既存の別リポジトリの内部」に位置していないかを検査する
# （検査だけを早期に行い、実際の git init は最後に実行する）。
if [ ! -d "${DEST}/.git" ]; then
  existing_toplevel="$(cd "${DEST}" && git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "${existing_toplevel}" ]; then
    log_error "作成先(${DEST})は既存のgitリポジトリの内部です（${existing_toplevel}）。既存repo内へのnested git initは拒否します。別ディレクトリを指定してください。"
    exit 1
  fi
fi

if [ "${MODE}" = "link" ] && [ ! -d "${CLAUDE_DIR}/rules" ]; then
  log_error "linkモードには agent-forge の導入（~/.claude/rules）が必要です。先に 'forge install' を実行してください。"
  exit 1
fi

log_info "新規プロジェクトをセットアップします: ${DEST} (name: ${PROJ_NAME}, mode: ${MODE})"

# --- ヘルパ -----------------------------------------------------------------

# プロジェクト固有の初期コピー。既存（編集済みの可能性）は上書きしない。
copy_once() {
  local src="$1" dst="$2"
  if [ -e "${dst}" ]; then
    log_info "skip(既存): ${dst#"${DEST}"/}"
    return 0
  fi
  if [ ! -e "${src}" ]; then
    log_error "テンプレートが見つかりません: ${src}"
    return 1
  fi
  mkdir -p "$(dirname "${dst}")"
  cp "${src}" "${dst}"
  log_info "copy: ${dst#"${DEST}"/}"
}

# {{PROJECT_NAME}} を置換しつつコピーする（既存は上書きしない）。
render_copy_once() {
  local src="$1" dst="$2" content
  if [ -e "${dst}" ]; then
    log_info "skip(既存): ${dst#"${DEST}"/}"
    return 0
  fi
  if [ ! -e "${src}" ]; then
    log_error "テンプレートが見つかりません: ${src}"
    return 1
  fi
  content="$(cat "${src}")"
  content="${content//\{\{PROJECT_NAME\}\}/${PROJ_NAME}}"
  mkdir -p "$(dirname "${dst}")"
  printf '%s\n' "${content}" > "${dst}"
  log_info "generate: ${dst#"${DEST}"/}"
}

# 絶対パスsymlinkを冪等に作成する（common.shのis_symlink_with_target等を利用）。
link_abs() {
  local target="$1" link="$2"
  if [ ! -e "${target}" ]; then
    log_error "symlink参照先が存在しません: ${target}"
    return 1
  fi
  mkdir -p "$(dirname "${link}")"
  if is_symlink_with_target "${link}" "${target}"; then
    log_info "skip（既に正しいsymlink）: ${link#"${DEST}"/}"
    return 0
  fi
  if is_clobbered_by_real_entry "${link}"; then
    log_error "${link} が symlink ではない実体として存在します。手動で確認してください。"
    return 1
  fi
  rm -f "${link}"
  ln -s "${target}" "${link}"
  log_info "絶対パスsymlinkを作成しました: ${link#"${DEST}"/} -> ${target}"
}

# --- 1) 常にコピーする成果物（copy/link共通） ---------------------------------
log_info "--- dist/ からホスト向け指示書をコピー ---"
copy_once "${REPO_ROOT}/dist/AGENTS.md" "${DEST}/AGENTS.md"
copy_once "${REPO_ROOT}/dist/GEMINI.md" "${DEST}/GEMINI.md"

# dist/codex-agents/*.toml は Codex CLI がプロジェクト単位で読む資産（.codex/agents/）。
# installerは~/.claudeにcodex資産を置かない（linkEntriesに無い）ためsymlink先が存在せず、
# copy/linkどちらのモードでもcopy_onceで実体コピーする。dist/codex-plugin/はプロジェクト単位でなく
# Codexのプラグイン機構側で読み込むものなのでここでは対象外。
for toml in "${REPO_ROOT}"/dist/codex-agents/*.toml; do
  [ -e "${toml}" ] || continue
  copy_once "${toml}" "${DEST}/.codex/agents/$(basename "${toml}")"
done

log_info "--- プロジェクト固有設定をコピー ---"
copy_once "${TEMPLATES_DIR}/mcp.json.template" "${DEST}/.mcp.json"
copy_once "${TEMPLATES_DIR}/settings.local.json.template" "${DEST}/.claude/settings.local.json"
copy_once "${TEMPLATES_DIR}/gitignore.template" "${DEST}/.gitignore"

log_info "--- 補助スクリプトをコピー ---"
copy_once "${TEMPLATES_DIR}/scripts/check-agent-assets.sh" "${DEST}/scripts/check-agent-assets.sh"
copy_once "${TEMPLATES_DIR}/scripts/check-docs.sh" "${DEST}/scripts/check-docs.sh"
chmod +x "${DEST}/scripts/check-agent-assets.sh" "${DEST}/scripts/check-docs.sh" 2>/dev/null || true

if [ ! -e "${DEST}/README.md" ]; then
  cat > "${DEST}/README.md" <<EOF
# ${PROJ_NAME}

agent-forge を基盤にセットアップした開発プロジェクト（mode: ${MODE}）。

## エージェント挙動の正本

エージェント指示書（ルール・スキル・サブエージェント定義）は agent-forge が
\`~/.claude/\` へグローバル導入する。未導入の場合は先に \`forge install\` を実行する。

- 状態確認: \`forge check\` または \`bash scripts/check-agent-assets.sh\`
EOF
  log_info "generate: README.md"
else
  log_info "skip(既存): README.md"
fi

# --- 2) モード依存の成果物（CLAUDE.md・.claude/rules/*） ----------------------
if [ "${MODE}" = "copy" ]; then
  log_info "--- copyモード: CLAUDE.md / .claude/rules/ を自己完結コピー ---"
  render_copy_once "${TEMPLATES_DIR}/CLAUDE.md" "${DEST}/CLAUDE.md"
  copy_once "${TEMPLATES_DIR}/claude-rules/testing.md" "${DEST}/.claude/rules/testing.md"
  copy_once "${TEMPLATES_DIR}/claude-rules/frontend.md" "${DEST}/.claude/rules/frontend.md"
  copy_once "${TEMPLATES_DIR}/claude-rules/docker.md" "${DEST}/.claude/rules/docker.md"
else
  log_info "--- linkモード: CLAUDE.md / .claude/rules/ を ~/.claude/ へ絶対symlink ---"
  link_abs "${CLAUDE_DIR}/CLAUDE.core.md" "${DEST}/CLAUDE.md"
  link_abs "${CLAUDE_DIR}/rules/11-testing-strategy.md" "${DEST}/.claude/rules/testing.md"
  link_abs "${CLAUDE_DIR}/rules/15-frontend-design.md" "${DEST}/.claude/rules/frontend.md"
  link_abs "${CLAUDE_DIR}/rules/70-docker-environments.md" "${DEST}/.claude/rules/docker.md"
fi

# --- 3) git初期化（mainのみ。developは作らない） -------------------------------
if [ -d "${DEST}/.git" ]; then
  log_info "既に git リポジトリのため初期化をスキップします。"
else
  log_info "--- git初期化（main） ---"
  git -C "${DEST}" init --quiet -b main
  # 初回スキャフォールド完了直後の状態を1コミットとして記録する（移植元
  # agentDevTemplate の create_new_project.sh と同挙動）。以後の開発差分と生成物を
  # 明確に切り分け、生成直後に `git status` が差分ゼロの状態から開発を始められるようにする。
  # 上のgit init分岐と同じ枝でのみ実行するため、既存repoへ本コマンドがコミットを
  # 追加することはない（既存repoスキップ時はコミットもスキップされる）。
  # commitはuser.name/user.email未設定環境で失敗しうるため、移植元同様に失敗を
  # スクリプト全体の失敗として扱わず警告に留める（scaffold自体は生成済みのため）。
  git -C "${DEST}" add -A
  if ! git -C "${DEST}" commit --quiet -m "agent-forgeによる初期スキャフォールド"; then
    log_info "注意: 初期コミットに失敗しました（git user.name/user.emailが未設定の可能性）。手動でコミットしてください。"
  fi
fi

log_info "完了: ${DEST}"
log_info "次の一手: cd \"${DEST}\" && bash scripts/check-agent-assets.sh で状態を確認してください。"
exit 0
