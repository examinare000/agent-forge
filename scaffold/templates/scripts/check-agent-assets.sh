#!/usr/bin/env bash
# エージェント資産の整合性チェック（drift 再発防止）。
# 本スクリプトは agent-forge の scaffold テンプレート由来（各プロジェクトへコピーされる）。
# copy モードで生成した新規プロジェクトは .claude/agents / .codex を持たない
# （エージェント定義は ~/.claude/agents にグローバル配置される）ため、
# .codex/agents ↔ .claude/agents のパリティ検査は「.codex/agents が存在する場合のみ」実行する
# （上級者が project-scoped agents を独自追加した場合の drift 検出用）。
#
# 使い方:   bash scripts/check-agent-assets.sh
# 終了コード: 0=OK / 1=違反（pre-push を中止すべき）
set -uo pipefail
shopt -s nullglob 2>/dev/null || true

# リポジトリルートへ移動
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
note() { printf '  - %s\n' "$1"; }

echo "🔎 エージェント資産整合性チェック ..."

# 1) エージェント対応表の突合（.codex/agents が存在する場合のみ）
# .claude/agents/*.md と .codex/agents/*.toml の basename を比較
echo ""
echo "  [1/3] エージェント対応表を確認中..."

if [ ! -d "$ROOT/.codex/agents" ]; then
  echo "  ℹ️  .codex/agents が無いためエージェント対応表チェックをスキップします（copyモードの既定構成）。"
else
  declare -a claude_agents
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    claude_agents+=("$(basename "$f" .md)")
  done < <(find "$ROOT/.claude/agents" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)

  declare -a codex_agents
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    codex_agents+=("$(basename "$f" .toml)")
  done < <(find "$ROOT/.codex/agents" -maxdepth 1 -type f -name '*.toml' 2>/dev/null | sort)

  # WHY `${arr[@]+"${arr[@]}"}`: bash 3.2ではset -u下で「要素0個の配列」を
  # `"${arr[@]}"`で展開すると unbound variable エラーになる（claude_agents/
  # codex_agentsのどちらかが空のプロジェクトは珍しくない）。`${arr[@]+...}`は
  # 配列が空でも安全に「展開結果なし」を返す標準的な回避イディオム。
  for agent in ${claude_agents[@]+"${claude_agents[@]}"}; do
    found=0
    for codex_agent in ${codex_agents[@]+"${codex_agents[@]}"}; do
      if [ "$agent" = "$codex_agent" ]; then
        found=1
        break
      fi
    done
    if [ $found -eq 0 ]; then
      echo "❌ エージェント欠落: .claude/agents/$agent.md は存在するが .codex/agents/$agent.toml がありません"
      note ".codex/agents/ に対応するミラーを追加してください。"
      fail=1
    fi
  done

  for codex_agent in ${codex_agents[@]+"${codex_agents[@]}"}; do
    found=0
    for agent in ${claude_agents[@]+"${claude_agents[@]}"}; do
      if [ "$codex_agent" = "$agent" ]; then
        found=1
        break
      fi
    done
    if [ $found -eq 0 ]; then
      echo "❌ エージェント過剰: .codex/agents/$codex_agent.toml は存在するが .claude/agents/$codex_agent.md がありません"
      note ".claude/agents/ に対応するエージェント定義を追加するか、.codex/agents/$codex_agent.toml を削除してください。"
      fail=1
    fi
  done

  # name フィールド一致（.codex/agents が存在する場合のみ意味を持つ）
  echo ""
  echo "  [2/3] エージェント name フィールドを確認中..."
  for toml_file in "$ROOT/.codex/agents"/*.toml; do
    [ -f "$toml_file" ] || continue
    toml_basename="$(basename "$toml_file" .toml)"

    # TOML の name フィールドを抽出：name = "value" / name = '''value''' → value
    # (agent-forgeのgenerators/build.pyはリテラル文字列 '''...''' で出力するため、
    #  " と ' の両方を剥がす)
    toml_name_value=$(grep -E '^\s*name\s*=' "$toml_file" 2>/dev/null | head -1 | sed "s/^[^=]*=\s*//; s/['\"]//g; s/[[:space:]]*\$//")

    claude_md="$ROOT/.claude/agents/$toml_basename.md"
    if [ ! -f "$claude_md" ]; then
      # すでに欠落報告済みなので skip
      continue
    fi

    claude_name_value=$(grep -E '^\s*name:\s*' "$claude_md" 2>/dev/null | head -1 | sed 's/^[^:]*:\s*//; s/"//g; s/[[:space:]]*$//')

    if [ -z "$toml_name_value" ]; then
      echo "❌ name フィールド欠落: $toml_file に name = ... がありません"
      fail=1
    elif [ "$toml_name_value" != "$claude_name_value" ]; then
      echo "❌ name 不一致: $toml_file の name=\"$toml_name_value\" が $claude_md の name: $claude_name_value と異なります"
      note "両ファイルの name フィールドを統一してください。"
      fail=1
    fi
  done
fi

# 3) .claude/rules/ の3パススコープファイルの健全性（symlink/copyどちらのモードでも成立させる）
echo ""
echo "  [3/3] .claude/rules/ のパススコープ参照ファイルを確認中..."
declare -a rule_refs=(testing frontend docker)
for rule in "${rule_refs[@]}"; do
  rule_file="$ROOT/.claude/rules/$rule.md"
  if [ ! -e "$rule_file" ] && [ ! -L "$rule_file" ]; then
    echo "❌ ルール参照ファイル欠落: $rule_file が存在しません"
    note "forge new が生成する .claude/rules/$rule.md が削除されていないか確認してください。"
    fail=1
    continue
  fi
  if [ -L "$rule_file" ]; then
    if [ ! -e "$rule_file" ]; then
      echo "❌ ルール参照 symlink 切断: $rule_file が指すファイルが存在しません（$(readlink "$rule_file")）"
      note "linkモードの前提である ~/.claude/rules/ が導入済みか確認してください（forge install）。"
      fail=1
    fi
  elif [ ! -s "$rule_file" ]; then
    echo "❌ ルール参照ファイルが空です: $rule_file"
    fail=1
  elif ! grep -q '^paths:' "$rule_file"; then
    echo "❌ ルール参照ファイルに paths: frontmatterがありません: $rule_file"
    note "Claude Codeのnative path-scoped rule機構向けにpaths:を維持してください。"
    fail=1
  fi
done

# 完了
echo ""
if [ "$fail" -ne 0 ]; then
  echo "🔴 エージェント資産チェック失敗。修正してから push してください。"
  exit 1
fi
echo "✅ エージェント資産チェック OK。"
exit 0
