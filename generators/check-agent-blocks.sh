#!/bin/bash
# generators/agent-blocks/ の正準ブロックが対象ファイルへバイト一致で
# 埋め込まれているかを検査する（コピーペースト方式のドリフト検知）。
#
# なぜテンプレートエンジンではなくこの方式か:
# docs/trial-log/shared-block-canonicalization.md の検討により、agents/ は
# installer が ~/.claude/agents/ へ直接 symlink する正本であり、生成物化
# すると installer・降格手順・CI に連鎖改修が必要になるため見送った。
# 代わりに正準ブロックを generators/agent-blocks/ に置き、対象ファイルへ
# 手でコピーペーストし、この検査スクリプトで「部分文字列として含まれるか」
# を機械的に確認する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
cd "$REPO_ROOT"

python3 - <<'PY'
import sys
from pathlib import Path

BLOCKS_DIR = Path("generators/agent-blocks")

# ブロック名 -> 埋め込まれているべき対象ファイルの一覧。
MAPPING = {
    "report-core.md": [
        "agents/code-reviewer.md",
        "agents/tdd-strict-coder.md",
        "agents/git-composer.md",
        "agents/test-runner.md",
        "agents/implementation-coder.md",
        "agents/testability-architect.md",
    ],
    "report-worker.md": [
        "agents/tdd-strict-coder.md",
        "agents/implementation-coder.md",
    ],
    "trial-log-worker.md": [
        "agents/tdd-strict-coder.md",
        "agents/implementation-coder.md",
        "agents/testability-architect.md",
    ],
    "trial-log-reviewer.md": [
        "agents/code-reviewer.md",
        "agents/ai-antipattern-reviewer.md",
        "agents/adversarial-verifier.md",
    ],
    "no-nesting.md": [
        "agents/adversarial-verifier.md",
        "agents/ai-antipattern-reviewer.md",
        "agents/code-reviewer.md",
        "agents/git-composer.md",
        "agents/implementation-coder.md",
        "agents/tdd-strict-coder.md",
        "agents/test-runner.md",
        "agents/testability-architect.md",
    ],
    "antipattern-axes.md": [
        "agents/ai-antipattern-reviewer.md",
        "skills/review-ai-antipattern/SKILL.md",
    ],
}

failures = []
pair_count = 0

for block_name, targets in MAPPING.items():
    block_path = BLOCKS_DIR / block_name
    block_text = block_path.read_text(encoding="utf-8").rstrip("\n")
    for target in targets:
        pair_count += 1
        target_path = Path(target)
        target_text = target_path.read_text(encoding="utf-8")
        if block_text not in target_text:
            failures.append(f"{block_name}: {target}")

if failures:
    for line in failures:
        print(line, file=sys.stderr)
    sys.exit(1)

print(f"agent-blocks: {len(MAPPING)} blocks × {pair_count} targets OK")
PY
