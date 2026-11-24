#!/bin/bash
# Checks that everything compiles, without signing:
#   1. the Mac is set up            (tools/mac-bootstrap.sh)
#   2. the SpikeKit tests pass      (swift test)
#   3. the Xcode project generates  (XcodeGen)
#   4. the app compiles for a device
#
# Everything is shown on screen and saved to build/logs/build-<time>.log, with anything that
# identifies a person or a device replaced by a placeholder.
# Last line: "RESULT: OK" or "RESULT: FAILED at <step>, log: <path>".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=tools/mac-lib.sh
. tools/mac-lib.sh
use_installed_xcode

mkdir -p build/logs
LOG="build/logs/build-$(date +%Y%m%d-%H%M%S).log"

run_step() {
  local name="$1"
  shift
  echo "== $name" | tee -a "$LOG"
  "$@" 2>&1 | scrub | tee -a "$LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "RESULT: FAILED at $name, log: $LOG"
    exit 1
  fi
}

generate_project() {
  (cd spike && ../.tools/xcodegen/bin/xcodegen generate)
}

run_step "setup check" tools/mac-bootstrap.sh
run_step "SpikeKit tests" swift test --package-path spike/SpikeKit
run_step "project generation" generate_project
run_step "compile" xcodebuild \
  -project spike/Spike.xcodeproj \
  -scheme Spike \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "RESULT: OK"
