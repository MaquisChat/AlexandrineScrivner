#!/bin/bash
# Fetches ExifTool, the program the session checker uses to read the times and places written
# inside audio, photo and video files. It is the same build the research workbench uses.
#
#   tools/get-exiftool.sh      the last line printed is the path of the exiftool program
#
# It is kept in .tools/exiftool and fetched only once. The download is checked against the
# checksum recorded below before anything in it is used. Works on a Mac and on Linux; needs Perl,
# which both have.
set -euo pipefail

EXIFTOOL_PACKAGE_VERSION="13.59.3"
EXIFTOOL_SHA256="dea9f92a8748a75a43ff42aae017644a48982aead848f985c6a443ec11e0b8f5"
URL="https://registry.npmjs.org/exiftool-vendored.pl/-/exiftool-vendored.pl-$EXIFTOOL_PACKAGE_VERSION.tgz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.tools/exiftool"
PROGRAM="$DIR/package/bin/exiftool"

fail() {
  echo "GET EXIFTOOL FAILED: $1" >&2
  exit 1
}

command -v perl >/dev/null 2>&1 || fail "Perl was not found, and ExifTool needs it."

if [ ! -f "$PROGRAM" ] || [ "$(cat "$DIR/version" 2>/dev/null || true)" != "$EXIFTOOL_PACKAGE_VERSION" ]; then
  mkdir -p "$ROOT/.tools"
  archive="$ROOT/.tools/exiftool.tgz"
  curl -fL --retry 3 -sS -o "$archive" "$URL" \
    || fail "Could not download ExifTool. Check the internet connection and try again."
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$archive" | awk '{ print $1 }')"
  else
    sum="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
  fi
  if [ "$sum" != "$EXIFTOOL_SHA256" ]; then
    rm -f "$archive"
    fail "The ExifTool download does not match its recorded checksum, so it was thrown away. Try again; if it keeps happening, stop and ask."
  fi
  rm -rf "$DIR"
  mkdir -p "$DIR"
  tar -xzf "$archive" -C "$DIR" || fail "The ExifTool download could not be unpacked."
  rm -f "$archive"
  chmod +x "$PROGRAM"
  echo "$EXIFTOOL_PACKAGE_VERSION" > "$DIR/version"
fi

"$PROGRAM" -ver >/dev/null 2>&1 || fail "ExifTool was fetched but does not run."
echo "ExifTool $("$PROGRAM" -ver)"
echo "$PROGRAM"
