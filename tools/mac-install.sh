#!/bin/bash
# Builds the test app signed for one connected device, installs it and opens it.
#
#   tools/mac-install.sh iphone
#   tools/mac-install.sh ipad
#
# The device must be connected by cable and unlocked.
# Everything is shown on screen and saved to build/logs/install-<time>.log.
# Last line: "RESULT: INSTALLED on <hardware model>" or "RESULT: FAILED at <step>, log: <path>".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=tools/mac-lib.sh
. tools/mac-lib.sh

mkdir -p build/logs
LOG="build/logs/install-$(date +%Y%m%d-%H%M%S).log"

failed() {
  echo "RESULT: FAILED at $1, log: $LOG"
  exit 1
}

run_step() {
  local name="$1"
  shift
  echo "== $name" | tee -a "$LOG"
  "$@" 2>&1 | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" -eq 0 ] || failed "$name"
}

echo "== find device" | tee -a "$LOG"
find_device "${1:-}" 2> >(tee -a "$LOG" >&2) || failed "find device"
echo "Found $DEVICE_MODEL" | tee -a "$LOG"

generate_project() {
  (cd spike && ../.tools/xcodegen/bin/xcodegen generate)
}

# The log must not hold the device's identifier, so the signed build's output is filtered.
signed_build() {
  xcodebuild \
    -project spike/Spike.xcodeproj \
    -scheme Spike \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath build/DerivedData \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build 2>&1 | sed "s/$DEVICE_UDID/<device>/g"
  return "${PIPESTATUS[0]}"
}

APP="build/DerivedData/Build/Products/Debug-iphoneos/Spike.app"

install_app() {
  xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" 2>&1 | sed "s/$DEVICE_UDID/<device>/g"
  return "${PIPESTATUS[0]}"
}

launch_app() {
  local bundle_id
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" || return 1
  xcrun devicectl device process launch --device "$DEVICE_UDID" "$bundle_id" 2>&1 | sed "s/$DEVICE_UDID/<device>/g"
  return "${PIPESTATUS[0]}"
}

run_step "project generation" generate_project
run_step "signed build" signed_build
[ -d "$APP" ] || failed "signed build (no app was produced)"
run_step "install" install_app
run_step "launch" launch_app

echo "RESULT: INSTALLED on $DEVICE_MODEL"
