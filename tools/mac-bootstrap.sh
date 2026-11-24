#!/bin/bash
# Checks that this Mac can build the app, fetches XcodeGen, and prepares spike/Local.xcconfig.
#
#   tools/mac-bootstrap.sh                  check everything; last line is "BOOTSTRAP OK"
#   tools/mac-bootstrap.sh --capture-team   also save the signing team chosen in Xcode
#
# Runs on the Mac. Works with the bash that ships with macOS.
set -euo pipefail

XCODEGEN_VERSION="2.46.0"
# SHA-256 of xcodegen.zip for the version above. Every download is verified against it.
# When changing the version, empty this; the next download prints the value to record here.
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"

# What the owner's Mac needs, to build for devices on version 27. The automatic checks build on
# whatever Mac they are given, so they may lower these two through the environment.
MIN_MACOS="${SCRIVNER_MIN_MACOS:-26.6}"
MIN_XCODE="${SCRIVNER_MIN_XCODE:-27}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "BOOTSTRAP FAILED: $1" >&2
  exit 1
}

# version_at_least HAVE NEED: true when dotted version HAVE is the same as or newer than NEED.
version_at_least() {
  local have="$1" need="$2" i h n
  local IFS=.
  # shellcheck disable=SC2206
  local have_parts=($have) need_parts=($need)
  for i in 0 1 2; do
    h="${have_parts[$i]:-0}"
    n="${need_parts[$i]:-0}"
    case "$h" in ''|*[!0-9]*) h=0 ;; esac
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$h" -gt "$n" ]; then return 0; fi
    if [ "$h" -lt "$n" ]; then return 1; fi
  done
  return 0
}

capture_team=no
for arg in "$@"; do
  case "$arg" in
    --capture-team) capture_team=yes ;;
    *) fail "Unknown option \"$arg\". Use no option, or --capture-team." ;;
  esac
done

# 1. macOS
command -v sw_vers >/dev/null 2>&1 || fail "This script has to run on a Mac."
# shellcheck source=tools/mac-lib.sh
. tools/mac-lib.sh
use_installed_xcode
macos_version="$(sw_vers -productVersion)"
version_at_least "$macos_version" "$MIN_MACOS" \
  || fail "macOS $macos_version is too old. Update to macOS Tahoe $MIN_MACOS or later in System Settings, General, Software Update."

# 2. Xcode
xcode_version="$(xcodebuild -version 2>/dev/null | awk '/^Xcode / { print $2; exit }')" || true
[ -n "${xcode_version:-}" ] \
  || fail "Xcode is not installed, or has not been opened yet. Install Xcode $MIN_XCODE from the App Store and open it once."
version_at_least "$xcode_version" "$MIN_XCODE" \
  || fail "Xcode $xcode_version is too old. Install Xcode $MIN_XCODE or later from the App Store."

# 3. XcodeGen
xcodegen=".tools/xcodegen/bin/xcodegen"
if [ ! -x "$xcodegen" ]; then
  mkdir -p .tools
  zip=".tools/xcodegen.zip"
  url="https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
  curl -fL --retry 3 -o "$zip" "$url" \
    || fail "Could not download XcodeGen $XCODEGEN_VERSION. Check the internet connection and try again."
  sum="$(shasum -a 256 "$zip" | awk '{ print $1 }')"
  if [ -n "$XCODEGEN_SHA256" ]; then
    if [ "$sum" != "$XCODEGEN_SHA256" ]; then
      rm -f "$zip"
      fail "The XcodeGen download does not match its recorded checksum, so it was thrown away. Try again; if it keeps happening, stop and ask."
    fi
  else
    echo "NOTE: XcodeGen $XCODEGEN_VERSION downloaded. Record this in XCODEGEN_SHA256 at the top of tools/mac-bootstrap.sh:"
    echo "NOTE:   $sum"
  fi
  unzip -q -o "$zip" -d .tools || fail "The XcodeGen download could not be unpacked. Delete the .tools folder and try again."
  [ -x "$xcodegen" ] || fail "XcodeGen was downloaded but its program was not found at $xcodegen."
fi

# 4. Local settings for this Mac (never committed)
local_config="spike/Local.xcconfig"
if [ ! -f "$local_config" ]; then
  mkdir -p spike
  suffix="$(od -An -N4 -tx1 /dev/urandom | tr -dc '0-9a-f')"
  {
    echo "// Local settings for this Mac. Not committed."
    echo "DEVELOPMENT_TEAM ="
    echo "BUNDLE_ID_PREFIX = local.scrivner.$suffix"
  } > "$local_config"
fi

# 5. Save the signing team chosen in Xcode
if [ "$capture_team" = yes ]; then
  project="spike/Spike.xcodeproj/project.pbxproj"
  [ -f "$project" ] || fail "The Xcode project has not been generated yet. Run tools/mac-build.sh first."
  team="$(awk '/DEVELOPMENT_TEAM = [A-Z0-9]+;/ { sub(/.*DEVELOPMENT_TEAM = /, ""); sub(/;.*/, ""); print; exit }' "$project")"
  [[ "$team" =~ ^[A-Z0-9]{10}$ ]] \
    || fail "No signing team is chosen in the Xcode project yet. Open spike/Spike.xcodeproj, choose your Personal Team under Signing & Capabilities, close Xcode, and run this again."
  tmp="$local_config.tmp"
  awk -v team="$team" '
    /^DEVELOPMENT_TEAM[ =]/ { print "DEVELOPMENT_TEAM = " team; done = 1; next }
    { print }
    END { if (!done) print "DEVELOPMENT_TEAM = " team }
  ' "$local_config" > "$tmp"
  mv "$tmp" "$local_config"
  echo "Signing team saved to $local_config."
fi

# 6. Report
echo "macOS $macos_version"
echo "Xcode $xcode_version"
echo "XcodeGen $("$xcodegen" --version 2>/dev/null | awk '{ print $NF; exit }')"
echo "BOOTSTRAP OK"
