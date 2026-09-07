---
name: lint-repair-strategy
description: Pick the repair direction by lint category when fixing SwiftLint / SwiftFormat findings, so code never gets moved into a meaningless extension just to dodge file_length/type_body_length. Use whenever the implementation owner receives a lint warning/error. Skip when a build error is still unfixed, when the user explicitly asks for a local disable, or when the issue is unrelated to lint.
---

# lint-repair-strategy

## Triggers

Any one of these triggers it:

- Running `just check` / SwiftLint / SwiftFormat produced a warning or error that must be fixed
- A `lint-error` / `lint-warning` from a verifier or `/review` report must be landed

## Does not trigger

- A build error is still open (fix compilation first)
- The user explicitly says "add swiftlint:disable on this line" / "disable it first, get it running"
- The incoming issue is not lint-class (mock-data / scope-violation / behavior-mismatch)

## Repair decision table

Find the category by rule name; each category has a **preferred fix → fallback**.

### Category A: pure formatting / naming / unused

Example rules: `trailing_whitespace` / `vertical_whitespace_*` / `opening_brace` / `colon` / `comma` / `operator_usage_whitespace` / `unused_import` / `unused_declaration` / `identifier_name` / `type_name` / `file_header`

**Fix**: run `just fix` / SwiftFormat directly, or change the one line by hand. No restructuring needed.

### Category B: length / complexity (**the one most often dodged by lazily extracting an extension**)

Example rules: `file_length` / `type_body_length` / `function_body_length` / `line_length` / `cyclomatic_complexity` / `nesting` / `function_parameter_count`

**Ask for the root cause, in order**:

1. Has this type / function **outgrown its responsibility**?
   - Yes → split by use case into **functional submodules** (a new type / service / reducer / view component); do not "move it to +Helpers"
   - Example: a 1200-line `HomeViewController` → split into two independent types, `HomeFeedSection` and `HomeRecommendationLogic`, **not** `HomeViewController+Helpers.swift`

2. Does this function mash **several semantic steps** together?
   - Yes → extract subfunctions with **semantic names** (`fetchProfile()` / `validateInput()` / `dispatchEvent()`), not `helper1()` / `_doStuff()`

3. Too many logical branches (the complexity rules)?
   - Can be resolved inside the existing boundary by splitting functions semantically, a closed enum/switch, or table-driven dispatch → fix locally
   - Only when the fix must change module ownership/dependency direction, a public seam, state source-of-truth, or the IO boundary → escalate to `architecture-first`

4. Genuinely, legitimately long?
   - SwiftUI body / DSL configuration / generated code → put `// swiftlint:disable type_body_length` at the top of that **single** file plus a one-line why
   - Do not disable globally

**Hard prohibitions**:

- ❌ Extracting **meaningless extension files** like `<Type>+Helpers.swift` / `<Type>+Utilities.swift` / `<Type>+Lint.swift` / `<Type>+Private.swift` / `<Type>+Internal.swift` purely to dodge `file_length` / `type_body_length`
- ❌ Moving blocks of private methods into `<Type>+xxx.swift` as a way over the wall
- ❌ Multiple extensions in one file purely to control line count

**Allowed extension extraction** (legitimate cases, not hard-prohibited):

- ✅ `<Type>+Codable.swift` — Codable is an independent concern
- ✅ `<Type>+Equatable.swift` / `<Type>+Hashable.swift` — protocol conformance is independent
- ✅ `<Type>+CollectionView.swift` — the UICollectionViewDelegate implementation is an independent protocol
- ✅ `<Type>+Analytics.swift` — analytics instrumentation is an independent cross-cutting concern
- Test: the extension filename maps to a **clear semantic concern** (protocol / cross-cutting / subsystem), not "where the rest of the code goes"

### Category C: local structural signals

Example rules: `large_tuple` / `cyclomatic_complexity` (same as B) / `function_parameter_count` (same as B) / `force_try`

**Fix**: restore the semantics inside the existing boundary first; lint alone does not trigger architecture selection.

- `large_tuple` → introduce a local/nested struct with business meaning
- `function_parameter_count` exceeded → group into a config/input struct only the parameters that genuinely share a lifecycle; otherwise split into semantic steps
- `cyclomatic_complexity` exceeded → extract semantic functions, or use enum/switch/table for closed cases
- `force_try` → if failure is a legal path, switch to `throws`/`Result` and let the existing owner handle it; for a static invariant, a local disable with a stated reason is fine

Hand the diagnostic evidence to `architecture-first` only when one of the fixes above would change a durable boundary; do not escalate automatically because of a rule name.

### Category D: boundary / safety

Example rules: `force_unwrap` / `force_cast` / `implicitly_unwrapped_optional` / `discouraged_direct_init`

**Fix**: usually an API design problem, not a one-line change.

- Many `force_unwrap` → the IUO should become `Optional` + guard let
- Many `force_cast` → redesign with a protocol / generic
- A one-line change is enough + the context guarantees non-nil → `// swiftlint:disable:next force_unwrap` plus a one-line why

## Output plan

The skill does not edit code directly. Return a structured decision (written into chat for the caller):

```yaml
lint_repair_plan:
  - rule: <SwiftLint rule name>
    category: A | B | C | D
    action: fix-in-place | extract-semantic-function | introduce-local-type | escalate-material-boundary | swiftlint-disable-with-reason
    target_location: <file path or affected boundary>
    notes: <one line on what to do / not do; for category B, state explicitly that no +Helpers is extracted>
```

The caller takes the plan and lands it itself. After landing, run the project's lint/check command (e.g. `just check`) to verify.

## Why (core)

Moving code into meaningless files only makes it physically shorter and organizationally scattered; first judge the real responsibility or API problem the lint exposed.
