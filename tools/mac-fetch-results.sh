#!/bin/bash
# Copies the test app's run folders off a connected device, then keeps only the reports.
#
#   tools/mac-fetch-results.sh iphone
#   tools/mac-fetch-results.sh ipad
#
# Everything from the device lands in build/fetched/<hardware model>/, which is never
# committed: that is where to listen to recordings and watch clips. Only each run's report.txt
# is copied into docs/spike/results/<hardware model>/<run folder>/.
# Last line: "RESULT: FETCHED <n> reports" or "RESULT: FAILED at <step>".
#
# NOT YET CONFIRMED ON A MAC: whether `devicectl device copy from` copies a whole folder as
# written below, or needs an extra option to do so. Check `xcrun devicectl help device copy from`
# the first time this is used (plan Task 8, step 2).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=tools/mac-lib.sh
. tools/mac-lib.sh
use_installed_xcode

failed() {
  echo "RESULT: FAILED at $1"
  exit 1
}

find_device "${1:-}" || failed "find device"

prefix="$(awk -F'= *' '/^BUNDLE_ID_PREFIX/ { print $2; exit }' spike/Local.xcconfig 2>/dev/null)"
[ -n "$prefix" ] || failed "reading the app's identifier (run tools/mac-bootstrap.sh first)"
bundle_id="$prefix.spike"

dest="build/fetched/$DEVICE_MODEL"
rm -rf "$dest"
mkdir -p "$dest"

xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$bundle_id" \
  --source Documents/runs \
  --destination "$dest/runs" 2>&1 | scrub
[ "${PIPESTATUS[0]}" -eq 0 ] || failed "copying from the device"

# Wherever the folder landed under $dest, every run is a folder holding a report.txt.
count=0
while IFS= read -r report; do
  run="$(basename "$(dirname "$report")")"
  mkdir -p "docs/spike/results/$DEVICE_MODEL/$run"
  cp "$report" "docs/spike/results/$DEVICE_MODEL/$run/report.txt"
  count=$((count + 1))
done < <(find "$dest" -type f -name report.txt)

if [ "$count" -eq 0 ]; then
  echo "Nothing was copied. Either no run has been made on this device yet, or the copy needs an"
  echo "extra option to take a whole folder: see 'xcrun devicectl help device copy from'."
  failed "finding reports in what was copied"
fi

echo "RESULT: FETCHED $count reports"
