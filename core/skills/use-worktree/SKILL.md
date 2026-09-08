---
name: use-worktree
description: Isolate every code change in a dedicated git worktree; the main checkout is for read-only operations only. Triggers on any coding task that will land Edit/Write while the cwd is not already under .worktrees/. Does not trigger when continuing the current task inside a worktree, nor for pure Q&A, reading code, or checking status; meta configuration does not auto-load this skill but still obeys the protected-branch routing in AGENTS.
---

# Always use a dedicated worktree for code changes

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

Create the worktree before the first source write. Do not implicitly derive from the current HEAD, which may hold WIP, and do not edit code directly in the main checkout.

## Entry routing

- Any coding task that will land Edit/Write (new feature, bugfix, refactor, added tests, etc.): triggers, whether or not the topic changed.
- The current path already contains `.worktrees/`: create nothing new, keep using the current worktree.
- Modifying the agent harness — rules, skills, hooks, settings: does not auto-trigger this skill; when repo-backed meta sits on main/master/dev, still follow AGENTS and switch to a task branch or pick a worktree first.
- Project rules forbid creating branches and grant no worktree exception: ask the user first, do not silently fall back to editing the main checkout.
- The main checkout has uncommitted user changes or sits on a non-baseline branch: confirm with the user before creating; inspect those changes read-only, do not move or revert them.

## Reuse

Run `git worktree list` before creating. When an existing worktree under `.worktrees/` satisfies "clean working tree and its branch is already merged into the baseline (`git merge-base --is-ancestor <branch> origin/<baseline>`)", you may reuse it (along with its resolved dependencies and build caches) by running `git fetch` inside it and then `git switch -c <new-branch>` straight from `origin/<baseline>`; the old branch stays where it is, and deleting it is the user's call. A worktree whose branch is unmerged or that has uncommitted changes must not be reused automatically; it needs explicit user authorization.

## Create and initialize

1. Read the project `AGENTS.md` to confirm the default baseline branch; when unspecified, follow the project convention — do not assume every repo uses `dev`.
2. One-shot bootstrap (fetch, worktree add, copy gitignored config, SPM artifacts symlink, directory trust, optional project init):

   ```bash
   "$HARNESS_ROOT/scripts/worktree-bootstrap.sh" <slug> --base <baseline-branch> \
     [--type feat] [--copy <relative-path>]... [--init "<command>"]
   ```

   By default the script copies `.claude/settings.local.json` when the main checkout has one; for SPM it only symlinks `build/DerivedData/SourcePackages/artifacts` and does not share `checkouts`, `repositories`, or `workspace-state.json`; the contents of copied files are never exposed in the output. `--init` runs only the initialization required to make the repo editable (codegen, dependency install, project generation). When the script is unavailable, perform the equivalent steps manually (`git fetch` + `git worktree add .worktrees/<slug> -b <type>/<slug> origin/<baseline>` + `trust-dir.sh "$PWD"`).
3. The branch type is usually `feat | fix | refactor | chore | docs | test | perf | style`; follow the project's or host's branch naming convention.

The init stage does no baseline build, does not warm up the Simulator, and does not open the IDE automatically; the final candidate is verified uniformly per `rules/post-change-verify.md`. When init fails, first separate local-config, dependency, and environment problems — do not treat an environment failure as a source failure; skip the related init when the user explicitly asks not to resolve dependencies.

## Lifecycle

- The branch is still needed for a PR or further iteration: keep the worktree.
- No changes and the task is cancelled: the worktree may be removed.
- With uncommitted changes, never discard or force-remove without explicit user authorization.
