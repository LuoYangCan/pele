# <Title> ExecPlan

- **status**: active | blocked | superseded | complete
- **revision**: 1
- **owner**: Root
- **worktree**: <absolute path>
- **base ref**: <commit>

## Goal and done

<user-observable outcome and completion criteria>

## Scope and constraints

- In scope: <...>
- Non-goals: <...>
- Hard constraints: <...>

## Decisions and affected surfaces

- <key interfaces, data flow, compatibility/migration decisions>
- Expected paths/modules: <...>

## Milestones and ownership

| Milestone | Owner | Dependencies | State |
| --- | --- | --- | --- |
| <result-oriented unit> | Root / worker-name | <none / milestone> | pending |

Shared files are written by Root only; parallel writers must not overlap in file ownership.

## Verification and rollback

- Lint/check: `<command | not configured>`
- Build: `<command>`
- Targeted tests/behavior checks: `<command or steps | none + reason>`
- Independent/UI review gates: `<enabled + mandatory-risk/optional-requested + reason | disabled>`
- Just-in-time approval boundaries: `<exact destructive/irreversible/external actions | none>`
- Rollback/migration recovery: <...>

## Current handoff

- Confirmed facts: <...>
- Completed: <...>
- Next action: <...>
- Blockers: <none or concrete blocker>
