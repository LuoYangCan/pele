---
description: Code review + quality fixes — after /simplify, collect structured report-only findings, and the backend generates the report
---

Use the host review backend:

- Codex: `$HARNESS_ROOT/core/skills/source-command-review-codex/SKILL.md`
- Claude Code: `$HARNESS_ROOT/core/skills/source-command-review/SKILL.md`

Codex runs its native review flow; Claude Code keeps the legacy native `/review`
backend. Do not invoke the Claude-only backend from a Codex prompt.
