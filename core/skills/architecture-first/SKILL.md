---
name: architecture-first
description: "Resolve durable architecture boundaries inside the current Root's Plan/discovery. Use only when the user explicitly asks to decide or revisit a material architecture boundary, or when work must choose/change an unresolved module/layer ownership or dependency direction, public/cross-module contract or multi-implementation seam, state source-of-truth/state machine/event flow, IO/side-effect boundary, or multi-responsibility split across those boundaries. Skip when project rules, precedent, or the authoritative final plan already determine structure and the user did not ask to revisit it. Skip work confined to one existing boundary—including private helpers/types/files, branches/flags, local error handling/tests, code smells, lint findings, and ordinary correctness review. Escalate review findings only when remediation requires a material boundary decision."
---

# Architecture-first

Treat this skill as a decision lens the same Root applies on demand inside Plan/discovery. It creates no separate phase, subagent, artifact, checklist, or confirmation round.

## Entry test

Enter architecture selection only when both hold:

1. The user explicitly asks for a redesign, or the final Plan, project rules and recent precedent do not yet pin down a single structure;
2. The choice durably changes at least one contract:
   - module/layer ownership or dependency direction;
   - public/cross-module API, extension point, or multi-implementation seam;
   - state source-of-truth, state machine, or event flow;
   - IO, side-effect, persistence, or external-system boundary;
   - splitting a multi-responsibility component across those boundaries.

Does not trigger on private helpers/types, new files, local branches/flags, copy-paste, TODOs, fallbacks, local error handling, test seams, line count, or lint warnings. `lean-diff`, `lint-repair-strategy`, or Root's root-cause diagnosis handles such local quality issues.

If the structure is already settled, return `architecture_decision: not_needed — <project rule / precedent / final plan>` and continue the current flow; do not open a candidate comparison just to prove "no complex architecture is needed".

## Evidence budget

Verify only facts that would change the current choice:

- read the project invariant or final plan that was hit;
- use `rg` to look at the affected boundary's direct callers/callees and one recent precedent;
- read the manifest only when adding or replacing a dependency;
- do not run a full reality-check on files, symbols, and dependencies in the prompt that do not affect the choice.

When the user's description disagrees with the repository, recalibrate the facts and continue. Ask the user only when the recalibration changes observable behavior, scope, hard constraints, or acceptance.

## Decision axes

Answer three questions in order:

1. `variation`: what is the real axis of variation, and are there truly multiple implementations or a durable extension point?
2. `state_ownership`: who owns the source of truth, lifecycle, concurrency, and migration?
3. `dependency_and_effects`: which way should dependencies point, and in which layer do the volatile seam, IO, and side effects land?

Read one reference on demand only when more than one viable structure exists:

- behavior/object pattern boundaries: `references/pattern-boundaries.md`
- UI state/event-flow boundaries: `references/ui-state-boundaries.md`
- module/system/side-effect boundaries: `references/system-boundaries.md`

When the project's existing shape already satisfies the constraints, reuse it; do not read encyclopedic material, and do not apply patterns mechanically by line or branch count.

## Output

Only when a material choice exists, merge the following straight into the final Plan; with no final Plan, keep it as the current Root's inline decision and create no separate file:

```yaml
architecture_decision:
  decision: <choice and responsibility boundary>
  evidence: [<2-3 repository facts>]
  rejected_nearest_alternative: <nearest candidate and why it was rejected>
  consequences:
    affected_boundaries: [<module/contract>]
    migration: <migration or compatibility requirement>
    verification: <behavior/boundary to prove>
```

When the Plan already carries the decision, Default implementation consumes it directly and does not invoke this skill again. If a new material boundary surprise appears during implementation, pause the writer and go back to discovery/Plan to update the decision; when ordinary review finds a clear boundary violation, report the finding directly — invoke this skill only when the fix still leaves an unresolved architecture choice.

## Out of scope

- Does not write implementation code directly;
- does not take over anti-patch, reuse, lint, or general correctness review;
- adds no approval point; ask along the main flow only when the choice changes user-facing behavior, scope, or a hard constraint;
- does not manufacture ceremonial justification for staying on the project's existing architecture.
