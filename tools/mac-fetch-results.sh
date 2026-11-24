#!/bin/bash
# Copies the test app's run folders off a connected device, then keeps only the reports.
#
#   tools/mac-fetch-results.sh iphone
#   tools/mac-fetch-results.sh ipad
#
# Everything from the device lands in build/fetched/<hardware model>/runs/, which is never
# committed: that is where to listen to recordings and watch clips. Only each run's report.txt
# is copied into docs/spike/results/<hardware model>/<run folder>/.
# Last line: "RESULT: FETCHED <n> reports" or "RESULT: FAILED at <step>".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=tools/mac-lib.sh
. tools/mac-lib.sh

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
  --destination "$dest/runs" 2>&1 | sed "s/$DEVICE_UDID/<device>/g"
[ "${PIPESTATUS[0]}" -eq 0 ] || failed "copying from the device"

count=0
for report in "$dest"/runs/*/report.txt; do
  [ -f "$report" ] || continue
  run="$(basename "$(dirname "$report")")"
  mkdir -p "docs/spike/results/$DEVICE_MODEL/$run"
  cp "$report" "docs/spike/results/$DEVICE_MODEL/$run/report.txt"
  count=$((count + 1))
done

echo "RESULT: FETCHED $count reports"
