---
name: dual-track-proposals
description: Use when delegating a non-trivial implementation task — multiple plausible approaches, novel design surface, or a prior failed attempt.
---

# Dual-Track Proposals (codex × sonnet 競合提案)

Non-trivial implementation tasks get two independent design proposals — one from Codex, one from a Sonnet coder — compared and adopted/merged by the orchestrator before a single implementation pass.

**Core principle:** proposals compete, implementation doesn't. Two write-capable agents on one tree is a merge problem; two read-only proposals is a judgment input.

## When to Use

Trigger when the implementation task meets ANY of:
- Multiple plausible approaches with real trade-offs
- Novel design surface (new module boundary, new public API, unfamiliar tech)
- A previous implementation attempt failed or was rejected
- The user explicitly asks for competing proposals

Do NOT use for spec-fixed mechanical tasks, trivial edits (≤ ~5 lines), or fixes with an obvious cause — those get single delegation per the standard table.

Scope boundary: `testability-architect` owns architecture-level decisions (module boundaries / data model / public API). Dual-track proposals compare implementation approaches within a settled architecture — when both trigger, run the architect first and fold its output into the shared brief.

## The Process

1. **One shared brief** (orchestrator): goal / target files / constraints / done-criteria (test command) / decisions already made. Identical text to both agents. Self-contained — no session history, no plan-file reading.
2. **Parallel dispatch** (one message, two Agent calls):
   - `外部ベンダー相当ツール（利用可能なら）` (Codex plugin 導入時。未導入なら Sonnet 独立2案で代替) — state read-only explicitly in the task text (propose only, do not edit) so the forwarder does not add `--write`. Ask for design approach + change outline (files touched, pseudo-diff level).
   - `tdd-strict-coder` — proposal mode: the brief states "proposal-only, no edits"; returns design approach + planned diff outline + test strategy.
3. **Compare** (orchestrator): score both on correctness / simplicity / testability / fit with existing code / risk. Adopt the better one, or merge — take the winning skeleton and graft superior ideas from the other. Record 1–3 lines of rationale (what was adopted, what was discarded, why).
4. **Single implementation**: hand the fixed spec to `tdd-strict-coder` (or `implementation-coder` when fully spec-fixed). Normal gates follow: `verification-before-completion` (run via `test-runner`) → `review-ai-antipattern` → `adversarial-verifier` → pre-merge checklist.

## Escalation Overlay

If the comparison itself is an architecture-level decision (module boundaries / data model / public API / irreversible ops), the standard 2-vote rule still applies on top: `adversarial-verifier` + `code-reviewer` on the adopted design, cross-vendor 3rd vote on disagreement.

## Red Flags

- Both proposals nearly identical → the task was probably trivial; skip to implementation and note the false trigger.
- Neither proposal satisfies a stated constraint → the brief was underspecified; fix the brief and re-run. Don't pick the "less bad" one.
- Merging by splicing half of each design → a merged spec must be one coherent design, not a patchwork.
