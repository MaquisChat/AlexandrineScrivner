#!/bin/bash
# Builds the app for the simulator, walks through it the way a person would (the UI tests in
# App/UITests), and saves a picture of each screen to build/screenshots/.
#
#   tools/mac-walkthrough.sh
#
# Runs on a Mac. The simulated phone is "iPhone 17 Pro" unless SCRIVNER_SIMULATOR names another.
# The log is saved to build/logs/walkthrough-<time>.log, scrubbed like the other logs.
# The session folders the app wrote in the simulator are copied to build/walkthrough-sessions/ and
# checked with scrivner-check: what the app writes must be a session folder the checker accepts.
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

# The newest simulator of that name, by its own identifier, so that the same one can be asked
# afterwards for the files the app wrote.
SIMULATOR="$(xcrun simctl list devices available -j 2>>"$LOG" | /usr/bin/python3 -c '
import json, re, sys
want = sys.argv[1]
found = []
for runtime, devices in json.load(sys.stdin).get("devices", {}).items():
    version = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not version:
        continue
    for device in devices:
        if device.get("name") == want and device.get("isAvailable", True):
            found.append(((int(version.group(1)), int(version.group(2))), device["udid"]))
print(sorted(found)[-1][1] if found else "")
' "$DEVICE")"
[ -n "$SIMULATOR" ] || fail "there is no simulator called $DEVICE"
xcrun simctl boot "$SIMULATOR" >>"$LOG" 2>&1 || true        # already booted is fine
xcrun simctl bootstatus "$SIMULATOR" -b >>"$LOG" 2>&1 || fail "the simulator did not start"

echo "== walkthrough on $DEVICE" | tee -a "$LOG"
rm -rf "$RESULT" build/screenshots build/screenshots-raw
xcodebuild test \
  -project App/Scrivner.xcodeproj \
  -scheme Scrivner \
  -destination "platform=iOS Simulator,id=$SIMULATOR" \
  -parallel-testing-enabled NO \
  -derivedDataPath build/DerivedData-walkthrough \
  -resultBundlePath "$RESULT" \
  2>&1 | scrub | tee -a "$LOG" | grep -E "^(Test Case|Test Suite|\*\*|.*error:|.*: error|Testing started|.*passed|.*failed)"
# The first command's own result: nothing may come between the pipeline and this line.
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

# With SCRIVNER_PRINT_SCREENSHOTS=1, a small copy of each picture is also printed as text, so the
# pictures can be read back out of a log where the files themselves cannot be fetched.
if [ "${SCRIVNER_PRINT_SCREENSHOTS:-0}" = "1" ]; then
  mkdir -p build/screenshots-small
  for picture in build/screenshots/*.png; do
    [ -f "$picture" ] || continue
    small="build/screenshots-small/$(basename "${picture%.png}").jpg"
    sips -Z 900 -s format jpeg -s formatOptions 55 "$picture" --out "$small" >/dev/null 2>&1 || continue
    echo "-----BEGIN SCREENSHOT $(basename "$small")-----"
    base64 -i "$small" | fold -w 160
    echo "-----END SCREENSHOT-----"
  done
  for description in build/screenshots/*.txt; do
    [ -f "$description" ] || continue
    echo "-----BEGIN SCREEN DESCRIPTION $(basename "$description")-----"
    head -c 60000 "$description"
    echo
    echo "-----END SCREEN DESCRIPTION-----"
  done
fi

[ "$status" -eq 0 ] || fail "a step of the walkthrough did not pass (${count:-0} screenshots were still saved to build/screenshots)"

# What the app wrote. The last step of the walkthrough leaves one finished session behind for this.
echo "== the session folders the app wrote" | tee -a "$LOG"
bundle="$(awk -F'= *' '/^BUNDLE_ID_PREFIX/ { print $2; exit }' App/Local.xcconfig).scrivner"
xcrun simctl bootstatus "$SIMULATOR" -b >>"$LOG" 2>&1 || true
container="$(xcrun simctl get_app_container "$SIMULATOR" "$bundle" data 2>>"$LOG")" \
  || fail "the app's files could not be found in the simulator"
rm -rf build/walkthrough-sessions
mkdir -p build/walkthrough-sessions
cp -R "$container/Documents/Sessions/." build/walkthrough-sessions/ 2>>"$LOG" \
  || fail "the app's Sessions folder could not be copied out of the simulator"

if ! build_output="$(swift build --package-path Core --product scrivner-check 2>&1)"; then
  echo "$build_output" | scrub | tee -a "$LOG"
  fail "the checker does not build"
fi
check="$(swift build --package-path Core --show-bin-path)/scrivner-check"
"$check" build/walkthrough-sessions 2>&1 | scrub | tee -a "$LOG"
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "the checker does not accept a session folder the app wrote"

# For information only in this stage: the stand-in recorder does not write the tags a real
# recording will carry, so problems are expected for audio. Stage 1c has to make this pass.
echo "== what is inside the media files (for information; stand-in hardware)" | tee -a "$LOG"
exiftool="$(tools/get-exiftool.sh 2>>"$LOG" | tail -1)" || true
if [ -n "${exiftool:-}" ] && [ -x "$exiftool" ]; then
  "$check" --media --exiftool "$exiftool" build/walkthrough-sessions 2>&1 | scrub | tee -a "$LOG" || true
fi

# With SCRIVNER_PRINT_SCREENSHOTS=1, what the app wrote is printed too: the record of each session
# and its notes, as the workbench and a person would read them.
if [ "${SCRIVNER_PRINT_SCREENSHOTS:-0}" = "1" ]; then
  find build/walkthrough-sessions -type f | sort | sed 's/^/  /'
  for record in build/walkthrough-sessions/*/session.json build/walkthrough-sessions/*/notes.md; do
    [ -f "$record" ] || continue
    echo "-----BEGIN SCREEN DESCRIPTION $(basename "$(dirname "$record")" | tr ' /' '__')__$(basename "$record").txt-----"
    head -c 40000 "$record"
    echo
    echo "-----END SCREEN DESCRIPTION-----"
  done
fi

echo "WALKTHROUGH OK (${count:-0} screenshots)"
