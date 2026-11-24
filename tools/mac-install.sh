#!/bin/bash
# Builds an app signed for one connected device, installs it and opens it.
#
#   tools/mac-install.sh iphone          the stage 0 test app, on the iPhone
#   tools/mac-install.sh ipad            the stage 0 test app, on the iPad
#   tools/mac-install.sh iphone app      the notebook app itself, on the iPhone (iPhone only so far)
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

# The notebook app is for the iPhone only so far; its iPad version is a later stage.
if [ "${1:-}" = "ipad" ] && [ "${2:-test}" = "app" ]; then
  echo "The notebook app is for the iPhone only at this stage. Use: tools/mac-install.sh iphone app" | tee -a "$LOG"
  failed "choosing the app"
fi

# Which app: the stage 0 test app unless the second word is "app".
case "${2:-test}" in
  test) FOLDER="spike"; PROJECT="spike/Spike.xcodeproj"; SCHEME="Spike"; DERIVED="build/DerivedData" ;;
  app) FOLDER="App"; PROJECT="App/Scrivner.xcodeproj"; SCHEME="Scrivner"; DERIVED="build/DerivedData-app" ;;
  *) echo "The second word, if given, must be \"app\"." | tee -a "$LOG"; failed "choosing the app" ;;
esac
if [ ! -f "$FOLDER/Local.xcconfig" ]; then
  echo "$FOLDER/Local.xcconfig is missing. Run tools/mac-bootstrap.sh first." | tee -a "$LOG"
  failed "local settings"
fi

generate_project() {
  (cd "$FOLDER" && ../.tools/xcodegen/bin/xcodegen generate)
}

signed_build() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build
}

APP="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"

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
