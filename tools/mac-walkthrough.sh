#!/bin/bash
# Builds the app for the simulator, walks through it the way a person would (the UI tests in
# App/UITests), and saves a picture of each screen to build/screenshots/.
#
#   tools/mac-walkthrough.sh
#
# Runs on a Mac. The simulated phone is "iPhone 17 Pro" unless SCRIVNER_SIMULATOR names another.
# The log is saved to build/logs/walkthrough-<time>.log, scrubbed like the other logs.
# Last line: "WALKTHROUGH OK (<n> screenshots)" or "WALKTHROUGH FAILED: <why>, log: <path>".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=tools/mac-lib.sh
. tools/mac-lib.sh
use_installed_xcode

mkdir -p build/logs
LOG="build/logs/walkthrough-$(date +%Y%m%d-%H%M%S).log"
DEVICE="${SCRIVNER_SIMULATOR:-iPhone 17 Pro}"
RESULT="build/walkthrough.xcresult"

fail() {
  echo "WALKTHROUGH FAILED: $1, log: $LOG"
  exit 1
}

[ -x .tools/xcodegen/bin/xcodegen ] || fail "XcodeGen is missing; run tools/mac-bootstrap.sh first"
[ -f App/Local.xcconfig ] || cp spike/Local.xcconfig App/Local.xcconfig 2>/dev/null \
  || fail "App/Local.xcconfig is missing; run tools/mac-bootstrap.sh first"

echo "== app project generation" | tee -a "$LOG"
(cd App && ../.tools/xcodegen/bin/xcodegen generate) 2>&1 | scrub | tee -a "$LOG"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "the app's project could not be generated"

echo "== walkthrough on $DEVICE" | tee -a "$LOG"
rm -rf "$RESULT" build/screenshots build/screenshots-raw
xcodebuild test \
  -project App/Scrivner.xcodeproj \
  -scheme Scrivner \
  -destination "platform=iOS Simulator,name=$DEVICE,OS=latest" \
  -derivedDataPath build/DerivedData-walkthrough \
  -resultBundlePath "$RESULT" \
  2>&1 | scrub | tee -a "$LOG" | grep -E "^(Test Case|Test Suite|\*\*|.*error:|.*: error|Testing started|.*passed|.*failed)" || true
status="${PIPESTATUS[0]}"

# The pictures are kept whether or not every step passed: a failed step's picture says why.
echo "== screenshots" | tee -a "$LOG"
count=0
if [ -d "$RESULT" ]; then
  xcrun xcresulttool export attachments --path "$RESULT" --output-path build/screenshots-raw >>"$LOG" 2>&1 || true
  if [ -f build/screenshots-raw/manifest.json ]; then
    count="$(/usr/bin/python3 - build/screenshots-raw build/screenshots <<'PY'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
with open(os.path.join(raw, "manifest.json"), encoding="utf-8") as handle:
    manifest = json.load(handle)
count = 0
for test in manifest:
    for attachment in test.get("attachments", []):
        source = os.path.join(raw, attachment.get("exportedFileName", ""))
        if not os.path.isfile(source):
            continue
        name = attachment.get("suggestedHumanReadableName") or attachment.get("exportedFileName")
        # "margin-layout_0_ABCD-....png" -> "margin-layout.png"
        stem, extension = os.path.splitext(name)
        stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", stem)
        stem = re.sub(r"[^A-Za-z0-9._-]+", "-", stem) or "screenshot"
        target = os.path.join(out, stem + (extension or ".png"))
        number = 2
        while os.path.exists(target):
            target = os.path.join(out, f"{stem}-{number}{extension or '.png'}")
            number += 1
        shutil.copyfile(source, target)
        count += 1
print(count)
PY
)"
  fi
fi
ls build/screenshots 2>/dev/null | tee -a "$LOG"

[ "$status" -eq 0 ] || fail "a step of the walkthrough did not pass (${count:-0} screenshots were still saved to build/screenshots)"
echo "WALKTHROUGH OK (${count:-0} screenshots)"
