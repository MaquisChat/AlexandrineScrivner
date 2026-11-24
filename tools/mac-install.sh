#!/bin/bash
# Builds the test app signed for one connected device, installs it and opens it.
#
#   tools/mac-install.sh iphone
#   tools/mac-install.sh ipad
#
# The device must be connected by cable and unlocked.
# Everything is shown on screen and saved to build/logs/install-<time>.log, with anything that
# identifies a person or a device replaced by a placeholder.
# Last line: "RESULT: INSTALLED on <hardware model>" or "RESULT: FAILED at <step>, log: <path>".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=tools/mac-lib.sh
. tools/mac-lib.sh
use_installed_xcode

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
  "$@" 2>&1 | scrub | tee -a "$LOG"
  [ "${PIPESTATUS[0]}" -eq 0 ] || failed "$name"
}

echo "== find device" | tee -a "$LOG"
problem="$(mktemp -t install.XXXXXX)"
if ! find_device "${1:-}" 2> "$problem"; then
  tee -a "$LOG" < "$problem"
  rm -f "$problem"
  failed "find device"
fi
rm -f "$problem"
echo "Found $DEVICE_MODEL" | tee -a "$LOG"

generate_project() {
  (cd spike && ../.tools/xcodegen/bin/xcodegen generate)
}

signed_build() {
  xcodebuild \
    -project spike/Spike.xcodeproj \
    -scheme Spike \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath build/DerivedData \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build
}

APP="build/DerivedData/Build/Products/Debug-iphoneos/Spike.app"

install_app() {
  xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
}

launch_app() {
  local bundle_id
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" || return 1
  xcrun devicectl device process launch --device "$DEVICE_UDID" "$bundle_id"
}

run_step "project generation" generate_project
run_step "signed build" signed_build
[ -d "$APP" ] || failed "signed build (no app was produced)"
run_step "install" install_app

echo "== launch" | tee -a "$LOG"
launch_app 2>&1 | scrub | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  {
    echo "The app is installed but could not be opened."
    echo "Unlock the device. The first time, do step 6 of docs/guides/mac-setup.md (trust the"
    echo "developer app on the device), then run this again."
  } | tee -a "$LOG"
  failed "launch"
fi

echo "RESULT: INSTALLED on $DEVICE_MODEL"
