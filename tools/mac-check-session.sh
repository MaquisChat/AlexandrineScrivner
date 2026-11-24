#!/bin/bash
# Checks session folders brought over from the phone, before they go into the research workbench.
#
#   tools/mac-check-session.sh FOLDER...
#
# FOLDER is one session folder, or a folder holding several. The report is shown on screen and
# saved to build/logs/session-check-<time>.log, with anything that identifies this Mac's owner
# replaced by a placeholder. Session titles are kept, so read the log before sharing it.
# Where the report is saved is said first. Last line: "SESSION CHECK OK (...)" or "SESSION CHECK FAILED (...)".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -lt 1 ]; then
  echo "Say which folder to check, for example: tools/mac-check-session.sh ~/Desktop/Sessions"
  echo "SESSION CHECK FAILED (no folder given)"
  exit 2
fi

# Folders are given relative to where the command was typed; work them out before moving.
folders=()
for folder in "$@"; do
  case "$folder" in
    /*) folders+=("$folder") ;;
    *) folders+=("$PWD/$folder") ;;
  esac
done

cd "$ROOT"
# shellcheck source=tools/mac-lib.sh
. tools/mac-lib.sh
use_installed_xcode

mkdir -p build/logs
LOG="build/logs/session-check-$(date +%Y%m%d-%H%M%S).log"

exiftool="$(tools/get-exiftool.sh | tail -1)" || {
  echo "SESSION CHECK FAILED (ExifTool could not be fetched)"
  exit 1
}
if ! build_output="$(swift build --package-path Core --product scrivner-check 2>&1)"; then
  echo "$build_output" | scrub | tee -a "$LOG"
  echo "SESSION CHECK FAILED (the checker does not build, log: $LOG)"
  exit 1
fi
check="$(swift build --package-path Core --show-bin-path)/scrivner-check"

echo "The report is also being saved to $ROOT/$LOG" | scrub
"$check" --media --exiftool "$exiftool" "${folders[@]}" 2>&1 | scrub | tee -a "$LOG"
exit "${PIPESTATUS[0]}"
