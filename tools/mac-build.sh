#!/bin/bash
# Checks that everything compiles, without signing:
#   1. the Mac is set up            (tools/mac-bootstrap.sh)
#   2. the Core tests pass          (swift test)
#   3. the session checker passes the worked example and catches faults in copies of it
#   4. the SpikeKit tests pass      (swift test)
#   5. the Xcode project generates  (XcodeGen)
#   6. the test app compiles for a device
#   7. the app's project generates, and the app compiles for a device
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

generate_app_project() {
  (cd App && ../.tools/xcodegen/bin/xcodegen generate)
}

run_step "setup check" tools/mac-bootstrap.sh
run_step "Core tests" swift test --package-path Core
run_step "example check" tools/check-example.sh
run_step "SpikeKit tests" swift test --package-path spike/SpikeKit
run_step "project generation" generate_project
run_step "compile" xcodebuild \
  -project spike/Spike.xcodeproj \
  -scheme Spike \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

run_step "app project generation" generate_app_project
run_step "app compile" xcodebuild \
  -project App/Scrivner.xcodeproj \
  -scheme Scrivner \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData-app \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "RESULT: OK"
