---
name: record-ui-animation
description: Capture iOS/Android Simulator motion as keyframe PNGs for agent inspection. Use for animation, transition, morph, loading, gesture, keyboard, toast, sheet, or other time-dependent UI evidence. Skip static UI, pure logic, real devices, and desktop targets.
---

# Record UI animation

This skill only captures the recording and keyframes; it does not navigate, trigger actions or decide PASS/FAIL. The caller drives the app per the final plan's dynamic cases and judges by reading the frame sequence.

## Inputs

| Variable | Requirement |
| --- | --- |
| `WORKTREE_SLUG` | Required, a safe short identifier |
| `CASE_SLUG` | Required, kebab-case case name |
| `DEVICE_UDID` | Required, target Simulator/emulator |
| `EXPECTED_DURATION_SECONDS` | Default 3 |
| `FRAME_COUNT` | Default 10; 6–8 for short animations, 10–15 for long ones |
| `PLATFORM` | Default `ios`; `android` optional |

The output directory is `.reviews/ui-<slug>-<timestamp>/animation/<case>/`.

## Capture lifecycle

### Prepare

```bash
eval "$(WORKTREE_SLUG="$WORKTREE_SLUG" CASE_SLUG="$CASE_SLUG" \
  DEVICE_UDID="$DEVICE_UDID" \
  EXPECTED_DURATION_SECONDS="${EXPECTED_DURATION_SECONDS:-3}" \
  FRAME_COUNT="${FRAME_COUNT:-10}" PLATFORM="${PLATFORM:-ios}" \
  bash ~/.claude/skills/record-ui-animation/scripts/prepare.sh)"
```

Returns `RECORDING_PATH`, `FRAMES_DIR`, `META_PATH` and `DEVICE_UDID`. When dependency or device validation fails, degrade per the script's error code.

### Record, act, stop

Start recording only after reaching the animation's starting point; keep navigation actions out of the measured time window.

```bash
eval "$(DEVICE_UDID="$DEVICE_UDID" RECORDING_PATH="$RECORDING_PATH" \
  bash ~/.claude/skills/record-ui-animation/scripts/record-xcrun.sh)"

# The caller performs the single trigger action specified by the final plan here; every sim-use carries --device.

sleep <expected-duration-plus-buffer>

REC_PID="$REC_PID" RECORDING_PATH="$RECORDING_PATH" \
  bash ~/.claude/skills/record-ui-animation/scripts/stop-xcrun.sh
```

`stop-xcrun.sh` uses SIGINT so simctl finalizes the MP4; do not switch to SIGTERM/KILL.

### Extract

```bash
RECORDING_PATH="$RECORDING_PATH" FRAMES_DIR="$FRAMES_DIR" \
  META_PATH="$META_PATH" FRAME_COUNT="${FRAME_COUNT:-10}" SCALE=0.5 \
  bash ~/.claude/skills/record-ui-animation/scripts/extract.sh
```

Returns `FRAMES_DIR`, the actual frame count, the duration and `META_PATH`. The default 0.5 scale keeps the multi-image context small; use 1.0 only for pixel-level issues.

## Judgment handoff

The caller reads every output frame, compares against the case's start, middle and end states and its timing, and returns evidence paths and observations. Record an environment limitation when there are fewer than 2 frames, keyframes are missing or the recording failed; retry once only after finding and fixing a specific environmental cause, never record blindly.

## Constraints

- Does not boot, build, install or launch the app automatically.
- Does not tap, type, swipe or change Simulator settings; the caller does those inside the recording window per the case.
- Does not judge the animation, does not produce GIFs, does not share one recording across devices.
- Static frame/spacing/color use the screenshot path, not screen recording.
