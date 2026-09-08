---
name: find-ios-build-artifact
description: Locate a just-built iOS Simulator `.app` and the per-worktree Simulator UDID. Output `APP_PATH`, `BUNDLE_ID`, and `SIMULATOR_UDID` for UI review/open-sim callers. Skip when all values are already known, no `.xcworkspace` ancestor exists, the app has not been built, or the target is macOS/device.
---

# find-ios-build-artifact

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

After an iOS Simulator build finishes, find the build artifact `.app` path + bundle id + **the simulator UDID bound to the current worktree**. The caller feeds these three values to `simctl install -d <udid> <app>` / `simctl launch <udid> <bundle>` / sim-use (the `--device <udid>` argument).

Parallel session isolation: each worktree uses its own sim (`sim-<slug>`), lazily managed by `"$HARNESS_ROOT/scripts/worktree-sim.sh" ensure`. Two sessions running at once will not fight over the same one.

## Triggers

The caller's SOP needs all three of `APP_PATH` / `BUNDLE_ID` / `SIMULATOR_UDID`, and an iOS Simulator build has already run. Common cases:

- **ui-reviewer**: the UI gate already has build evidence; locate the build artifact to prepare install + launch
- **open-sim** skill: the user says "open the simulator" → Step 2 takes the build artifact and installs + launches
- Any caller that wants to install an already-built iOS Simulator app onto a simulator and run it

## Does not trigger

- The caller already got `APP_PATH` + `BUNDLE_ID` from the main agent / a previous step
- The project has no `.xcworkspace` (bare `.xcodeproj` or SPM-only) — this skill assumes a workspace path; the caller has to adapt on its own
- Running a macOS / device build (this skill assumes destination = `generic/platform=iOS Simulator`)
- No build has run yet — `xcodebuild -showBuildSettings` still runs without a build, but the `.app` does not actually exist; this skill reports `BUILD_ARTIFACT_NOT_FOUND` and lets the caller decide the next step

## Steps

### Step 1: locate the workspace

Walk up from cwd looking for a `.xcworkspace` folder (many projects keep it at the repo root, but a monorepo may have it in a subdirectory):

```bash
WORKSPACE_DIR="$(pwd)"
WORKSPACE_NAME=""
while [[ "$WORKSPACE_DIR" != "/" ]]; do
  # any .xcworkspace in the current directory
  found=$(find "$WORKSPACE_DIR" -maxdepth 1 -name '*.xcworkspace' -type d 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    WORKSPACE_NAME="$(basename "$found")"
    break
  fi
  WORKSPACE_DIR="$(dirname "$WORKSPACE_DIR")"
done
[[ -n "$WORKSPACE_NAME" ]] || { echo "BUILD_ARTIFACT_NOT_FOUND: no .xcworkspace ancestor"; exit 1; }
```

### Step 2: determine the scheme

The caller should pass the scheme name (e.g. `<YourApp>iOS` / `MyAppiOS`). If it did not:

```bash
# list every scheme in the workspace and let the caller pick
xcrun xcodebuild -workspace "$WORKSPACE_DIR/$WORKSPACE_NAME" -list 2>/dev/null | sed -n '/Schemes:/,$p'
```

Selection heuristic (when the caller did not specify):

- The repo root's `AGENTS.md` / `Justfile` names the main scheme → use it
- Prefer scheme names containing the `iOS` / `iphone` keyword
- Otherwise take the first entry, and note in the output "scheme auto-selected, may be wrong"

### Step 3: get build settings

```bash
SETTINGS=$(cd "$WORKSPACE_DIR" && xcodebuild -workspace "$WORKSPACE_NAME" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null)
```

Extract 3 fields:

```bash
BUILT_DIR=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR =/ {print $2; exit}')
APP_NAME=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*FULL_PRODUCT_NAME =/ {print $2; exit}')
BUNDLE_ID=$(echo "$SETTINGS" | awk -F' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER =/ {print $2; exit}')
APP_PATH="$BUILT_DIR/$APP_NAME"
```

### Step 4: verify the `.app` actually exists

```bash
[[ -d "$APP_PATH" ]] || { echo "BUILD_ARTIFACT_NOT_FOUND: $APP_PATH does not exist — run just build-ios / Xcode build / xcodebuild build first"; exit 1; }
```

`-showBuildSettings` **returns a path** even before a build, while the `.app` does not actually exist. Verify it so the caller does not carry a nonexistent path into a failing `simctl install`.

### Step 5: get the per-worktree simulator UDID

Run only when cwd is inside `.worktrees/<slug>/` (sub-worktree included). For the main repo / a non-worktree cwd, skip this step and output an empty `SIMULATOR_UDID`.

```bash
SIM_OUT=$(bash "$HARNESS_ROOT/scripts/worktree-sim.sh" ensure 2>&1) && {
  SIMULATOR_UDID=$(echo "$SIM_OUT" | awk -F= '/^SIMULATOR_UDID=/ {print $2}')
} || {
  # not in a worktree (exit 1) / no .xcworkspace (exit 2) → not fatal, leave empty and let the caller use its fallback
  # simctl failed (exit 3) → same, the caller checks its own environment
  SIMULATOR_UDID=""
}
```

#### Optional: create an extra sim on a specific runtime

`worktree-sim.sh ensure` takes an optional `--runtime <id>` argument that creates one **extra** sim bound to the given runtime (it does not replace the default `sim-<slug>`); its UDID is stored in `.claude/sim-udid-<runtime-suffix>`. Typical use:

```bash
# create and boot an iOS 18.6 sim (coexists alongside sim-<slug>)
bash "$HARNESS_ROOT/scripts/worktree-sim.sh" ensure --runtime iOS-18-6
# → sim-<slug>-ios18-6, UDID stored in .claude/sim-udid-ios18-6
```

Calling it with no argument stays backward compatible (defaults to the newest runtime). For `--runtime` edge cases (fallback on an incompatible device type / error when the runtime is not installed / shutdown/delete interaction), see the header comment of `"$HARNESS_ROOT/scripts/worktree-sim.sh"`.

### Step 6: output

The caller uses `eval` or source to get the four variables; or this skill just prints KEY=VALUE for the caller to parse:

```bash
echo "APP_PATH=$APP_PATH"
echo "BUNDLE_ID=$BUNDLE_ID"
echo "SIMULATOR_UDID=$SIMULATOR_UDID"   # may be empty (cwd not in a worktree / not an iOS project / simctl failed)
echo "WORKSPACE=$WORKSPACE_DIR/$WORKSPACE_NAME"
echo "SCHEME=$SCHEME"
```

## Error handling

| Failure | Error code | What the caller does |
|---|---|---|
| No `.xcworkspace` ancestor | `BUILD_ARTIFACT_NOT_FOUND: no .xcworkspace ancestor` | Caller checks whether cwd is inside the repo; bare xcodeproj / SPM-only projects use another route |
| `-showBuildSettings` returns empty / fields missing | `BUILD_ARTIFACT_NOT_FOUND: cannot parse build settings` | Usually a wrong scheme name; caller cross-checks with `xcodebuild -list` |
| `.app` does not exist | `BUILD_ARTIFACT_NOT_FOUND: <path> does not exist` | Caller returns `DEGRADED build_artifact_not_found`; do not add a build inside this skill |
| `SIMULATOR_UDID` empty while the caller runs inside a worktree | No error in the structured output, only a WARN on stderr | Callers such as review-mobile-ui check their own cwd / fall back to the old "count booted sims" fallback |

**Do not** run `xcodebuild build` yourself to fill the gap — the build is the caller's / user's responsibility; this skill only locates the build artifact.
**Do not** boot / install / launch the app yourself — this skill only ensures the sim exists and is booted; install + launch is run by the caller once it has `SIMULATOR_UDID`.

## Caller integration examples

### UI reviewer

```
Skill(find-ios-build-artifact)   # input: scheme = <YourApp>iOS
# output: APP_PATH=/path/to/<YourApp>.app, BUNDLE_ID=<your.bundle.id>, SIMULATOR_UDID=A1B2-...

# build artifact fails → return DEGRADED build_artifact_not_found
# SIMULATOR_UDID empty (not a worktree / simctl failed) → use the review-mobile-ui Step 2 fallback
# success → simctl install -d $SIMULATOR_UDID $APP_PATH; simctl launch $SIMULATOR_UDID $BUNDLE_ID
```

### open-sim skill Step 2

```
Skill(find-ios-build-artifact)   # input: scheme = <YourApp>iOS
# failure → tell the user to "run just build-ios first"
# success → Step 3 installs + launches with $SIMULATOR_UDID (no sim picker for the user — the worktree is already bound)
```

## Out of scope

- ❌ **No build** — when nothing was built / the artifact does not exist, it only errors and lets the caller decide the next step
- ❌ **No scheme guessing** — the caller must pass one, or this skill lists the schemes for the caller to pick
- ❌ **No macOS / device handling** — destination is hardcoded to `generic/platform=iOS Simulator`
- ❌ **No installing / launching the app** — that is the caller's job (`simctl install/launch` or an mcp tool)
- ❌ **No caller-picked simulator** — the per-worktree UDID is decided solely by `worktree-sim.sh ensure`; the caller does not pick another

## Why (core)

- The three fields (`APP_PATH` / `BUNDLE_ID` / `SIMULATOR_UDID`) are emitted as one package — the caller gets everything install/launch needs in one go
- `SIMULATOR_UDID` comes from `worktree-sim.sh ensure`: lazily create + boot a per-worktree `sim-<slug>`, so parallel sessions each have their own sim and the sim-use `--device` argument routes precisely
