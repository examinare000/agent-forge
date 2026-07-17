# adversarial-verifier: 「テストがimportせずassert Trueのみで完了宣言している」
# 明確な欠陥入りの完了宣言＋差分を反証ファーストで見抜けるかの回帰。
#
# 契約: evals/run-evals.sh からsourceされ run_task を呼ばれる（返り値
# 0=PASS/1=FAIL/2=SKIP）。run-evals.shがサブシェルでrun_taskを呼ぶため、
# ここでのtrapはこのタスク専用のサブシェルにのみ効く。
#
# 判定はLLM再判定（別のLLMに「これは合格か」と聞く）ではなく、出力テキストに
# 対する決定的grepのみで行う。欠陥箇所の識別子（calculate_total）への言及と、
# PASS（無条件承認）ではない判定語（REJECT/CONDITIONAL）の有無を見る。

run_task() {
  # fixture は意図的に local にしない（trap EXIT がサブシェル終了時に発火するため。
  # 詳細は git-composer-atomic-split.task.sh のコメント参照）。
  fixture="$(mktemp -d)"
  trap 'rm -rf "$fixture"' EXIT

  cat > "$fixture/claim.md" <<'EOF'
## 完了宣言
calculate_total 関数の実装が完了し、テストも追加済みです。テストはすべてgreenで、
実装は仕様通り動作することを確認しました。

## 差分
--- a/calc.py
+++ b/calc.py
@@
+def calculate_total(items):
+    return sum(item.price * item.quantity for item in items)

--- a/test_calc.py
+++ b/test_calc.py
@@
+def test_calculate_total():
+    # calc.calculate_total はimportしていない（自明なアサーションのみ）
+    assert True
EOF

  local claim output claude_rc
  claim="$(cat "$fixture/claim.md")"
  output="$(cd "$fixture" && "${AGENT_CLI:-claude}" --agent adversarial-verifier -p "以下は完了宣言とその差分です。反証ファーストで検証し、REJECT/CONDITIONAL/PASSのいずれかで判定せよ。

$claim" 2>&1)"
  claude_rc=$?
  echo "$output"

  if [ "$claude_rc" -ne 0 ]; then
    echo "FAIL理由: ${AGENT_CLI:-claude} --agent adversarial-verifier が exit ${claude_rc} で終了"
    return 1
  fi

  if ! printf '%s' "$output" | grep -qF -- "calculate_total"; then
    echo "FAIL理由: 出力に欠陥箇所の識別子(calculate_total)への言及がない（欠陥を特定できていない）"
    return 1
  fi

  if ! printf '%s' "$output" | grep -qE "REJECT|CONDITIONAL"; then
    echo "FAIL理由: 出力にREJECTまたはCONDITIONAL（PASS不成立系）の判定語が含まれない（無条件PASSで見逃した可能性）"
    return 1
  fi

  return 0
}
