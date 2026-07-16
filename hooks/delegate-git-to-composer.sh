#!/usr/bin/env bash
# PreToolUse(Bash) hook: force the MAIN agent to delegate MUTATING git/gh
# operations to the git-composer subagent.
#
# Why a hook: "always delegate git writes to git-composer" is a deterministic
# routing rule, so it belongs in a hook rather than a prompt the model may forget.
#
# Deadlock avoidance: hooks fire inside subagents too, and git-composer itself
# must run git/gh. The PreToolUse payload sets `agent_type` ONLY inside a
# subagent (empty for the main agent, verified empirically). So we exit early
# (allow) ONLY for git-composer. Other subagents keep read-only git access
# (status/diff/log etc. stay unblocked below) but are NOT exempt from the
# mutating-git gate: a Bash-capable worker reading untrusted content, holding
# private repo access, and able to reach the network (push / gh pr create) is
# a lethal-trifecta shape, so exempting "any subagent" was itself the bug.
# Since subagents cannot spawn subagents (no nesting), a blocked subagent
# cannot retry via "launch git-composer" — see the branched message below.
#
# Scope: protect exactly 3 things — (1) history creation/rewriting (where commit-
# message convention lives), (2) remote/external-facing effects, (3) irreversible
# destruction of work. Anything outside these 3 stays available to the main agent.
#
# Consequences of that principle, beyond plain read-only (status/diff/log/show/
# branch-list/gh ... view|list ...):
# - branch creation/switching (git switch [-c], git checkout -b/-B, git branch <new>)
#   — no atomicity/message judgment, and creation/switch never commits.
# - format-patch / request-pull — output-only (patch file / stdout), no history or
#   worktree effect.
# - apply — edits the worktree, equivalent to Edit/patch; no history/remote/
#   destruction risk of its own.
# - stash push/pop/apply/list/show/branch — stash is a reversible local shelf;
#   only `stash drop`/`stash clear` are irreversible destruction (blocked below).
# - merge/rebase/cherry-pick/am --abort — recovery of an in-progress operation,
#   the opposite of destruction; `--continue` stays blocked since it can create
#   a commit.
# - restore --staged (without --worktree/-W) — unstage only; the worktree itself
#   is untouched, so no irreversible destruction occurs.
# - pull --ff-only — cannot produce a merge commit or discard work, so no history/
#   destruction judgment is needed; plain pull / --rebase can still silently
#   create a merge commit or rewrite history, so they stay blocked.
#
# Everything else stays blocked: commit/push/reset/revert/add/rm/mv/clean/gc/
# prune/fast-import/stage, branch -d/-D/-m/-M/-c/-C, tag create/delete/force,
# checkout -- <path>, plain merge/rebase/cherry-pick/am, plain/--rebase pull,
# restore without --staged (or with --worktree), gh mutating verbs.
set -uo pipefail

input="$(cat)"

# Exempt only git-composer (prevents deadlock; it needs git/gh to do its job).
# Other subagents fall through to the same mutating-git gate as main.
agent_type="$(printf '%s' "$input" | jq -r '.agent_type // ""')"
[ "$agent_type" = "git-composer" ] && exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"

# is_mutating <segment> → return 0 if the segment is a state-changing git/gh call
is_mutating() {
  local s="$1" rest sub verb sub2
  case "$s" in
    git\ *)
      # strip git global options, then take the subcommand
      rest="$(printf '%s' "$s" | sed -E 's/^git( +-C +[^ ]+| +-c +[^ ]+| +--git-dir[= ][^ ]+| +--work-tree[= ][^ ]+)*//')"
      rest="${rest#"${rest%%[![:space:]]*}"}" # ltrim
      sub="$(printf '%s' "$rest" | awk '{print $1}')"
      case "$sub" in
        commit | push | reset | revert | add | rm | mv | clean | gc | prune | fast-import | stage)
          return 0 ;;
        pull) # --rebase can rewrite history even combined with --ff-only, so it blocks unconditionally and is checked first;
              # only when --rebase is absent does --ff-only's "no merge commit possible" guarantee hold
          printf '%s' "$rest" | grep -Eq -- '(^| )--rebase(=|$| )' && return 0
          printf '%s' "$rest" | grep -Eq -- '(^| )--ff-only($| )' && return 1
          return 0 ;;
        merge | rebase | cherry-pick | am) # --abort recovers an in-progress op (opposite of destruction); --continue can still create a
                                            # commit, so it stays blocked. Exact-match only (rest must be exactly "<sub> --abort") so
                                            # "--abort" appearing inside a quoted -m message, or trailing extra args, can't fool a
                                            # word-boundary scan into fail-open allow — any deviation fails closed (blocked).
          printf '%s' "$rest" | grep -Eq -- "^${sub}[[:space:]]+--abort[[:space:]]*\$" && return 1
          return 0 ;;
        restore) # --staged (without --worktree/-W) only unstages; the worktree itself is untouched, so no irreversible destruction occurs
          if printf '%s' "$rest" | grep -Eq -- '(^| )(--staged|-S)($| )'; then
            printf '%s' "$rest" | grep -Eq -- '(^| )(--worktree|-W)($| )' && return 0
            return 1
          fi
          return 0 ;;
        stash) # only drop/clear AS THE ACTUAL SUBCOMMAND are irreversible destruction; push/pop/apply/list/show/branch
               # stay reversible local shelf ops. Matched on the literal 2nd word (not a substring glob) so a
               # message/branch-name that merely contains "drop" (e.g. `stash push -m drop-old-work`) isn't
               # mistaken for the subcommand and fail-closed-blocked by accident.
          sub2="$(printf '%s' "$rest" | awk '{print $2}')"
          case "$sub2" in
            drop | clear) return 0 ;;
            *) return 1 ;;
          esac ;;
        branch) # delete/move/copy/force stay delegated; CREATION (`git branch <name>`)
                # is now allowed on main — it carries no atomicity/message judgment and
                # the branch-protection hook is unaffected (creation never commits).
          case "$rest" in
            *\ -d* | *\ -D* | *\ -m* | *\ -M* | *\ -c* | *\ -C* | *--delete* | *--move* | *--copy* | *--force*) return 0 ;;
          esac
          return 1 ;;
        tag) # mutating on create/delete/force; read-only on list
          case "$rest" in *\ -d* | *\ -a* | *\ -s* | *\ -f* | *--delete* | *--force*) return 0 ;; esac
          printf '%s' "$rest" | grep -Eq '^tag( +(-l|--list|-n[0-9]*|--sort=[^ ]+))* +[A-Za-z0-9._/]' && return 0
          return 1 ;;
        switch) return 1 ;; # switch never touches files; -c only CREATES a branch → allowed on main
        checkout) case "$rest" in *\ --\ *) return 0 ;; *) return 1 ;; esac ;; # only `checkout -- <path>` (destructive file revert) stays delegated; -b/-B/--orphan (branch creation) allowed
        *) return 1 ;;
      esac ;;
    gh\ *)
      # gh api with a write method/body is mutating; plain GET is read-only
      case "$s" in
        *\ api\ *)
          printf '%s' "$s" | grep -Eiq -- '-X +(POST|PUT|PATCH|DELETE)|--method +(POST|PUT|PATCH|DELETE)|(^| )(-f|--field|--raw-field|--input)( |=)' && return 0
          return 1 ;;
      esac
      rest="$(printf '%s' "$s" | sed -E 's/^gh +//')"
      verb="$(printf '%s' "$rest" | awk '{print $2}')"
      case "$verb" in
        create | merge | close | edit | comment | review | ready | delete | reopen | rename | transfer | lock | unlock | set | run | enable | disable | sync | add | remove | restore | approve | rebase | update | "import")
          return 0 ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

blocked=""
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}" # ltrim
  [ -z "$seg" ] && continue
  if is_mutating "$seg"; then
    blocked="$seg"
    break
  fi
done < <(printf '%s\n' "$cmd" | tr ';|&' '\n\n\n')

[ -z "$blocked" ] && exit 0

# Subagents cannot spawn subagents (no nesting), so the "launch git-composer via
# Agent tool" instruction below is unexecutable advice for them and would just
# invite a retry loop. Branch the message: non-git-composer subagents get told
# to stop and hand a commit plan back to the orchestrator instead.
if [ -n "$agent_type" ]; then
  cat >&2 <<EOF
🟠 サブエージェントは git/gh の変更操作を実行できない。この操作をリトライするな。
変更内容と論理変更単位のコミット計画（ファイル群+メッセージ案）を最終報告に含めて
オーケストレータに返せ。コミットはオーケストレータが git-composer に委譲する。
読み取り専用の git/gh（status/diff/log 等）は実行可。
また、履歴生成・リモート影響・非可逆破棄のいずれにも該当しない操作
（stash push/pop/apply/list/show/branch・merge/rebase/cherry-pick/am --abort・
restore --staged・apply・pull --ff-only・format-patch・request-pull）も実行可。
検出セグメント: ${blocked}
EOF
else
  cat >&2 <<EOF
🟠 git/gh の変更操作は main では実行せず、git-composer サブエージェントに委譲してください。
Agent ツールで subagent_type="git-composer" を起動し、この操作（アトミックコミット/ブランチ/マージ/push/PR など）を任せること。
【重要・多重起動禁止】操作ごとに起動せず、このタスクで必要な一連の変更系手順
（例: ステージ→commit→push→PR 作成→マージ→main 最新化）を 1 回の git-composer 起動に
まとめて渡すこと。git-composer はフック免除で内部 git/gh を連続実行できる。
複数リポジトリはリポ単位で並列起動可（各リポ内の手順は 1 委譲にまとめる）。
読み取り専用の git/gh（status/diff/log 等）は main で実行可。
また、履歴生成・リモート影響・非可逆破棄のいずれにも該当しない操作
（stash push/pop/apply/list/show/branch・merge/rebase/cherry-pick/am --abort・
restore --staged・apply・pull --ff-only・format-patch・request-pull）も main で実行可。
検出セグメント: ${blocked}
EOF
fi
exit 2
