#!/usr/bin/env bash

set -euo pipefail

input="$(cat)"
cwd="$(jq -r '.cwd // "."' <<<"$input")"
tool_name="$(jq -r '.tool_name // ""' <<<"$input")"

case "$tool_name" in
  apply_patch|Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

paths=()

if [[ "$tool_name" == "apply_patch" ]]; then
  while IFS= read -r path; do
    [[ -n "$path" ]] && paths+=("$path")
  done < <(
    jq -r '.tool_input.command // ""' <<<"$input" |
      sed -nE \
        -e 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p' \
        -e 's/^\*\*\* Move to: (.*)$/\1/p'
  )
else
  path="$(
    jq -r \
      '.tool_input.file_path // .tool_input.notebook_path // empty' \
      <<<"$input"
  )"
  [[ -n "$path" ]] && paths+=("$path")
fi

if [[ "${#paths[@]}" -eq 0 ]]; then
  paths+=("$cwd")
fi

for raw_path in "${paths[@]}"; do
  if [[ "$raw_path" == /* ]]; then
    target="$raw_path"
  else
    target="$cwd/$raw_path"
  fi

  probe="$target"
  [[ -d "$probe" ]] || probe="$(dirname "$probe")"
  while [[ ! -d "$probe" && "$probe" != "/" ]]; do
    probe="$(dirname "$probe")"
  done

  repo_root="$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$repo_root" ]] || continue

  branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
  case "$branch" in
    main|master|dev)
      jq -n \
        --arg branch "$branch" \
        --arg target "$target" \
        '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: (
              "Target " + $target + " belongs to protected branch " + $branch +
              ". Create or use a task worktree first."
            )
          }
        }'
      exit 0
      ;;
  esac
done

exit 0
