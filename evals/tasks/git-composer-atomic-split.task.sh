# git-composer: 「テスト追加＋実装追加＋README修正」の混在未コミット変更を
# アトミックコミット規約（1コミット=1論理変更・テスト/実装/docs分離・日本語メッセージ）
# で分割コミットできるかの回帰。
#
# 契約: このファイルは evals/run-evals.sh からsourceされ、run_task関数を呼ばれる。
# run_taskの返り値: 0=PASS 1=FAIL 2=SKIP（理由は事前にstdoutへ出力すること）。
# run-evals.shはこのファイルをサブシェルでsource+run_task呼び出しするため、
# ここでの trap EXIT はこのタスク専用のサブシェルにのみ効き、他タスクや
# run-evals.sh本体には波及しない（bootstrap.test.shのmktemp -d + trap隔離様式を踏襲）。
#
# なぜHOMEを差し替えないのか: 実環境のuser-scope git-composer定義
# （~/.claude/agents/git-composer.md）をそのまま使うのが目的だから
# （run-evals.shヘッダ参照）。フィクスチャは一時git repoのみに限定し、
# 実リポジトリ・~/.claudeへは一切書き込まない。

run_task() {
  # fixture は意図的に local にしない: trap EXIT はサブシェル終了時（run_task の
  # return 後）に発火するため、local だと set -u で未定義になり掃除が走らない
  # （初回実走 2026-07-15 で一時ディレクトリ残留として実測・再現済み）。
  # タスクはサブシェル実行なので非localでも他タスクへ漏れない。
  fixture="$(mktemp -d)"
  trap 'rm -rf "$fixture"' EXIT

  git -C "$fixture" init -q
  git -C "$fixture" config user.email "eval@example.com"
  git -C "$fixture" config user.name "eval"
  echo "# fixture" > "$fixture/README.md"
  git -C "$fixture" add README.md
  git -C "$fixture" commit -q -m "初期コミット"

  # テスト/実装/docsの3種混在の未コミット変更を仕込む。
  mkdir -p "$fixture/src" "$fixture/tests"
  cat > "$fixture/src/calc.py" <<'EOF'
def add(a, b):
    return a + b
EOF
  cat > "$fixture/tests/test_calc.py" <<'EOF'
from src.calc import add


def test_add():
    assert add(1, 2) == 3
EOF
  {
    echo ""
    echo "## Usage"
    echo "calc.add(1, 2) -> 3"
  } >> "$fixture/README.md"

  local output claude_rc
  output="$(cd "$fixture" && "${AGENT_CLI:-claude}" --agent git-composer --permission-mode acceptEdits \
    --allowedTools "Bash(git add:*),Bash(git commit:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*)" \
    -p "このリポジトリの未コミット変更をアトミックコミット規約（1コミット=1論理変更・テスト/実装/docs分離・日本語メッセージ）で分割コミットせよ" 2>&1)"
  claude_rc=$?
  echo "$output"

  if [ "$claude_rc" -ne 0 ]; then
    echo "FAIL理由: ${AGENT_CLI:-claude} --agent git-composer が exit ${claude_rc} で終了"
    return 1
  fi

  # working tree clean（分割コミットが未完了だと必ず差分が残る）
  if [ -n "$(git -C "$fixture" status --porcelain)" ]; then
    echo "FAIL理由: フィクスチャrepoのworking treeがcleanでない"
    git -C "$fixture" status --porcelain
    return 1
  fi

  # 初期コミット含め4以上（＝初期1 + 分割3以上）
  local commit_count
  commit_count="$(git -C "$fixture" log --oneline | wc -l | tr -d ' ')"
  if [ "$commit_count" -lt 4 ]; then
    echo "FAIL理由: コミット数が${commit_count}件（期待: 初期コミット含め4件以上）"
    return 1
  fi

  # 初期コミットを除く各コミットが単一関心（テストのみ/実装のみ/docsのみ）かを
  # 変更ファイルのパスから判定する。
  local hashes hash files category categories_seen msg has_japanese_ok
  hashes="$(git -C "$fixture" log --reverse --format=%H | tail -n "+2")"
  categories_seen=""
  has_japanese_ok=true
  while IFS= read -r hash; do
    [ -z "$hash" ] && continue
    files="$(git -C "$fixture" diff-tree --no-commit-id --name-only -r "$hash")"
    category=""
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in
        tests/*) c="test" ;;
        src/*) c="impl" ;;
        *) c="docs" ;;
      esac
      if [ -z "$category" ]; then
        category="$c"
      elif [ "$category" != "$c" ]; then
        echo "FAIL理由: コミット ${hash} が複数関心（${category}と${c}）を含んでいる"
        return 1
      fi
    done <<< "$files"
    if [ -z "$category" ]; then
      echo "FAIL理由: コミット ${hash} に変更ファイルがない"
      return 1
    fi
    categories_seen="$categories_seen $category"

    msg="$(git -C "$fixture" log -1 --format=%s "$hash")"
    if ! printf '%s' "$msg" | perl -CSD -ne 'exit(/[\x{3040}-\x{30FF}\x{4E00}\x{9FFF}]/ ? 0 : 1)'; then
      echo "FAIL理由: コミット ${hash} のメッセージ「${msg}」に日本語が含まれない"
      has_japanese_ok=false
    fi
  done <<< "$hashes"

  if [ "$has_japanese_ok" != "true" ]; then
    return 1
  fi

  # test/impl/docsの3カテゴリが最低1回ずつ登場しているか（分離できていることの確認）。
  for want in test impl docs; do
    case " $categories_seen " in
      *" $want "*) ;;
      *)
        echo "FAIL理由: カテゴリ「${want}」に対応するコミットが見つからない（分離漏れ）"
        return 1
        ;;
    esac
  done

  return 0
}
