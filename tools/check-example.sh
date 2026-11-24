#!/bin/bash
# Proves the session checker does its job, using the worked example in format/examples:
#   1. the example itself passes, media tags included;
#   2. a copy with one photo's time moved by a minute fails, and the report says why;
#   3. a copy with a place written into a clip made with location off fails, and says why;
#   4. the same when the place is tucked into a part of a file the recorder never uses.
#
# Last line: "EXAMPLE CHECK OK" or "EXAMPLE CHECK FAILED: <why>".
# Works on a Mac and on Linux. Set EXIFTOOL to use an ExifTool you already have.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "EXAMPLE CHECK FAILED: $1"
  exit 1
}

exiftool="${EXIFTOOL:-}"
if [ -z "$exiftool" ]; then
  exiftool="$(tools/get-exiftool.sh | tail -1)" || fail "ExifTool could not be fetched"
fi
[ -x "$exiftool" ] || fail "ExifTool was not found at $exiftool"

if ! build_output="$(swift build --package-path Core --product scrivner-check 2>&1)"; then
  echo "$build_output"
  fail "the checker does not build"
fi
check="$(swift build --package-path Core --show-bin-path)/scrivner-check"
[ -x "$check" ] || fail "the checker was built but not found at $check"

example="$(find format/examples -mindepth 1 -maxdepth 1 -type d | head -1)"
[ -n "$example" ] || fail "there is no example in format/examples"
name="$(basename "$example")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# run_check FOLDER: runs the checker; leaves its output in $output and its exit status in $status.
run_check() {
  output="$("$check" --media --exiftool "$exiftool" "$1" 2>&1)"
  status=$?
  echo "$output"
}

# expect_failure WHAT TEXT...: the last run must have failed and its report must contain each TEXT.
expect_failure() {
  local what="$1"
  shift
  [ "$status" -eq 1 ] || fail "$what: the checker should have failed"
  local text
  for text in "$@"; do
    echo "$output" | grep -qF -- "$text" || fail "$what: the report does not say \"$text\""
  done
}

echo "== 1. the worked example"
run_check format/examples
[ "$status" -eq 0 ] || fail "the worked example does not pass"
echo "$output" | grep -q "^SESSION CHECK OK (1 session, 0 problems, 0 warnings)$" \
  || fail "the worked example passes, but not cleanly"

echo "== 2. a photo whose time inside the file was moved by a minute"
mkdir "$work/time"
cp -R "$example" "$work/time/"
"$exiftool" -q -overwrite_original "-DateTimeOriginal+=0:0:0 0:1:0" "$work/time/$name/photos/photo-0001.heic" \
  || fail "could not change the copy's photo"
run_check "$work/time/$name"
expect_failure "moved time" "photos/photo-0001.heic: says it was taken at" "photos/photo-0001.heic: does not match its checksum"

echo "== 3. a place written into a clip made with location off"
mkdir "$work/place"
cp -R "$example" "$work/place/"
"$exiftool" -q -overwrite_original "-Keys:GPSCoordinates=27.7046, 85.3076, 1300" "$work/place/$name/video/clip-0002.mov" \
  || fail "could not change the copy's clip"
run_check "$work/place/$name"
expect_failure "unexpected place" "video/clip-0002.mov: carries a location although session.json has none for it"

echo "== 4. a place hidden in an unusual part of an audio file"
mkdir "$work/hidden"
cp -R "$example" "$work/hidden/"
"$exiftool" -q -overwrite_original "-UserData:GPSCoordinates=27.7046, 85.3076" "$work/hidden/$name/audio/audio-002.m4a" \
  || fail "could not change the copy's audio"
run_check "$work/hidden/$name"
expect_failure "hidden place" "audio/audio-002.m4a: carries a location; audio is never located (found in UserData:GPSCoordinates)"

echo "EXAMPLE CHECK OK"
