#!/bin/bash
# Shared helpers for the tools/mac-*.sh scripts. Sourced, not run.

# find_device KIND: KIND is "iphone" or "ipad". On success sets
#   DEVICE_UDID   the identifier Xcode's tools need (never print it)
#   DEVICE_MODEL  the hardware model, e.g. "iPhone18,1" (safe to print)
# and returns 0. Returns 1 with a plain message on standard error otherwise.
find_device() {
  local kind="$1" want json line
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
  line="$(/usr/bin/python3 - "$json" "$want" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
for device in data.get("result", {}).get("devices", []):
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    if hardware.get("deviceType") != want:
        continue
    if connection.get("pairingState") != "paired":
        continue
    udid = hardware.get("udid") or device.get("identifier")
    model = hardware.get("productType", want)
    if udid:
        print(udid + " " + model)
        break
PY
)"
  rm -f "$json"
  if [ -z "$line" ]; then
    echo "No $want found. Connect it by cable, unlock it, and tap Trust if it asks." >&2
    return 1
  fi
  DEVICE_UDID="${line%% *}"
  DEVICE_MODEL="${line#* }"
  return 0
}
