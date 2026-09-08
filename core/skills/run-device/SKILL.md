---
name: run-device
description: Build, install, and launch the iOS app on a connected real iPhone. Use when the user asks to "install on a real device", "run it on the real device", "install on device", "run on device / on my iPhone", "deploy to my phone", "debug on device", "put it on my phone". Skip for the simulator (use `open-sim`), macOS, or release / archive.
---

# run-device

Resolve installed paths per the [host adapter](../../rules/host-adapter.md) before running helpers.

Build + install + launch the current iOS code on **a connected real device**. The mechanical part lives in the shared script `"$HARNESS_ROOT/scripts/run-ios.sh"` (`--target device`, shared with `open-sim`); this skill only calls it and relays the result.

## When to use

- Want a quick look on real hardware (runtime confidence: it compiles / installs / launches, and the resource pipeline is not broken)
- Debugging on device some behavior that only reproduces there

Not for: the simulator (use `open-sim`) · macOS · release / archive.

## Assumptions (device-specific)

- The iPhone is **plugged in + unlocked + has trusted this computer**, and is paired (visible in `xcrun devicectl list devices`)
- Signing is already set up in the repo's `Local.xcconfig` (`DEVELOPMENT_TEAM` + Automatic); a device build needs no extra configuration
- cwd is somewhere inside the iOS repo (worktree included), with a `justfile` findable upward

## Run

```bash
bash "$HARNESS_ROOT/scripts/run-ios.sh" --target device
```

The script will: auto-select the CoreDevice `identifier` of **the single reachable physical device** (first excluding simulators registered as CoreDevice via `hardwareProperties.reality == physical`, then narrowing by reachability; `identifier` is a UUID, e.g. `25CC377B-...`) → `<IOS_BUILD_DESTINATION>="platform=iOS,id=<id>" just build-ios` → locate the build artifact (scans `Build/Products/*-iphoneos/`, takes the newest `.app`; the configuration name is project-defined and can change, so `Debug-` is not hardcoded) → read the bundle id from the artifact's `Info.plist` → `devicectl device install app` + `process launch` → print the `----- run-ios result -----` result block.

- **Multiple reachable** physical devices connected → the script errors, lists only the reachable candidates for the user to pick, then pass the id:
  ```bash
  bash "$HARNESS_ROOT/scripts/run-ios.sh" --target device --device-id <identifier>
  ```
- Already built and you only want to reinstall → add `--no-build`.

## Report to the user

Relay the result block: which device it landed on (`WHERE=device:<name>`) + `UDID` (= the CoreDevice identifier) + `BUNDLE_ID` + `PID`. On any step failure the script emits `ERROR:` and exits non-zero — **report it to the user verbatim, do not switch approaches automatically**.

## Save context (optional)

A device build is slower than sim and the xcodebuild log is longer. To keep it out of the main conversation: on Claude dispatch Haiku / Sonnet; on Codex dispatch `command-runner` (Luna low), or Terra low when that role is not loaded. The subagent only runs the command and returns the result block; it does not judge code quality.

## Failure handling (script exit codes)

| Exit code | Meaning | What to do |
|---|---|---|
| 1 | No paired device / multiple reachable ones need disambiguation / multiple paired but none reachable / `devicectl` not ready | Have the user plug in + unlock + trust, or pass `--device-id` as prompted |
| 2 | Device build failed | Usually a bad connection / locked screen / not trusted / signing problem; report the xcodebuild error verbatim |
| 3 | No `.app` found | Only possible with `--no-build`; have the user drop `--no-build` and re-run |
| 4 | devicectl install / launch failed | Device plugged in + unlocked + trusted? launch only means something once install succeeds |

Device selection accepts only physical machines (`reality == physical`), then narrows by **reachability**: wired counts as reachable (even when `tunnelState` still shows `disconnected` — devicectl builds the tunnel only when it is needed), wireless must actually be `connected`. A phone stays in the CoreDevice pairing records long after it is unplugged, so judging by paired alone would force `--device-id` every day.

Branches after narrowing:

| Paired physical devices | Reachable | Behavior |
| ---- | ---- | ---- |
| 1 | any | Pick it; when unreachable, `WARN:` first and still try, letting the real xcodebuild / devicectl error be the backstop |
| N | exactly 1 | **Auto-selected**, printing `— only reachable one of N paired` as the reason |
| N | ≥2 | Error, listing only the reachable candidates |
| N | 0 | Error "no reachable device", listing all candidates |

## Out of scope

- ❌ Does not run `just generate` · does not switch scheme · does not touch the simulator (sim goes to `open-sim`)
- ❌ Does not configure signing / does not handle provisioning (assumes `Local.xcconfig` is ready)
- ❌ Does not skip the build unless the user explicitly asks (builds every time by default)
