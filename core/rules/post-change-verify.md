# Final-candidate verification

Once the code and any required project docs are stable, run exactly one round of objective verification over the final source, covering this change. Root runs it; long commands or long logs can go to `command-runner` (Root runs them directly when the host has no such agent). No separate verification role is needed.

## Order

1. Run the project's existing cheap lint/check; record `not configured` when there is none.
2. Run a build covering the production entry point.
3. Run the narrowest relevant tests when the user asks, the final plan specifies it, existing tests directly cover the change, or a high-risk gate hits.
4. Simulator, real device, full test suite, formatter fix, and Periphery run only when the user or the corresponding skill triggers them.

Obey project rules when they explicitly require stronger verification. When a targeted test already fully compiles the same production target, state the coverage relationship and skip the duplicate build; when in doubt, still run the build.

## Receipt

With a single Root, a single worktree, and verification results that no review gate, parallel fan-in, or cross-session reuse depends on, just run the commands — do not write a receipt. To reuse verification results across stages, use:

```bash
verify="$HOME/.claude/scripts/validation-receipt.sh"
repo="$(git rev-parse --show-toplevel)"
receipt="$repo/.specs/<slug>-validation.json"
"$verify" --repo "$repo" reusable "$receipt" <check-id> <coverage> || \
  "$verify" --repo "$repo" run "$receipt" <check-id> <coverage> -- <command> [args...]
```

A receipt is valid only for the current Git-visible source fingerprint; re-check after the source or project docs change. The helper compares the fingerprint before and after the command; when the check itself modifies source it writes `invalidated` and fails — the post-state must not be recorded as PASS. `.specs/` and `.reviews/` temporary artifacts do not by themselves invalidate a source receipt.

A receipt alone cannot prove that semantic or UI acceptance is still valid. When starting verifier / UI reviewer, follow `plan-first-delivery` to bind the source fingerprint, the authoritative plan, receipt/check evidence, the diff snapshot for semantic review, and the design/cases/build the UI needs into one context fingerprint; any input change invalidates the corresponding review PASS.

## Failure routing

- lint/check FAIL: fix the first actionable issue, then re-run lint/check; continue downstream after PASS.
- build FAIL: separate implementation errors from environment/dependency errors; fix only the scope the evidence hits.
- test FAIL: first determine whether it is a regression from this change, a pre-existing failure, or an environment issue, then decide the fix.
- After any fix changes the source, all old lint/check/build/test/review evidence is stale; re-run from the earliest invalidated required gate, usually starting at lint/check. Only an environment retry with unchanged source/context may re-run just the failed gate.
- Stop blind fixing when the same diagnosis makes no progress twice in a row; go back to Plan or ask the user. Returning to Plan preserves existing execution authorization while scope and intent remain unchanged; obtain authorization only for newly introduced actions.
- When the same required gate accumulates 4 FAILs (whether or not the diagnosis changed), you must ask the user; the "go back to Plan" branch is no longer allowed.

An independent verifier and UI reviewer start only after the corresponding `plan-first-delivery` gate hits and objective verification PASSes.
