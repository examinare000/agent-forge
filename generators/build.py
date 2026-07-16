#!/usr/bin/env python3
"""generators/build.py — 多ベンダー向け指示ファイル生成器（Python3標準ライブラリのみ）。

rules/ と skills/ を素材に、Codex CLI 用 dist/AGENTS.md、Gemini CLI 用
dist/GEMINI.md、Codex plugin 用 dist/codex-plugin/ を生成する。

Claude Code 固有機構（サブエージェント・hooks強制・plan mode）は他ホストに
存在しないため、指示層のみを移植し、固有部は除外または劣化ガイダンスに
置換する。

再生成: `python3 generators/build.py`
直接編集しないこと。編集対象は rules/ / skills/ / generators/hosts.toml 側。
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

# 生成対象ホスト。claude は rules/ と skills/ を直接利用するため生成不要。
HOSTS = ("codex", "gemini")

GENERATED_HEADER = (
    "<!--\n"
    "  本ファイルは generators/build.py により自動生成されました。\n"
    "  再生成: `python3 generators/build.py`\n"
    "  直接編集しないでください（rules/ または skills/ を編集して再生成すること）。\n"
    "-->\n"
)

# サブエージェント機構が存在しないホスト向けの劣化ガイダンス。
# 元の委譲表(rules/*.md)がサブエージェント前提で書かれているため、
# 「どう代替するか」を一箇所にまとめて明示する（各節ごとに繰り返し書かない）。
DEGRADATION_GUIDANCE = (
    "## サブエージェント機構の劣化ガイダンス\n"
    "\n"
    "本フレームワークの委譲表はサブエージェント機構を前提とする。"
    "サブエージェントが無いホストでは: 各役割（設計/実装/レビュー/検証）を"
    "**逐次の独立プロンプト**として実行する。特に重要: 実装後の自己レビューは"
    "新しい会話/コンテキストで行う（自己レビューの甘さ回避）。"
    "強制ゲート（hooks）は存在しないため、コミット前チェックリストを"
    "手動で実行する。\n"
)

# rules/ 直下の対象ファイル名パターン（番号付きの実ルールファイルのみ）。
# README.md はホスト非依存の索引・メタドキュメントであり、番号を持たないので
# このパターンに一致せず自然に除外される。
RULE_FILENAME_RE = re.compile(r"^\d{2}-.*\.md$")

# 先頭のYAML風フロントマター(--- ... ---)を抽出する。
FRONTMATTER_RE = re.compile(r"\A---\n(.*?\n)---\n?", re.DOTALL)
# フロントマター内の `key: value` 一行フィールド。
# `paths:` のような複数行リスト(次行以降が `  - "..."`)は value 側が空文字に
# なるだけで、以降の `- ...` 行はこのパターンに一致せず読み飛ばされる
# （完全なYAMLパーサは不要という設計方針どおり）。
FIELD_LINE_RE = re.compile(r"^(\w+):\s?(.*)$")

# `<!-- host:X --> ... <!-- /host:X -->` の部分除外フェンス。
FENCE_RE = re.compile(
    r"[ \t]*<!--\s*host:(claude|codex|gemini)\s*-->\n(.*?)"
    r"[ \t]*<!--\s*/host:\1\s*-->\n?",
    re.DOTALL,
)

# lint対象パターン（生成物に残ってはならないClaude Code固有の語句）。
LINT_PATTERNS_FULL = ["mcp__", "~/.claude", "Fable", "codex:", "Agent ツール", "Task ツール"]
# codex-plugin/skills/ 配下はスキルの説明文脈上 mcp__ 等が残りうるため、
# より狭い集合のみを検査する（設計どおり）。
LINT_PATTERNS_SKILLS = ["~/.claude", "Fable"]


def parse_frontmatter(text: str) -> tuple[dict, str]:
    """先頭のフロントマターを抽出する。

    完全なYAMLパーサは使わず、`key: value` の一行フィールドのみを正規表現で
    読む（設計方針: 完全なYAMLパーサ不要）。`hosts: [a, b]` は特別扱いして
    リストに分解する。フロントマターが無ければ meta={} で本文をそのまま返す。
    """
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    fm_body = m.group(1)
    body = text[m.end():]
    meta: dict = {}
    for line in fm_body.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fm = FIELD_LINE_RE.match(line)
        if not fm:
            # `  - "..."` のようなリスト継続行は対象外なので読み飛ばす。
            continue
        key, value = fm.group(1), fm.group(2).strip()
        if key == "hosts":
            value = value.strip("[]")
            meta["hosts"] = [h.strip() for h in value.split(",") if h.strip()]
        else:
            meta[key] = value
    return meta, body


def host_allowed(meta: dict, host: str) -> bool:
    """frontmatterの`hosts`指定を尊重する。省略時は全ホスト対象。"""
    hosts = meta.get("hosts")
    if not hosts:
        return True
    return host in hosts


def strip_host_fences(text: str, host: str) -> str:
    """部分除外フェンスを処理する。

    対象ホスト(host)向けの区間はマーカー行のみ除去して本文を残し、
    他ホスト向けの区間はマーカーごと丸ごと除去する。
    """

    def _repl(m: re.Match) -> str:
        fence_host, body = m.group(1), m.group(2)
        return body if fence_host == host else ""

    return FENCE_RE.sub(_repl, text)


def collect_agent_files(agents_dir: Path) -> list[Path]:
    """agents/直下の.mdファイルをファイル名順に集める（サブディレクトリは対象外）。"""
    if not agents_dir.is_dir():
        return []
    return sorted(p for p in agents_dir.glob("*.md") if p.is_file())


def _unescape_yaml_dq(raw: str) -> str:
    """agents/*.md フロントマターのYAML二重引用符スカラー値を復元する。

    generators/build.py 共通のフロントマターパーサ(FIELD_LINE_RE)はクォート剥がしや
    エスケープ解決を行わない簡易実装（rules/skills側はunquoted運用のため今まで不要
    だった）。agents/*.md 側は `name: "..."` / `description: "..."` のようにYAMLの
    double-quoted scalar を使うため、ここでのみ最小限のエスケープ解決を行う。
    対応するのは実際にこのリポジトリで使われる2種類のみ:
      - `\\"` → `"` （埋め込みの引用符）
      - `\\\\` → `\\` （エスケープされたバックスラッシュ。直後の文字は別トークンとして
        そのまま残るため、例えば `\\\\n` は「バックスラッシュ1文字+n」という2文字に
        戻る。実改行(chr(10))には変換しない）
    他のエスケープ種別(\\t, \\uXXXX 等)はこのリポジトリの記法に出現しないため未対応。
    """
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        raw = raw[1:-1]
    out: list[str] = []
    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch == "\\" and i + 1 < len(raw) and raw[i + 1] in ("\\", '"'):
            out.append(raw[i + 1])
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def _toml_string(value: str) -> str:
    """Python文字列をTOML文字列リテラルとして安全にシリアライズする。

    エージェント定義の説明文・本文プロンプトには `"` や `\\` を含む例文が多い。
    TOMLのリテラル文字列(`'''...'''`)はエスケープ処理を一切行わないため、
    このデフォルトを使えばバックスラッシュや引用符をそのまま埋め込める
    （エスケープ漏れ・二重エスケープのバグを構造的に防げる）。
    内容が `'''` を含む場合のみリテラル文字列を開始できないため、
    基本複数行文字列(`\"\"\"..\"\"\"`)にフォールバックし `\\` と `"` をエスケープする。
    """
    if "'''" not in value:
        return f"'''{value}'''"
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"""{escaped}"""'


def _agent_sandbox_mode(tools: list[str]) -> str | None:
    """agentのtools一覧からCodex側のsandbox_modeを判定する。

    Edit/Writeを持たないエージェントは書き込み不可(read-only)であることを
    Codex側にも明示する。書き込み可能なエージェントは既定(workspace-write相当)で
    よいためNoneを返し、sandbox_modeフィールド自体を出力しない。
    """
    if "Edit" in tools or "Write" in tools:
        return None
    return "read-only"


def _agent_reasoning_effort(effort: str | None) -> tuple[str | None, str | None]:
    """Claude側のeffort frontmatter値をCodexのmodel_reasoning_effortへ変換する。

    Codexの reasoning effort は low/medium/high のみで xhigh に非対応のため、
    xhigh は対応する最上位 high に意図的に降格し、その理由をコメント文として返す
    （agentDevTemplateの実例 adversarial-verifier.toml と同じ方針）。
    effort未指定は「Codex側のデフォルトに委ねる」ことを意味するため、
    フィールド自体を出力しない(None, None)。
    """
    if effort is None:
        return None, None
    if effort == "xhigh":
        return "high", "Claude側はeffort=xhighだが、Codexのreasoning effortはlow/medium/highのみでxhigh非対応のため、対応する最上位highを意図的に維持する。"
    return effort, None


_TOML_TABLE_RE = re.compile(r"^\[\[substitution\]\]\s*$")
_TOML_KV_RE = re.compile(r"""^(\w+)\s*=\s*(['"])(.*)\2\s*$""")


def _parse_minimal_toml(text: str) -> dict:
    """tomllib不在環境向けの最小TOMLサブセットパーサ。

    なぜ独自実装か: このリポジトリのデフォルト`python3`(3.9系)には
    tomllib(3.11+同梱)が無く、外部依存追加はstdlib限定方針に反するため。
    hosts.tomlは `[[substitution]]` の配列テーブルに文字列キー
    (pattern/codex/gemini)のみを持つ制限されたスキーマなので、ネスト・
    複数行文字列・エスケープ等の完全なTOML文法は非対応でよい。
    シングルクォート値はTOMLのliteral string同様エスケープ処理をしない。
    """
    entries: list[dict] = []
    current: dict | None = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if _TOML_TABLE_RE.match(line):
            if current is not None:
                entries.append(current)
            current = {}
            continue
        kv = _TOML_KV_RE.match(line)
        if kv and current is not None:
            key, _quote, value = kv.groups()
            current[key] = value
    if current is not None:
        entries.append(current)
    return {"substitution": entries}


def load_substitutions(path: Path) -> list[dict]:
    """generators/hosts.toml（ホスト別置換テーブル）を読み込む。

    Python 3.11+ の環境では標準の`tomllib`を優先して使い、無い環境では
    上記の最小パーサへフォールバックする（同じ制限されたスキーマである限り
    両者は同じ結果を返す）。
    """
    text = path.read_text(encoding="utf-8")
    try:
        import tomllib  # type: ignore[import-not-found]
    except ImportError:
        data = _parse_minimal_toml(text)
    else:
        data = tomllib.loads(text)
    return data.get("substitution", [])


def apply_substitutions(text: str, host: str, substitutions: list[dict]) -> str:
    """置換テーブルをデータ駆動で順に適用する。

    列挙順が適用順（先に列挙した規則ほど優先）。あるホスト向けの置換文字列が
    定義されていない規則はそのホストでは無視する。
    """
    for rule in substitutions:
        pattern = rule["pattern"]
        replacement = rule.get(host)
        if replacement is None:
            continue
        text = re.sub(pattern, replacement, text)
    return text


def collect_rule_files(rules_dir: Path) -> list[Path]:
    """rules/直下(サブディレクトリを除く)の番号付きルールファイルを番号順に集める。

    README.md はメイン索引（人間向けメタドキュメント）であり生成物には含めない。
    rules/hosts/<host>/ はホスト固有機構であり、Path.glob("*.md")が直下のみを
    対象にするためディレクトリの位置により自動的に除外される。
    """
    return sorted(
        p for p in rules_dir.glob("*.md") if RULE_FILENAME_RE.match(p.name)
    )


def collect_skill_dirs(skills_dir: Path) -> list[Path]:
    """skills/直下の各スキルディレクトリ(SKILL.mdを持つもの)を名前順に集める。"""
    if not skills_dir.is_dir():
        return []
    return sorted(
        p for p in skills_dir.iterdir() if p.is_dir() and (p / "SKILL.md").is_file()
    )


def render_rules_section(rules_dir: Path, host: str, substitutions: list[dict]) -> str:
    """共通ルールを番号順に連結し、ホストフィルタ・フェンス除去・置換を適用する。"""
    parts = []
    for path in collect_rule_files(rules_dir):
        meta, body = parse_frontmatter(path.read_text(encoding="utf-8"))
        if not host_allowed(meta, host):
            continue
        body = strip_host_fences(body, host)
        body = apply_substitutions(body, host, substitutions)
        parts.append(body.strip("\n"))
    return "\n\n".join(parts) + "\n"


def render_skill_index(skills_dir: Path, host: str, substitutions: list[dict]) -> str:
    """skills/の索引(name + description の表)を生成する。本文はcodex-plugin側参照。"""
    lines = ["## Skills 索引", "", "| name | description |", "| --- | --- |"]
    for skill_dir in collect_skill_dirs(skills_dir):
        meta, _ = parse_frontmatter((skill_dir / "SKILL.md").read_text(encoding="utf-8"))
        if not host_allowed(meta, host):
            continue
        name = apply_substitutions(meta.get("name", skill_dir.name), host, substitutions)
        description = apply_substitutions(meta.get("description", ""), host, substitutions)
        description = description.replace("|", "\\|")
        lines.append(f"| `{name}` | {description} |")
    lines.append("")
    if host == "codex":
        lines.append(
            "各スキルの本文は同梱の Codex plugin "
            "(`codex-plugin/skills/<name>/SKILL.md`) を参照。本ファイルには索引のみ掲載する。"
        )
    else:
        lines.append(
            "各スキルの本文は配布元リポジトリの `skills/<name>/SKILL.md` を参照"
            "（本ファイルには索引のみ掲載）。"
        )
    return "\n".join(lines) + "\n"


def render_host_doc(rules_dir: Path, skills_dir: Path, host: str, substitutions: list[dict]) -> str:
    """1ホスト分の生成物本文(AGENTS.md / GEMINI.md)を組み立てる。"""
    parts = [
        GENERATED_HEADER,
        render_rules_section(rules_dir, host, substitutions),
        DEGRADATION_GUIDANCE,
        render_skill_index(skills_dir, host, substitutions),
    ]
    return "\n".join(p.strip("\n") for p in parts) + "\n"


def render_codex_agent_toml(meta: dict, body: str, host: str, substitutions: list[dict]) -> str:
    """1エージェント分の`.codex/agents/<name>.toml`本文を組み立てる。

    キー構成は移植元(~/git/agentDevTemplate/.codex/agents/*.toml)の実形式に合わせる:
    name / description / (任意コメント) / model_reasoning_effort / sandbox_mode /
    developer_instructions。Codexには存在しない`model: opus/sonnet/haiku`のような
    厳密な値は出力せず(実在しないmodel IDを名乗ると設定として壊れるため)、
    tier表現はコメント行にのみ残す。
    """
    name = _unescape_yaml_dq(meta.get("name", "")).strip()
    description = apply_substitutions(_unescape_yaml_dq(meta.get("description", "")), host, substitutions)
    tools = [t.strip() for t in meta.get("tools", "").split(",") if t.strip()]

    lines = [f"name = {_toml_string(name)}", f"description = {_toml_string(description)}"]

    raw_model = meta.get("model", "").strip()
    if raw_model:
        tier_label = apply_substitutions(raw_model, host, substitutions)
        lines.append(f"# model tier: {tier_label}（正本 agents/*.md の model: {raw_model} 相当）")

    reasoning_effort, effort_comment = _agent_reasoning_effort(meta.get("effort"))
    if reasoning_effort is not None:
        if effort_comment:
            lines.append(f"# {effort_comment}")
        lines.append(f'model_reasoning_effort = "{reasoning_effort}"')

    sandbox_mode = _agent_sandbox_mode(tools)
    if sandbox_mode is not None:
        lines.append(
            "# 正本 agents/*.md の tools 制約（read-only）を Codex 側で表現するため sandbox を read-only に固定"
        )
        lines.append(f'sandbox_mode = "{sandbox_mode}"')

    instructions = apply_substitutions(strip_host_fences(body, host), host, substitutions).strip("\n")
    lines.append(f"developer_instructions = {_toml_string(instructions)}")

    return "\n".join(lines) + "\n"


def build_codex_agents(agents_dir: Path, out_dir: Path, substitutions: list[dict]) -> None:
    """dist/codex-agents/<name>.toml 一式（agents/*.md のCodexミラー）を生成する。"""
    agents_out = out_dir / "codex-agents"
    if agents_out.exists():
        shutil.rmtree(agents_out)
    agents_out.mkdir(parents=True)

    for agent_path in collect_agent_files(agents_dir):
        text = agent_path.read_text(encoding="utf-8")
        meta, body = parse_frontmatter(text)
        toml_text = render_codex_agent_toml(meta, body, "codex", substitutions)
        (agents_out / f"{agent_path.stem}.toml").write_text(toml_text, encoding="utf-8")


def build_codex_plugin(skills_dir: Path, out_dir: Path, substitutions: list[dict]) -> None:
    """dist/codex-plugin/ (plugin.json + skills/<name>/SKILL.md 一式)を生成する。"""
    plugin_dir = out_dir / "codex-plugin"
    if plugin_dir.exists():
        shutil.rmtree(plugin_dir)
    skills_out = plugin_dir / "skills"
    skills_out.mkdir(parents=True)

    plugin_manifest = {
        "name": "agent-forge",
        "description": "agent-forge のルール/スキルを移植した Codex CLI 用プラグイン。",
        "skills": "./skills/",
    }
    (plugin_dir / "plugin.json").write_text(
        json.dumps(plugin_manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    for skill_dir in collect_skill_dirs(skills_dir):
        meta, _ = parse_frontmatter((skill_dir / "SKILL.md").read_text(encoding="utf-8"))
        if not host_allowed(meta, "codex"):
            continue
        dest_dir = skills_out / skill_dir.name
        dest_dir.mkdir(parents=True)
        for src in sorted(skill_dir.iterdir()):
            if src.name == "SKILL.md":
                # frontmatterは維持(構造は保持)しつつ、本文含め全体に
                # フェンス除去・置換を適用する(frontmatterのdescription等にも
                # Claude固有語句が含まれうるため。lint対象でもある)。
                text = src.read_text(encoding="utf-8")
                text = strip_host_fences(text, "codex")
                text = apply_substitutions(text, "codex", substitutions)
                (dest_dir / "SKILL.md").write_text(text, encoding="utf-8")
            elif src.is_dir():
                shutil.copytree(src, dest_dir / src.name)
            else:
                shutil.copy2(src, dest_dir / src.name)


def lint_text(text: str, label: str, patterns: list[str]) -> list[str]:
    """禁止パターンを含む行を`file:line`付きで報告する。"""
    violations = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        for pat in patterns:
            if pat in line:
                violations.append(f"{label}:{lineno}: 禁止パターン検出: {pat!r}: {line.strip()}")
    return violations


def lint_dist(out_dir: Path, agents_text: str, gemini_text: str) -> list[str]:
    """生成後のdist一式に対してlintを実行する。"""
    violations = []
    violations += lint_text(agents_text, "dist/AGENTS.md", LINT_PATTERNS_FULL)
    violations += lint_text(gemini_text, "dist/GEMINI.md", LINT_PATTERNS_FULL)
    skills_out = out_dir / "codex-plugin" / "skills"
    if skills_out.is_dir():
        for skill_md in sorted(skills_out.glob("*/SKILL.md")):
            text = skill_md.read_text(encoding="utf-8")
            label = f"dist/{skill_md.relative_to(out_dir)}"
            violations += lint_text(text, label, LINT_PATTERNS_SKILLS)
    # codex-agents/*.toml もskillsと同じ狭い集合で検査する(設計どおり)。
    # エージェント本文もskill本文同様に自然文プロンプトであり、mcp__ツール名や
    # `codex:`接頭辞等はプロンプト文脈上正当に出現しうるため対象外とする。
    agents_out = out_dir / "codex-agents"
    if agents_out.is_dir():
        for agent_toml in sorted(agents_out.glob("*.toml")):
            text = agent_toml.read_text(encoding="utf-8")
            label = f"dist/{agent_toml.relative_to(out_dir)}"
            violations += lint_text(text, label, LINT_PATTERNS_SKILLS)
    return violations


def main(argv: list[str] | None = None) -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rules-dir", type=Path, default=repo_root / "rules")
    parser.add_argument("--skills-dir", type=Path, default=repo_root / "skills")
    parser.add_argument("--agents-dir", type=Path, default=repo_root / "agents")
    parser.add_argument("--hosts-toml", type=Path, default=script_dir / "hosts.toml")
    parser.add_argument("--out-dir", type=Path, default=repo_root / "dist")
    args = parser.parse_args(argv)

    substitutions = load_substitutions(args.hosts_toml)

    args.out_dir.mkdir(parents=True, exist_ok=True)

    agents_text = render_host_doc(args.rules_dir, args.skills_dir, "codex", substitutions)
    gemini_text = render_host_doc(args.rules_dir, args.skills_dir, "gemini", substitutions)

    (args.out_dir / "AGENTS.md").write_text(agents_text, encoding="utf-8")
    (args.out_dir / "GEMINI.md").write_text(gemini_text, encoding="utf-8")
    build_codex_plugin(args.skills_dir, args.out_dir, substitutions)
    build_codex_agents(args.agents_dir, args.out_dir, substitutions)

    violations = lint_dist(args.out_dir, agents_text, gemini_text)
    if violations:
        for v in violations:
            print(v, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
