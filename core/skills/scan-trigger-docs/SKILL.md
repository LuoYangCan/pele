---
name: scan-trigger-docs
description: Scan the trigger-on-touch doc index in the project's AGENTS.md/CLAUDE.md and read in full every doc that intersects this round's plan, write, or review scope. Skip when the project has no index, or when the scope clearly does not intersect.
---

# Scan trigger-on-touch docs

A plain Markdown link does not automatically inject the target's body into context. Every agent that plans, implements, or reviews runs this flow independently against its own actual scope.

## 1. Locate the project root

Walk up from cwd to the nearest `AGENTS.md` or `CLAUDE.md`. Inside a worktree use the worktree's own files; do not jump back to the main repository.

```bash
project_root="$PWD"
while [[ "$project_root" != "/" \
  && ! -f "$project_root/AGENTS.md" \
  && ! -f "$project_root/CLAUDE.md" ]]; do
  project_root="$(dirname "$project_root")"
done
```

Stop if neither exists.

## 2. Read the index

When the host has already injected the always-load files into context, or the project ships its own dedicated scan skill, the injected content and the project version win — do not Read them again; otherwise read whichever of `AGENTS.md` and `CLAUDE.md` exist, in full. Look for the following forms and any semantically equivalent phrasing:

- "read this doc before changing any of the following scopes";
- "trigger-on-touch / must read before touching";
- a plain Markdown link pointing to a subsystem index.

If an always-load file delegates the trigger table to another index file, read that index in full before deciding.

## 3. Match this round's scope

For each trigger, record the doc path and the triggering path/type/module/concept. Match against this round's planned paths, current ownership, actual changed paths, or review scope:

| Signal | Handling |
| --- | --- |
| The file sits directly under a trigger path | Read |
| A type, function, or module name hits | Read |
| Feature semantics relate to the doc's topic | Read |
| Clearly another platform/module with no intersection | Skip |
| The boundary is uncertain | Read |

When scope grows during execution, re-match the added part; no need to re-read the same version of a doc.

## 4. Read and apply

Read every doc that hits in full; do not substitute `grep/head` fragments. If a doc carries recursive triggers, continue under the same rules.

- Planning: write constraints that would change implementation or acceptance into the final plan.
- Implementation: obey the invariants; if one conflicts with the plan, pause writing and go back to the decision layer.
- Review: check the final diff against the doc as evidence, and report only deviations in the current diff.

When the project has `.cursor/rules/*.mdc`, read one in full only when its filename/preamble shows it is relevant to this round's scope.

## Output

The caller may attach to its structured result:

```yaml
trigger_docs_read:
  - <repo-relative path>
```

This skill does not modify markers, does not cache results across sessions, and does not replace planning, implementation, or review.
