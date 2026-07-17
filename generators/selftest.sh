#!/bin/bash
# generators/build.py のセルフテスト。決定的アサートのみ・実LLM呼び出しなし。
#
# なぜ bats 等の外部フレームワークを使わないのか:
# installer/install.test.sh / evals/harness-selftest.sh と同じ理由で、
# exit codeと出力文字列の一致だけで十分検証できる規模のテストに新規依存を
# 増やすのはスコープ過剰。既存2本と同じ assert_* ヘルパー方式に合わせる。
#
# 何を検証するか:
#   1) build.py内の各関数（フロントマター解析・フェンス除去・置換・
#      ルールファイル収集・lint検出）の単体シナリオ
#   2) fixture一式(testdata/fixture-basic/)に対するエンドツーエンドのbuild
#      実行結果（ホスト別フィルタ・フェンス・置換が期待通り反映されること）
#   3) 実リポジトリ(rules/, skills/)に対するbuild実行 → lint exit 0
#   4) 冪等性（同一入力を2回buildして出力に差分が無いこと）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
BUILD_PY="$SCRIPT_DIR/build.py"
FIXTURE_DIR="$SCRIPT_DIR/testdata/fixture-basic"

pass=0
fail=0

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# $1: label, $2: expected exit code, $3: actual exit code
assert_rc() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected actual=$actual)"
    fail=$((fail + 1))
  fi
}

# $1: label, $2: 出力全体, $3: 含まれるべき文字列
assert_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (needle not found: $needle)"
    fail=$((fail + 1))
  fi
}

# $1: label, $2: 出力全体, $3: 含まれてはいけない文字列
assert_not_contains() {
  local label="$1" output="$2" needle="$3"
  if printf '%s' "$output" | grep -qF -- "$needle"; then
    echo "FAIL: $label (含まれてはいけない文字列が存在: $needle)"
    fail=$((fail + 1))
  else
    echo "PASS: $label"
    pass=$((pass + 1))
  fi
}

# $1: label, $2: 存在すべきパス
assert_exists() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (存在すべきファイルが無い: $path)"
    fail=$((fail + 1))
  fi
}

# $1: label, $2: 存在してはいけないパス
assert_absent() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then
    echo "FAIL: $label (存在してはいけないファイルが存在: $path)"
    fail=$((fail + 1))
  else
    echo "PASS: $label"
    pass=$((pass + 1))
  fi
}

# build.py内の純粋関数を直接呼び出す小さなPythonスニペットを実行するヘルパー。
# $1: label, $2: pythonコード(標準出力に "OK" が出れば成功とみなす)
assert_py() {
  local label="$1" code="$2"
  local out rc=0
  out="$(python3 -c "$code" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "OK" ]; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label"
    echo "  --- output(rc=$rc) ---"
    printf '%s\n' "$out" | sed 's/^/  /'
    echo "  ----------------------"
    fail=$((fail + 1))
  fi
}

# 単体テストから build.py をモジュールとしてimportするための共通プリアンブル。
PY_IMPORT_BUILD="
import importlib.util, sys
spec = importlib.util.spec_from_file_location('agent_forge_build', '$BUILD_PY')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
"

echo "=== 単体: parse_frontmatter ==="
assert_py "hosts指定ありのfrontmatterからhostsリストを抽出できる" "
$PY_IMPORT_BUILD
meta, body = build.parse_frontmatter('---\nhosts: [claude, codex]\n---\n# body\n')
assert meta['hosts'] == ['claude', 'codex'], meta
assert body == '# body\n', repr(body)
print('OK')
"

assert_py "frontmatterが無いファイルはmeta空・本文そのまま" "
$PY_IMPORT_BUILD
meta, body = build.parse_frontmatter('# body only\n')
assert meta == {}, meta
assert body == '# body only\n', repr(body)
print('OK')
"

assert_py "hosts以外のfrontmatterフィールド(name/description)も抽出できる" "
$PY_IMPORT_BUILD
meta, body = build.parse_frontmatter('---\nname: sample\ndescription: desc text\n---\n# body\n')
assert meta['name'] == 'sample', meta
assert meta['description'] == 'desc text', meta
print('OK')
"

assert_py "pathsのような複数行リストfrontmatterがあってもクラッシュしない" "
$PY_IMPORT_BUILD
text = '---\npaths:\n  - \"**/*.test.ts\"\n  - \"**/*.spec.ts\"\n---\n# body\n'
meta, body = build.parse_frontmatter(text)
assert body == '# body\n', repr(body)
print('OK')
"

echo ""
echo "=== 単体: host_allowed ==="
assert_py "hosts未指定は全ホスト許可" "
$PY_IMPORT_BUILD
assert build.host_allowed({}, 'codex') is True
assert build.host_allowed({}, 'gemini') is True
print('OK')
"

assert_py "hosts: [claude]指定はcodex/geminiを許可しない" "
$PY_IMPORT_BUILD
meta = {'hosts': ['claude']}
assert build.host_allowed(meta, 'claude') is True
assert build.host_allowed(meta, 'codex') is False
assert build.host_allowed(meta, 'gemini') is False
print('OK')
"

echo ""
echo "=== 単体: strip_host_fences ==="
assert_py "対象ホストのフェンスはマーカーのみ除去され本文は残る" "
$PY_IMPORT_BUILD
text = 'before\n<!-- host:codex -->\nkeep me\n<!-- /host:codex -->\nafter\n'
out = build.strip_host_fences(text, 'codex')
assert 'keep me' in out, out
assert 'host:codex' not in out, out
assert 'before' in out and 'after' in out, out
print('OK')
"

assert_py "対象外ホストのフェンスは中身ごと除去される" "
$PY_IMPORT_BUILD
text = 'before\n<!-- host:claude -->\ndrop me\n<!-- /host:claude -->\nafter\n'
out = build.strip_host_fences(text, 'codex')
assert 'drop me' not in out, out
assert 'host:claude' not in out, out
assert 'before' in out and 'after' in out, out
print('OK')
"

assert_py "フェンスが無いテキストはそのまま返る" "
$PY_IMPORT_BUILD
text = 'plain text with no fences\n'
assert build.strip_host_fences(text, 'codex') == text
print('OK')
"

echo ""
echo "=== 単体: 置換テーブル読み込み・適用 ==="
assert_py "hosts.tomlの最小サブセットをパースできる(pattern/codex/gemini)" "
$PY_IMPORT_BUILD
from pathlib import Path
subs = build.load_substitutions(Path('$FIXTURE_DIR/hosts.toml'))
patterns = [s['pattern'] for s in subs]
assert 'mcp__shelf__consult' in patterns, patterns
print('OK')
"

assert_py "apply_substitutionsはhost別の置換列を使う" "
$PY_IMPORT_BUILD
subs = [{'pattern': 'mcp__shelf__consult', 'codex': 'CODEX_TEXT', 'gemini': 'GEMINI_TEXT'}]
assert build.apply_substitutions('use mcp__shelf__consult here', 'codex', subs) == 'use CODEX_TEXT here'
assert build.apply_substitutions('use mcp__shelf__consult here', 'gemini', subs) == 'use GEMINI_TEXT here'
print('OK')
"

assert_py "置換順序: 先に列挙した規則が優先して消費する" "
$PY_IMPORT_BUILD
subs = [
    {'pattern': 'mcp__shelf__consult', 'codex': 'SPECIFIC', 'gemini': 'SPECIFIC'},
    {'pattern': 'mcp__[A-Za-z0-9_]+', 'codex': 'GENERIC', 'gemini': 'GENERIC'},
]
out = build.apply_substitutions('mcp__shelf__consult and mcp__other__tool', 'codex', subs)
assert out == 'SPECIFIC and GENERIC', out
print('OK')
"

echo ""
echo "=== 単体: ルールファイル収集 ==="
assert_py "rules直下の番号付きファイルのみを番号順に集め、README.mdとhosts/配下は除外する" "
$PY_IMPORT_BUILD
from pathlib import Path
files = [p.name for p in build.collect_rule_files(Path('$FIXTURE_DIR/rules'))]
assert files == ['00-core.md', '10-git.md', '20-claude-limited.md'], files
print('OK')
"

echo ""
echo "=== 単体: agents/*.md 収集 ==="
assert_py "agents直下の.mdファイルをファイル名順に集める" "
$PY_IMPORT_BUILD
from pathlib import Path
files = [p.name for p in build.collect_agent_files(Path('$FIXTURE_DIR/agents'))]
assert files == ['read-only-agent.md', 'write-agent.md'], files
print('OK')
"

echo ""
echo "=== 単体: YAML二重引用符フロントマター値の復元(_unescape_yaml_dq) ==="
assert_py "クォート無しの値はそのまま返す" "
$PY_IMPORT_BUILD
assert build._unescape_yaml_dq('adversarial-verifier') == 'adversarial-verifier'
print('OK')
"

assert_py "外側のダブルクォートを剥がす" "
$PY_IMPORT_BUILD
assert build._unescape_yaml_dq('\"read-only-agent\"') == 'read-only-agent'
print('OK')
"

assert_py "エスケープされた引用符(\\\\\")を実際の引用符1文字に戻す" "
$PY_IMPORT_BUILD
raw = '\"say \\\\\"hi\\\\\" now\"'
out = build._unescape_yaml_dq(raw)
assert out == 'say \"hi\" now', repr(out)
print('OK')
"

assert_py "二重バックスラッシュ(\\\\\\\\n)はバックスラッシュ1文字+nの2文字として残る(実改行にしない)" "
$PY_IMPORT_BUILD
raw = '\"a\\\\\\\\n\\\\\\\\nb\"'
out = build._unescape_yaml_dq(raw)
assert out == 'a' + chr(92) + 'n' + chr(92) + 'nb', repr(out)
assert chr(10) not in out, repr(out)
print('OK')
"

echo ""
echo "=== 単体: TOML文字列シリアライズ(_toml_string) ==="
assert_py "通常の文字列はリテラル文字列('''...''')で囲む" "
$PY_IMPORT_BUILD
out = build._toml_string('plain text with \"quotes\" and ' + chr(92) + 'n backslash-n')
assert out == \"'''plain text with \\\"quotes\\\" and \" + chr(92) + \"n backslash-n'''\", out
print('OK')
"

assert_py "''' を含む文字列は基本複数行文字列にフォールバックしエスケープする" "
$PY_IMPORT_BUILD
value = \"has '''triple''' inside\"
out = build._toml_string(value)
assert out.startswith('\"\"\"') and out.endswith('\"\"\"'), out
assert \"'''\" in out, out
print('OK')
"

echo ""
echo "=== 単体: agentのtools一覧からsandbox_mode判定(_agent_sandbox_mode) ==="
assert_py "Edit/Writeを含まないtools一覧はread-only" "
$PY_IMPORT_BUILD
assert build._agent_sandbox_mode(['Bash', 'Read', 'Grep', 'Glob']) == 'read-only'
print('OK')
"

assert_py "Editを含むtools一覧はNone(sandbox_mode指定なし)" "
$PY_IMPORT_BUILD
assert build._agent_sandbox_mode(['Bash', 'Read', 'Edit', 'Write']) is None
print('OK')
"

echo ""
echo "=== 単体: reasoning effort変換(_agent_reasoning_effort) ==="
assert_py "effort未指定はNone,Noneを返す(model_reasoning_effortを出力しない)" "
$PY_IMPORT_BUILD
value, comment = build._agent_reasoning_effort(None)
assert value is None and comment is None, (value, comment)
print('OK')
"

assert_py "effort=xhighはCodexの最上位highへ降格しコメントを添える" "
$PY_IMPORT_BUILD
value, comment = build._agent_reasoning_effort('xhigh')
assert value == 'high', value
assert comment is not None and 'xhigh' in comment and 'high' in comment, comment
print('OK')
"

assert_py "effort=highはそのままhigh・コメント無し" "
$PY_IMPORT_BUILD
value, comment = build._agent_reasoning_effort('high')
assert value == 'high', value
assert comment is None, comment
print('OK')
"

echo ""
echo "=== 単体: render_codex_agent_toml ==="
assert_py "read-only-agentのtoml: sandbox_mode/model_reasoning_effort/リテラル文字列化/本文置換が反映される" "
$PY_IMPORT_BUILD
from pathlib import Path
subs = build.load_substitutions(Path('$FIXTURE_DIR/hosts.toml'))
text = Path('$FIXTURE_DIR/agents/read-only-agent.md').read_text(encoding='utf-8')
meta, body = build.parse_frontmatter(text)
out = build.render_codex_agent_toml(meta, body, 'codex', subs)
assert out.startswith(\"name = '''read-only-agent'''\"), out
assert '説明文' in out, out
assert '\"引用符\"' in out, out
assert 'sandbox_mode = \"read-only\"' in out, out
assert 'model_reasoning_effort = \"high\"' in out, out
assert 'xhigh' in out, out
assert '最高性能クラス' in out, out
assert 'shelf MCP（導入環境のみ）' in out, out
assert 'mcp__shelf__consult' not in out, out
assert out.rstrip().endswith(chr(39)*3), out
print('OK')
"

assert_py "write-agentのtoml: sandbox_mode/model_reasoning_effortを出力せず本文のAgentツール置換が反映される" "
$PY_IMPORT_BUILD
from pathlib import Path
subs = build.load_substitutions(Path('$FIXTURE_DIR/hosts.toml'))
text = Path('$FIXTURE_DIR/agents/write-agent.md').read_text(encoding='utf-8')
meta, body = build.parse_frontmatter(text)
out = build.render_codex_agent_toml(meta, body, 'codex', subs)
assert 'sandbox_mode' not in out, out
assert 'model_reasoning_effort' not in out, out
assert '軽量クラス' in out, out
assert '逐次プロンプト' in out, out
assert 'Agent ツール' not in out, out
print('OK')
"

echo ""
echo "=== 単体: lint検出 ==="
assert_py "禁止パターンを含む行をfile:line付きで検出する" "
$PY_IMPORT_BUILD
violations = build.lint_text('line1\nuses mcp__something here\n', 'dist/AGENTS.md', build.LINT_PATTERNS_FULL)
assert len(violations) == 1, violations
assert 'dist/AGENTS.md:2' in violations[0], violations
print('OK')
"

assert_py "禁止パターンが無ければ空リスト" "
$PY_IMPORT_BUILD
violations = build.lint_text('clean text\nnothing bad here\n', 'dist/AGENTS.md', build.LINT_PATTERNS_FULL)
assert violations == [], violations
print('OK')
"

echo ""
echo "=== エンドツーエンド: fixtureに対するbuild実行 ==="
OUT1="$WORKDIR/out1"
rc=0
out="$(python3 "$BUILD_PY" \
  --rules-dir "$FIXTURE_DIR/rules" \
  --skills-dir "$FIXTURE_DIR/skills" \
  --agents-dir "$FIXTURE_DIR/agents" \
  --hosts-toml "$FIXTURE_DIR/hosts.toml" \
  --out-dir "$OUT1" 2>&1)" || rc=$?
assert_rc "fixture一式のbuildはexit 0(lint通過)" 0 "$rc"

agents_text="$(cat "$OUT1/AGENTS.md" 2>/dev/null || echo MISSING)"
gemini_text="$(cat "$OUT1/GEMINI.md" 2>/dev/null || echo MISSING)"

assert_contains "AGENTS.mdに共通ルール(00-core)が含まれる" "$agents_text" "共通ルール。全ホスト共通で読まれる。"
assert_contains "AGENTS.mdでmcp__shelf__consultが置換されている" "$agents_text" "shelf MCP（導入環境のみ）"
assert_not_contains "AGENTS.mdにmcp__の生トークンが残らない" "$agents_text" "mcp__"
assert_contains "AGENTS.mdでAgent ツールが逐次プロンプトに置換されている" "$agents_text" "逐次プロンプト"
assert_not_contains "AGENTS.mdにAgent ツールの生トークンが残らない" "$agents_text" "Agent ツール"
assert_contains "AGENTS.mdにcodex向けフェンス内容が残る" "$agents_text" "Codex固有の補足事項"
assert_not_contains "AGENTS.mdにgemini向けフェンス内容が残らない" "$agents_text" "Gemini固有の補足事項"
assert_not_contains "AGENTS.mdにclaude向けフェンス内容が残らない" "$agents_text" "Claude専用の詳細運用"
assert_not_contains "AGENTS.mdにフェンスマーカー文字列が残らない" "$agents_text" "host:codex"
assert_not_contains "AGENTS.mdにhosts:[claude]指定ファイルの内容が含まれない" "$agents_text" "Claude限定ルール"
assert_not_contains "AGENTS.mdにrules/hosts/claude/配下(位置除外)の内容が含まれない" "$agents_text" "Claude Only (位置による除外)"
assert_not_contains "AGENTS.mdにREADME.mdの内容が含まれない" "$agents_text" "索引ファイルであり"
assert_contains "AGENTS.mdに劣化ガイダンス節がある" "$agents_text" "サブエージェント機構の劣化ガイダンス"
assert_contains "AGENTS.mdのスキル索引にsample-skillが載る" "$agents_text" "sample-skill"
assert_not_contains "AGENTS.mdのスキル索引にhosts:[claude]指定スキルが載らない" "$agents_text" "claude-only-skill"

assert_contains "GEMINI.mdにgemini向けフェンス内容が残る" "$gemini_text" "Gemini固有の補足事項"
assert_contains "GEMINI.mdでmcp__shelf__consultが置換されている" "$gemini_text" "shelf MCP（導入環境のみ）"
assert_not_contains "GEMINI.mdにcodex向けフェンス内容が残らない" "$gemini_text" "Codex固有の補足事項"
assert_not_contains "GEMINI.mdにclaude向けフェンス内容が残らない" "$gemini_text" "Claude専用の詳細運用"

assert_exists "codex-plugin/plugin.jsonが生成される" "$OUT1/codex-plugin/plugin.json"
assert_contains "plugin.jsonにagent-forge名がある" "$(cat "$OUT1/codex-plugin/plugin.json")" "agent-forge"
assert_exists "codex-plugin/skills/sample-skill/SKILL.mdが生成される" "$OUT1/codex-plugin/skills/sample-skill/SKILL.md"
assert_exists "codex-plugin/skills/sample-skill/NOTES.txt(補助ファイル)がコピーされる" "$OUT1/codex-plugin/skills/sample-skill/NOTES.txt"
assert_absent "codex-plugin/skillsにhosts:[claude]指定スキルは生成されない" "$OUT1/codex-plugin/skills/claude-only-skill"

skill_out_text="$(cat "$OUT1/codex-plugin/skills/sample-skill/SKILL.md" 2>/dev/null || echo MISSING)"
assert_contains "codex-plugin skillでAgentツールが置換されている" "$skill_out_text" "逐次プロンプト"
assert_not_contains "codex-plugin skillに~/.claude が残らない" "$skill_out_text" "~/.claude"
assert_not_contains "codex-plugin skillにClaude専用フェンス内容が残らない" "$skill_out_text" "Claude固有のサブエージェント起動手順"
assert_not_contains "codex-plugin skillにgemini向けフェンス内容が残らない" "$skill_out_text" "Gemini向け特記事項"
assert_contains "codex-plugin skillのfrontmatter descriptionにも置換が適用される" "$skill_out_text" "shelf MCP（導入環境のみ）"

assert_exists "codex-agents/read-only-agent.tomlが生成される" "$OUT1/codex-agents/read-only-agent.toml"
assert_exists "codex-agents/write-agent.tomlが生成される" "$OUT1/codex-agents/write-agent.toml"
readonly_toml_text="$(cat "$OUT1/codex-agents/read-only-agent.toml" 2>/dev/null || echo MISSING)"
write_toml_text="$(cat "$OUT1/codex-agents/write-agent.toml" 2>/dev/null || echo MISSING)"
assert_contains "read-only-agent.tomlにsandbox_mode=read-onlyがある" "$readonly_toml_text" 'sandbox_mode = "read-only"'
assert_contains "read-only-agent.tomlにmodel_reasoning_effort=highがある(xhighからの降格)" "$readonly_toml_text" 'model_reasoning_effort = "high"'
assert_contains "read-only-agent.tomlの本文でmcp__shelf__consultが置換されている" "$readonly_toml_text" "shelf MCP（導入環境のみ）"
assert_not_contains "read-only-agent.tomlにmcp__の生トークンが残らない" "$readonly_toml_text" "mcp__"
assert_not_contains "write-agent.tomlにsandbox_modeが出力されない(Edit/Write保持のため)" "$write_toml_text" "sandbox_mode"
assert_contains "write-agent.tomlの本文でAgentツールが置換されている" "$write_toml_text" "逐次プロンプト"

echo ""
echo "=== エンドツーエンド: lint違反があればexit 1で検出理由を報告する ==="
BAD_RULES="$WORKDIR/bad-rules"
mkdir -p "$BAD_RULES"
printf '# 00. Bad\n\nこの行には未処理の mcp__leftover があります。\n' > "$BAD_RULES/00-bad.md"
EMPTY_SKILLS="$WORKDIR/empty-skills"
mkdir -p "$EMPTY_SKILLS"
: > "$WORKDIR/empty-hosts.toml"
rc=0
out="$(python3 "$BUILD_PY" \
  --rules-dir "$BAD_RULES" \
  --skills-dir "$EMPTY_SKILLS" \
  --hosts-toml "$WORKDIR/empty-hosts.toml" \
  --out-dir "$WORKDIR/out-bad" 2>&1)" || rc=$?
assert_rc "未置換の禁止パターンが残るとexit 1" 1 "$rc"
assert_contains "lint違反メッセージにファイル名:行番号形式が出る" "$out" "dist/AGENTS.md:"
assert_contains "lint違反メッセージに違反箇所の行内容が出る" "$out" "mcp__leftover"

echo ""
echo "=== エンドツーエンド: dist/codex-agents/にlint禁止パターンが残ればexit 1 ==="
BAD_AGENTS="$WORKDIR/bad-agents"
mkdir -p "$BAD_AGENTS"
printf -- '---\nname: "bad-agent"\ndescription: "テスト用"\nmodel: sonnet\ntools: Bash, Read\n---\n\n~/.claude/agents/ を直接参照する残存表現。\n' > "$BAD_AGENTS/bad-agent.md"
rc=0
out="$(python3 "$BUILD_PY" \
  --rules-dir "$EMPTY_SKILLS" \
  --skills-dir "$EMPTY_SKILLS" \
  --agents-dir "$BAD_AGENTS" \
  --hosts-toml "$WORKDIR/empty-hosts.toml" \
  --out-dir "$WORKDIR/out-bad-agents" 2>&1)" || rc=$?
assert_rc "codex-agentsに~/.claudeが残るとexit 1" 1 "$rc"
assert_contains "lint違反メッセージがdist/codex-agents/配下を指す" "$out" "dist/codex-agents/bad-agent.toml:"

echo ""
echo "=== 冪等性: 同一fixtureを2回buildしても出力が一致する ==="
OUT2="$WORKDIR/out2"
rc=0
python3 "$BUILD_PY" \
  --rules-dir "$FIXTURE_DIR/rules" \
  --skills-dir "$FIXTURE_DIR/skills" \
  --agents-dir "$FIXTURE_DIR/agents" \
  --hosts-toml "$FIXTURE_DIR/hosts.toml" \
  --out-dir "$OUT2" >/dev/null 2>&1 || rc=$?
assert_rc "2回目のbuildもexit 0" 0 "$rc"

diff_out="$(diff -r "$OUT1" "$OUT2" 2>&1)" || true
assert_contains "冪等性: 2回のbuild出力に差分が無い" "$([ -z "$diff_out" ] && echo NO_DIFF || echo "$diff_out")" "NO_DIFF"

echo ""
echo "=== 実リポジトリに対するbuild実行 ==="
REAL_OUT1="$WORKDIR/real-out1"
rc=0
out="$(python3 "$BUILD_PY" --out-dir "$REAL_OUT1" 2>&1)" || rc=$?
assert_rc "実リポジトリのbuildはexit 0(lint通過)" 0 "$rc"
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out" | sed 's/^/  /'
fi
assert_exists "実buildでdist相当のAGENTS.mdが生成される" "$REAL_OUT1/AGENTS.md"
assert_exists "実buildでdist相当のGEMINI.mdが生成される" "$REAL_OUT1/GEMINI.md"
assert_exists "実buildでdist相当のcodex-plugin/plugin.jsonが生成される" "$REAL_OUT1/codex-plugin/plugin.json"
assert_exists "実buildでdist相当のcodex-agents/が生成される" "$REAL_OUT1/codex-agents"

agent_count="$(find "$REAL_OUT1/codex-agents" -maxdepth 1 -name '*.toml' | wc -l | tr -d ' ')"
assert_rc "実buildのcodex-agents/はagents/*.mdと同数(8個)のtomlを生成する" 8 "$agent_count"

assert_py "実buildで生成した各codex-agents/*.tomlが構文的に健全(可能ならtomllibでパース)" "
import glob
for path in glob.glob('$REAL_OUT1/codex-agents/*.toml'):
    text = open(path, encoding='utf-8').read()
    assert text.count(chr(39)*3) % 2 == 0, (path, 'リテラル文字列の三重引用符が閉じていない')
    assert text.count(chr(34)*3) % 2 == 0, (path, '基本複数行文字列の三重引用符が閉じていない')
    assert 'name = ' in text, (path, 'nameキーが無い')
    assert 'developer_instructions = ' in text, (path, 'developer_instructionsキーが無い')
    try:
        import tomllib
        tomllib.loads(text)
    except ModuleNotFoundError:
        pass
print('OK')
"

REAL_OUT2="$WORKDIR/real-out2"
python3 "$BUILD_PY" --out-dir "$REAL_OUT2" >/dev/null 2>&1
real_diff="$(diff -r "$REAL_OUT1" "$REAL_OUT2" 2>&1)" || true
assert_contains "実リポジトリbuildも冪等(2回目と差分なし)" "$([ -z "$real_diff" ] && echo NO_DIFF || echo "$real_diff")" "NO_DIFF"

echo ""
echo "=== 本番dist/への実書き込み(既定引数)がexit 0であること ==="
rc=0
out="$(cd "$REPO_ROOT" && python3 generators/build.py 2>&1)" || rc=$?
assert_rc "既定引数(python3 generators/build.py)でのbuildもexit 0" 0 "$rc"
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$out" | sed 's/^/  /'
fi
assert_exists "dist/AGENTS.mdが存在する" "$REPO_ROOT/dist/AGENTS.md"
assert_exists "dist/GEMINI.mdが存在する" "$REPO_ROOT/dist/GEMINI.md"
assert_exists "dist/codex-plugin/が存在する" "$REPO_ROOT/dist/codex-plugin"

echo ""
echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
