#!/usr/bin/env bash
# record-ui-animation / Step B (the only recording path — straight to xcrun simctl)
#
# Depends on no UI interaction tool — this script only records.
# The caller drives the animation-triggering actions (tap / type / swipe) separately via sim-use; that is outside this script.
#
# Usage:
#   1. The caller runs this script in the foreground; it forks simctl io into the background and prints the PID
#   2. The caller takes that PID and drives the animation itself
#   3. The caller calls stop-xcrun.sh with that PID to end the recording
#
# Inputs (env):
#   DEVICE_UDID
#   RECORDING_PATH
#
# Outputs:
#   REC_PID=<pid>
#   REC_STARTED_AT=<unix-ts>

set -euo pipefail
: "${DEVICE_UDID:?}"
: "${RECORDING_PATH:?}"

if [[ ! "$RECORDING_PATH" =~ \.mp4$ ]]; then
  echo "ERR_RECORDING_PATH_MUST_BE_MP4:$RECORDING_PATH"
  exit 1
fi

# h264 extracts frames a little faster than hevc and has the best ffmpeg/videotoolbox compatibility.
# Critical: redirect simctl's stdout/stderr to a log file. Otherwise, when the caller
# invokes this script as `eval "$(record-xcrun.sh)"`, the background simctl process holds the
# parent shell's fd → the command substitution never sees EOF and the whole eval hangs.
LOG_PATH="${RECORDING_PATH%.mp4}.simctl.log"
xcrun simctl io "$DEVICE_UDID" recordVideo --codec=h264 --force "$RECORDING_PATH" \
  </dev/null >"$LOG_PATH" 2>&1 &
REC_PID=$!
disown 2>/dev/null || true

# Wait for simctl to write the first frame before returning, so a caller that acts with zero delay does not lose the opening frames
sleep 0.6

if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "ERR_SIMCTL_DIED_EARLY: recordVideo exited before the first frame (log=${LOG_PATH})"
  exit 1
fi

echo "REC_PID=$REC_PID"
echo "REC_STARTED_AT=$(date +%s)"
echo "REC_LOG=$LOG_PATH"
