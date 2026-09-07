---
name: agent-readable-docs
description: "Compact agent-consumed operational Markdown without changing its behavioral contract. Use when creating or modifying AGENTS.md/CLAUDE.md; rule, agent, skill, template, or command Markdown under ~/.claude or project equivalents; or a new/existing knowledge document indexed for agents. Apply inline after content decisions to canonicalize prose and indexes. Skip read-only discovery/application of existing docs, format/link/rename-only edits, generated docs, ordinary README/API/user-facing docs, ExecPlan/spec, code comments, and commit/PR/release text. skill-creator owns skill functionality/frontmatter/resources/evals; scan-trigger-docs owns read-only discovery."
---

# Agent-readable docs

Treat this skill as an inline, semantics-preserving compaction step inside the same Root. Do not create a separate stage, subagent, artifact, or confirmation turn.

## First decide the document's role

| Role | Form to keep |
| --- | --- |
| Always-load index (AGENTS/CLAUDE) | Keep only entry points, precedence, and on-demand links; push the SOP down |
| On-demand execution doc (rule/agent/skill/command/template) | Entry assumptions, inputs, steps, outputs, failure routing, and verification |
| Long-lived knowledge / trigger-on-touch doc | Stable facts, invariants, owner, applicable scope, and invalidation conditions |
| Dual-audience doc or UI metadata | Keep the human explanation that is needed; compact only the agent-execution fragments |

When the target is not agent-consumed operational Markdown, return `agent_docs: not_needed` and do not apply this rule.

## Rewrite in place

1. Read the target, its direct entry index, and the direct references that define the same contract in full; determine the single canonical owner.
2. Freeze the semantics that must not change silently:
   - trigger, skip, scope, precedence, and authority;
   - permission/safety boundaries, input and output / schema, state transitions;
   - failure, retry, rollback, verification;
   - commands, paths, tool contracts, and non-obvious causality that changes an agent's decision.
3. After reading the whole document, merge new content into the section and existing structure it belongs to; do not merely append a record of this change at the end. Merge duplicate rules and adjacent explanations in place. Delete historical narrative, task traces, analogies, repeated emphasis, passages explaining the what of code, and expanded Why that does not affect decisions.
4. Do not mechanically delete whole sections by headings such as "design intent", "risks", or "fallback"; merge the constraints that still affect execution into the corresponding step, failure route, or verification.
5. Keep one canonical definition per fact and turn the other locations into short pointers. When sources conflict, surface the conflict first; do not pick a side on your own by length.
6. Real code is the only source of truth for numeric values such as UI sizes, spacing, colors, and tokens: project docs do not record the annotated values from design files (Figma and the like); cite the path of the code constant / token definition when needed. Design values live only in task-scoped frozen artifacts and the final plan.
7. Push a reference down only when it lowers always-load cost; keep it one hop away and do not create an index inside an index.

## Index edits

- Update the existing entry first; avoid append-only additions of near-synonymous entries.
- Each entry expresses one routing decision: trigger condition, purpose, link; implementation detail stays in the target document.
- When creating an agent knowledge document, add its entry to the index in the same change; when moving or deleting one, sync every direct link.

## Wrap-up

Reread the contract after the edit and confirm the frozen semantics above and the applicable project rules have not drifted. Mechanical verification such as format, frontmatter, local links, and installer follows the host/meta config flow; this skill adds no app build and no second documentation acceptance.

Return `agent_docs: no_change_required` when it is already compact and canonical. Otherwise update the target document directly, and do not write a separate summary file.

## Responsibility boundaries

- `skill-creator`: decides skill functionality, frontmatter, resource layout, verification, and evals; this skill only compacts its agent-facing prose/index.
- `scan-trigger-docs`: read-only discovery and application of project knowledge; this skill is used only when creating or modifying the body.
- `plan-first-delivery`: decides whether a product change needs a long-lived doc update; this skill does not force a paper trail for ordinary changes.
- `exec-plan`: one-off handoff plans are out of scope for this skill.
