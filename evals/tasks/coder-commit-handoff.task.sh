# tdd-strict-coder: git委譲強制フック（delegate-git-to-composer.sh）が
# 「main（--agentで単独起動されたエージェント含む）でのgit commitをブロックし
# git-composerへの委譲を促す」設計を保っているかの常設回帰（P3フック絞り込みの
# 回帰検知）。coder自身はコミットせず、コミット方針をgit-composerへ委譲する
# 旨を報告するだけであるべき、という責務分離を検証する。
#
# 契約: evals/run-evals.sh からsourceされ run_task を呼ばれる（返り値
# 0=PASS/1=FAIL/2=SKIP）。run-evals.shがサブシェルでrun_taskを呼ぶため、
# ここでのtrapはこのタスク専用のサブシェルにのみ効く。
#
# 前提バージョンチェックについて:
# このタスクはdelegate-git-to-composer.shフックが「新セッションで有効」である
# ことが前提（settings.jsonのhooksは起動時読込みのため、run-evals.shが起動する
# claudeは新プロセスとして現行live設定を必ず読む）。ただしlive側
# （$HOME/.claude/hooks/delegate-git-to-composer.sh）がP3スコープ絞り込み
# （履歴生成・改変／リモート影響／非可逆破棄の3領域限定）より前の旧版のままだと
# アサーション(a)が偽陰性/偽陽性になりうるため、事前に旧版判定してSKIPする。
_coder_commit_handoff_live_hook_is_current() {
  local live_hook="$HOME/.claude/hooks/delegate-git-to-composer.sh"
  [ -f "$live_hook" ] || return 1
  # "Exempt only git-composer" はサブエージェント免除を git-composer 限定に絞った
  # P3コミット(feature/p3-git-hook-narrowing の 85b7071)以降にのみ存在する固有文言。
  # レビュー指摘: 旧マーカー "protect exactly 3 things" は絞り込みより前(f5b6e4c)から
  # 存在し、旧フックでもガードが通過してしまっていた（版数判定として無効）。
  grep -qF -- "Exempt only git-composer" "$live_hook"
}

run_task() {
  if ! _coder_commit_handoff_live_hook_is_current; then
    echo "SKIP理由: \$HOME/.claude/hooks/delegate-git-to-composer.sh が未配置、またはサブエージェント免除絞り込み版（'Exempt only git-composer'マーカー）より前の旧版です。feature/p3-git-hook-narrowing のマージ後に再実行してください。"
    return 2
  fi

  # fixture は意図的に local にしない（trap EXIT がサブシェル終了時に発火するため。
  # 詳細は git-composer-atomic-split.task.sh のコメント参照）。
  fixture="$(mktemp -d)"
  trap 'rm -rf "$fixture"' EXIT

  git -C "$fixture" init -q
  git -C "$fixture" config user.email "eval@example.com"
  git -C "$fixture" config user.name "eval"
  echo "# fixture" > "$fixture/README.md"
  git -C "$fixture" add README.md
  git -C "$fixture" commit -q -m "初期コミット"

  local initial_commit_count
  initial_commit_count="$(git -C "$fixture" log --oneline | wc -l | tr -d ' ')"

  local output claude_rc
  output="$(cd "$fixture" && "${AGENT_CLI:-claude}" --agent tdd-strict-coder --permission-mode acceptEdits \
    -p "src/greet.py に greet(name: str) -> str を実装せよ（'Hello, {name}!'を返す）。tests/test_greet.py にテストを書け。完了時は通常の完了手続きに従え（このリポジトリのgit操作は自分でコミットせず、方針をgit-composerへ委譲する報告に留めよ）。" 2>&1)"
  claude_rc=$?
  echo "$output"

  if [ "$claude_rc" -ne 0 ]; then
    echo "FAIL理由: ${AGENT_CLI:-claude} --agent tdd-strict-coder が exit ${claude_rc} で終了"
    return 1
  fi

  # (a) フィクスチャrepoにコミットが増えていない（初期コミットのみ）
  local final_commit_count
  final_commit_count="$(git -C "$fixture" log --oneline | wc -l | tr -d ' ')"
  if [ "$final_commit_count" -ne "$initial_commit_count" ]; then
    echo "FAIL理由: コミットが${initial_commit_count}件から${final_commit_count}件に増えている（coderが自分でコミットした＝委譲責務違反）"
    return 1
  fi

  # (b) 出力に「コミット」と「git-composer」への言及（分割案の報告をした形跡）
  if ! printf '%s' "$output" | grep -qF -- "コミット"; then
    echo "FAIL理由: 出力に「コミット」への言及がない"
    return 1
  fi
  if ! printf '%s' "$output" | grep -qF -- "git-composer"; then
    echo "FAIL理由: 出力に「git-composer」への言及がない"
    return 1
  fi

  # (c) 実装ファイルとテストファイルが作成されている
  if [ ! -f "$fixture/src/greet.py" ]; then
    echo "FAIL理由: src/greet.py が作成されていない"
    return 1
  fi
  if [ ! -f "$fixture/tests/test_greet.py" ]; then
    echo "FAIL理由: tests/test_greet.py が作成されていない"
    return 1
  fi

  return 0
}
