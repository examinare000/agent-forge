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
    return violations


def main(argv: list[str] | None = None) -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rules-dir", type=Path, default=repo_root / "rules")
    parser.add_argument("--skills-dir", type=Path, default=repo_root / "skills")
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

    violations = lint_dist(args.out_dir, agents_text, gemini_text)
    if violations:
        for v in violations:
            print(v, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
