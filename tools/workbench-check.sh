#!/bin/bash
# Runs the research workbench's own import code over a session folder, to see what the workbench
# would take from it, and compares that with the session's own record.
#
#   tools/workbench-check.sh WORKBENCH_CHECKOUT [SESSION_FOLDER]
#
# WORKBENCH_CHECKOUT is a local copy of the workbench (MaquisChat/AlexandrineOxiana) with its
# dependencies installed (pnpm install). SESSION_FOLDER defaults to the worked example.
# Nothing is imported anywhere and nothing in the workbench is changed: its code is only run.
#
# This is not one of the automatic checks, because it needs the workbench's code. Run it when
# either side changes, and record the result in docs/compatibility/workbench-check.md.
# Last line: "WORKBENCH CHECK OK (...)" or "WORKBENCH CHECK FAILED (...)".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -lt 1 ]; then
  echo "Say where the workbench is: tools/workbench-check.sh WORKBENCH_CHECKOUT [SESSION_FOLDER]"
  echo "WORKBENCH CHECK FAILED (no workbench given)"
  exit 2
fi

absolute() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$PWD/$1" ;;
  esac
}

workbench="$(absolute "$1")"
if [ "$#" -ge 2 ]; then
  session="$(absolute "$2")"
else
  session="$(find "$ROOT/format/examples" -mindepth 1 -maxdepth 1 -type d | head -1)"
fi

[ -f "$workbench/packages/library/src/import/device.ts" ] || {
  echo "WORKBENCH CHECK FAILED ($workbench is not a workbench checkout)"
  exit 2
}
[ -d "$workbench/node_modules" ] || {
  echo "WORKBENCH CHECK FAILED (the workbench's dependencies are not installed: run pnpm install in it)"
  exit 2
}
[ -f "$session/session.json" ] || {
  echo "WORKBENCH CHECK FAILED ($session is not a session folder)"
  exit 2
}

commit="$(git -C "$workbench" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "Workbench at commit $commit"
echo "Session folder: $(basename "$session")"

output="$(cd "$workbench" && npx --no-install tsx "$ROOT/tools/workbench-check/scan.mts" "$workbench" "$session" "$ROOT/format/naming-cases.json" 2>&1)"
status=$?
echo "$output" | grep -v '^RESULT '

result="$(echo "$output" | grep '^RESULT ' | tail -1)"
files="$(echo "$result" | sed -n 's/.*files=\([0-9]*\).*/\1/p')"
names="$(echo "$result" | sed -n 's/.*names=\([0-9]*\).*/\1/p')"
failures="$(echo "$result" | sed -n 's/.*failures=\([0-9]*\).*/\1/p')"

if [ "$status" -eq 0 ] && [ -n "$files" ]; then
  echo "WORKBENCH CHECK OK ($files files, $names folder names, workbench $commit)"
  exit 0
fi
echo "WORKBENCH CHECK FAILED (${failures:-the check did not finish;} ${failures:+failures, }workbench $commit)"
exit 1
