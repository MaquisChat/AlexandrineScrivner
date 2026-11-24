#!/bin/bash
# Shared helpers for the tools/mac-*.sh scripts. Sourced, not run.

# If the Command Line Tools were installed before Xcode, xcodebuild fails although Xcode is
# there. Point the tools at Xcode for this run when that is the case.
use_installed_xcode() {
  if ! xcodebuild -version >/dev/null 2>&1; then
    if [ -d /Applications/Xcode.app/Contents/Developer ]; then
      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
  fi
}

# find_device KIND: KIND is "iphone" or "ipad". On success sets
#   DEVICE_MODEL  the hardware model, e.g. "iPhone18,1" (safe to print)
# and, for use but never for printing,
#   DEVICE_UDID   the identifier Xcode's tools need
#   DEVICE_ID     the second identifier devicectl uses for the same device
#   DEVICE_NAME   the name its owner gave it
# and returns 0. Returns 1 with a plain message on standard error otherwise.
find_device() {
  local kind="$1" want json out
  case "$kind" in
    iphone) want="iPhone" ;;
    ipad) want="iPad" ;;
    *) echo "Say which device: iphone or ipad." >&2; return 1 ;;
  esac
  json="$(mktemp -t devices.XXXXXX)"
  if ! xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1; then
    rm -f "$json"
    echo "Could not list connected devices. Is Xcode installed and has it been opened once?" >&2
    return 1
  fi
  out="$(/usr/bin/python3 - "$json" "$want" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2]
with open(path, "rb") as f:
    data = json.load(f)
for device in data.get("result", {}).get("devices", []):
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    properties = device.get("deviceProperties", {})
    if device.get("visibilityClass") == "Simulator":
        continue
    if hardware.get("deviceType") != want:
        continue
    if connection.get("pairingState") != "paired":
        continue
    # A device that was paired once is still listed when it is not plugged in.
    if connection.get("transportType") != "wired" and connection.get("tunnelState") != "connected":
        continue
    udid = hardware.get("udid") or device.get("identifier")
    if not udid:
        continue
    print(udid)
    print(hardware.get("productType", want))
    print(device.get("identifier", ""))
    print(properties.get("name", ""))
    break
PY
)"
  rm -f "$json"
  if [ -z "$out" ]; then
    echo "No connected $want found. Connect it by cable, unlock it, and tap Trust if it asks." >&2
    return 1
  fi
  DEVICE_UDID="$(printf '%s\n' "$out" | sed -n 1p)"
  DEVICE_MODEL="$(printf '%s\n' "$out" | sed -n 2p)"
  DEVICE_ID="$(printf '%s\n' "$out" | sed -n 3p)"
  DEVICE_NAME="$(printf '%s\n' "$out" | sed -n 4p)"
  return 0
}

# scrub: a filter for everything the scripts print or log. Replaces the things that identify a
# person or a device (identifiers, the device's name, the signing team and identity, the home
# folder) with placeholders, so a log can be shown to someone else.
scrub() {
  local team=""
  if [ -f spike/Local.xcconfig ]; then
    team="$(awk -F'= *' '/^DEVELOPMENT_TEAM/ { print $2; exit }' spike/Local.xcconfig)"
  fi
  SCRUB_UDID="${DEVICE_UDID:-}" SCRUB_ID="${DEVICE_ID:-}" SCRUB_NAME="${DEVICE_NAME:-}" \
  SCRUB_TEAM="$team" SCRUB_HOME="$HOME" SCRUB_USER="${USER:-}" \
  /usr/bin/python3 -u -c '
import os, re, sys
pairs = [
    (os.environ.get("SCRUB_UDID", ""), "<device>"),
    (os.environ.get("SCRUB_ID", ""), "<device>"),
    (os.environ.get("SCRUB_NAME", ""), "<device name>"),
    (os.environ.get("SCRUB_TEAM", ""), "<team>"),
    (os.environ.get("SCRUB_HOME", ""), "~"),
]
pairs = [(old, new) for old, new in pairs if len(old) >= 4]
user = os.environ.get("SCRUB_USER", "")
identity = re.compile(r"(Apple (?:Development|Distribution)|iPhone Developer): [^\"\n]*")
for raw in sys.stdin.buffer:
    line = raw.decode("utf-8", "replace")
    for old, new in pairs:
        line = line.replace(old, new)
    line = identity.sub(r"\1: <identity>", line)
    if len(user) >= 3:
        line = line.replace(user + ".xcuserdatad", "<user>.xcuserdatad")
    sys.stdout.write(line)
    sys.stdout.flush()
'
}
