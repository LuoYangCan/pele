# Review binding (conditional acceptance)

Resolve installed paths per the [host adapter](../../../rules/host-adapter.md) before running helpers.

Root reads this file in full after `needs_independent_review` / `needs_ui_review` is hit and objective verification PASSes; ordinary tasks do not read it.

## Candidate identity and evidence binding

An objective receipt only proves the current Git-visible source. Before launching a verifier / UI reviewer, Root must also freeze this acceptance context:

1. `source`: the current value of `validation-receipt.sh --repo "$repo" source-fingerprint`;
2. `plan`: the ExecPlan's absolute path, revision and file SHA-256, or the SHA-256 of the full body of the same task's native Plan mode final plan (also record a stable item/turn ID when the host provides one; when it does not, identity is the body SHA-256 plus a task slug chosen by Root). If a narrow task was implemented directly via entry routing with no Plan/ExecPlan, compose a canonical intent body from the user's original goal, the authorized scope/non-goals and the acceptance criteria, and use it, together with the user-message/thread ID (when the host provides one) and the body SHA-256, as `plan=`; it only binds existing intent for the review, and adds no checkpoint or plan file;
3. `validation`: the receipt path matching `source`, its file SHA-256 and the required check IDs/coverage, or, with no receipt, the normalized commands, exit codes, coverage and their SHA-256;
4. Semantic acceptance additionally freezes `diff`: the binary patch from `base_ref` to the final candidate, plus the JSON manifest of current untracked product paths; both go in `.reviews/`, the binding carries absolute paths and SHA-256, and the verifier reads the current untracked files per the manifest;
5. UI additionally freezes `design` (immutable file/node/version; when the provider has no version, the frozen reference/measurement/resource bundle digest is the source of truth, and no mutable latest is fetched live during review), `cases` (exact steps, strict/loose, tolerances) and `build` (the absolute path and `artifact-digest` of the actually installed `.app`, bundle ID, scheme, configuration, destination/runtime, and the corresponding build receipt/check).

The semantic snapshot uses the final candidate and excludes acceptance temp directories:

```bash
"$HARNESS_ROOT/scripts/review-input-snapshot.sh" \
  --repo "$repo" "$base_ref" "<slug>"
```

Use the helper's returned `base_commit + patch SHA-256 + untracked manifest SHA-256` as the `diff=` binding. If the source fingerprint changes after the freeze, regenerate the snapshot; do not recompute only the outer fingerprint.

Call `validation-receipt.sh --repo "$repo" review-fingerprint semantic|ui ...` on the repo/worktree passed in (the helper enforces the required keys and sorts them): semantic acceptance yields `review_input_fingerprint`, UI acceptance yields `ui_review_input_fingerprint`. The review request must carry the full binding and fingerprint, and the output must echo them verbatim. Root recomputes once against the current candidate before dispatch and once after receiving the result; the post-receipt recompute must also check the snapshot's mtime/inode list (line format `mtime inode path`, path last and may contain spaces) against the current files, and drift is handled as a write inside the window. If the source, final plan, diff snapshot, design artifacts, cases/strictness, build or verification evidence change in any way, the related PASS is invalidated immediately.

"Recompute" means re-deriving every SHA or stable ID from the current files/artifacts/plan item first, then calling the helper; taking the previous binding string and re-running only the outer hash is forbidden.

A binding value holds only a canonical single-line identity/digest, and does not inline plan/cases bodies; the full bodies and structured cases are attached separately as review input, and the binding references their SHA-256.

Freeze all source/plan/design writers while the review runs; only the UI reviewer may write `.reviews/` evidence. Once a relevant write is observed inside the window, discard the result and re-freeze the inputs; even if the fingerprint returns to its old value by the end, it cannot be reused.

A Codex verifier recomputes on its own with `review-fingerprint semantic` under `sandbox_mode=read-only`. Claude's parent permission mode may override the subagent mode, so a Claude verifier gets no Bash/Edit/Write and only reads the pre-attached patch, the untracked manifest and the current files; its staleness protection comes from Root's dual fingerprint check before dispatch and after receipt.

## Independent semantic acceptance

When `needs_independent_review=true`, launch one fresh, read-only verifier after objective verification PASSes. The input must contain: repo/worktree, `base_ref`, the user requirement and the final Plan/ExecPlan/canonical intent, the final changed paths, the frozen patch and untracked manifest, the full `plan=`/`validation=`/`diff=` bindings, `review_input_fingerprint`, and verification evidence matching the current source.

The verifier does not run lint/build/test, does not change code, and does not dispatch further agents. Ordinary tasks do not launch a verifier, and do not stack a second semantic verifier.

Routing for a blocking finding: Root verifies it → fixes → re-runs all invalidated verification → hands the original finding ID/body, the previous fingerprint and the new bindings to the same verifier for one recheck; if the second pass still makes no progress, stop and align with the user. When the user goal, the authoritative plan or related design inputs change, the old review is likewise invalidated.

## UI acceptance

When `needs_ui_review=true`, call the UI reviewer only after an actually installable `.app` has been frozen per `build=`; "build PASS" by itself is not enough. It checks only the visuals and interactions the plan/design requires, and does not replace the semantic verifier. If both gates are hit, the same final source can be accepted in parallel, but each validates its own context fingerprint. If a strict Figma artifact exposes new behavior, scope, architecture or acceptance decisions, return to DISCOVER/PLAN_READY to update the final plan before implementing; a design artifact must not silently supersede the old plan.
