#!/usr/bin/env bash
# record-ui-animation / Step B wrap-up (xcrun backend)
#
# Inputs (env):
#   REC_PID            the PID printed by record-xcrun.sh
#   RECORDING_PATH     used to check the file was actually written
#
# Outputs:
#   RECORDING_SIZE=<bytes>
#   RECORDING_PATH=<abs>

set -euo pipefail
: "${REC_PID:?}"
: "${RECORDING_PATH:?}"

if kill -0 "$REC_PID" 2>/dev/null; then
  # SIGINT lets simctl finalize the mp4 and write the moov atom. Never SIGTERM/KILL — that corrupts the artifact.
  kill -INT "$REC_PID"
  # `wait $PID` returns immediately when the PID is not a child of the current shell (a process forked
  # inside a command substitution belongs to the parent shell, not to this script), so poll `kill -0` instead.
  # simctl finalize usually takes <2s; allow 10s as a backstop and never force-kill on timeout (force-kill = corrupt mp4).
  for _ in $(seq 1 50); do
    kill -0 "$REC_PID" 2>/dev/null || break
    sleep 0.2
  done
fi

[[ -f "$RECORDING_PATH" ]] || { echo "ERR_RECORDING_MISSING:$RECORDING_PATH"; exit 1; }

SIZE=$(stat -f%z "$RECORDING_PATH" 2>/dev/null || stat -c%s "$RECORDING_PATH")
if [[ "$SIZE" -lt 1024 ]]; then
  echo "ERR_RECORDING_TOO_SMALL:$SIZE bytes (mp4 corrupt or premature SIGINT)"
  exit 1
fi

echo "RECORDING_SIZE=$SIZE"
echo "RECORDING_PATH=$RECORDING_PATH"
