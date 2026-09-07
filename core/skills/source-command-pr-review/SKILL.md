---
name: "source-command-pr-review"
description: "PR review — a subagent reviews the given PR (defaults to the current branch's PR) and leaves a comment on it; Haiku on Claude, Terra high on Codex"
---

# source-command-pr-review

Use this skill when the user asks to run the migrated source command `pr-review`.

## Command Template

Have a subagent review one PR and leave a comment on it. **This skill only does PR review** — no commit, no push, no merge.

## Arguments

- If the user passed a PR URL / number → use it
- Otherwise → use `gh pr view --json url,number,title` to get the current branch's PR; if there is none → report "no PR is open for the current branch, open one before calling `/pr-review`"

## Dispatch

Dispatch a subagent with the Agent tool:

- `subagent_type`: `general-purpose`
- `model`: `haiku` on Claude; `gpt-5.6-terra` + `high` on Codex. PR review involves semantic judgment and an external comment, so it does not drop down to Luna
- `description`: "PR review"
- Task prompt:
  - PR URL
  - Have the subagent run `gh pr view <url> --json title,body,files,additions,deletions` and `gh pr diff <url>` itself to read the metadata and the diff
  - Assess it from three angles: overall approach / potential risks / follow-up suggestions
  - **It must finally** post the assessment to the PR comments with `gh pr comment <url> --body "..."`
  - What to return to the main agent: "commented" plus a summary of the comment

If no subagent tool is available: the main agent runs the same `gh pr view` / `gh pr diff` / `gh pr comment` flow itself. Do **not** let the fallback produce a second duplicate comment; check the PR comments first to confirm none was just posted.

## Report back

Return the PR URL and the comment summary to the user. Do not advance to a next step automatically.

## Out of scope

- ❌ Does not modify code
- ❌ Does not merge the PR
- ❌ Does not run a deeper review on top (that is `/review`'s flagship reviewer path)
