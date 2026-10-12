#!/usr/bin/env bash
# Generates the App Store screenshots from Demo Mode (UI test class ScreenshotTests, seeded by the Debug-only
# `-seed-demo-instance` launch argument) into Screenshots/<device>/<language>/NN-<scene>.png (git-ignored).
# Usage: Scripts/screenshots.sh [iphone|ipad|watch|all]   (default: all; ipad and watch are not implemented yet)
# Env:   IPHONE_TYPE (default iPhone-18-Pro-Max, the 6.9" class)
# The script creates and uses its own simulators ("EngelsystemClient Screenshots …"); yours stay untouched.
# Needs an unlocked screen (UI tests). A fresh simulator is slow for a while — a run takes several minutes.
# App Store sizes (App Store Connect › Screenshot specifications, checked 2026-10-12): iPhone 6.9" 1320 × 2868,
# iPad 13" 2752 × 2064 (landscape), Apple Watch Ultra 3/4 422 × 514.
set -euo pipefail
cd "$(dirname "$0")/.."

LANGUAGE="en"
BUNDLE_ID="net.cuccato.engelsystem.de.EngelsystemClient"
SCENES=(01-shifts 02-news 03-profile 04-locations 05-messages 06-settings)
IPHONE_NAME="EngelsystemClient Screenshots iPhone"
IPHONE_TYPE="com.apple.CoreSimulator.SimDeviceType.${IPHONE_TYPE:-iPhone-18-Pro-Max}"
IPHONE_SIZE="1320x2868"

# Creates the simulator if missing and returns its UDID on stdout.
ensure_simulator() { # name device-type
  local udid
  udid="$(xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "$1" "$2")"
  fi
  echo "$udid"
}

# Boots the simulator with English (US), light appearance and the status bar Apple uses in marketing images
# (9:41, full battery without the charging bolt, Wi-Fi and cellular), and removes a previous install of the app so every run starts with
# fresh state (including the notification permission prompt the test handles).
prepare_simulator() { # udid
  local udid="$1"
  xcrun simctl boot "$udid" 2> /dev/null || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
  if [[ "$(xcrun simctl spawn "$udid" defaults read -g AppleLocale 2> /dev/null)" != "en_US" ]]; then
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array en
    xcrun simctl spawn "$udid" defaults write -g AppleLocale en_US
    xcrun simctl shutdown "$udid"
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b > /dev/null
  fi
  xcrun simctl ui "$udid" appearance light
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2> /dev/null || true
}

# Removes the EXIF and XMP chunks (the simulator's orientation/size from before a rotation) from a PNG.
strip_metadata() { # file
  python3 - "$1" << 'PY'
import struct, sys
path = sys.argv[1]
data = open(path, "rb").read()
chunks, index = [data[:8]], 8
while index < len(data):
    length = struct.unpack(">I", data[index:index + 4])[0]
    kind = data[index + 4:index + 8]
    is_xmp = kind == b"iTXt" and data[index + 8:index + 25] == b"XML:com.adobe.xmp"
    if kind != b"eXIf" and not is_xmp:
        chunks.append(data[index:index + 12 + length])
    index += 12 + length
open(path, "wb").write(b"".join(chunks))
PY
}

# Runs ScreenshotTests on one simulator and copies the attachments to Screenshots/<device>/<language>/.
run_ui_device() { # device-label udid expected-size
  local device="$1" udid="$2" size="$3"
  local result="build/Screenshots-$device.xcresult" export="build/Screenshots-$device-attachments"
  local target="Screenshots/$device/$LANGUAGE"
  rm -rf "$result" "$export" "$target"
  mkdir -p "$target" build
  echo "==> $device ($udid)"
  prepare_simulator "$udid"
  local status=0
  # Normal simulator signing: CODE_SIGNING_ALLOWED=NO would strip the iCloud entitlement and the app would crash.
  xcodebuild test -scheme EngelsystemClient -destination "platform=iOS Simulator,id=$udid" \
    -only-testing:EngelsystemClientUITests/ScreenshotTests -parallel-testing-enabled NO \
    -derivedDataPath build/ScreenshotsDerivedData -resultBundlePath "$result" \
    > "build/Screenshots-$device.log" 2>&1 || status=$?
  if [[ -d "$result" ]]; then
    xcrun xcresulttool export attachments --path "$result" --output-path "$export" > /dev/null
    python3 - "$export" "$target" << 'PY'
import json, os, shutil, sys
export, target = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(export, "manifest.json"))):
    for attachment in test["attachments"]:
        name = attachment["suggestedHumanReadableName"].split("_0_")[0]
        if name[:2].isdigit():  # scene attachments are named NN-scene; ignore the system ones
            shutil.copy(os.path.join(export, attachment["exportedFileName"]), os.path.join(target, name + ".png"))
PY
  fi
  if [[ $status -ne 0 ]]; then
    echo "error: ScreenshotTests failed (exit $status) — see build/Screenshots-$device.log" >&2
    return 1
  fi
  verify_device "$device" "$target" "$size"
}

# Every scene must exist with the exact App Store pixel size; metadata is stripped; prints a summary.
verify_device() { # device dir expected-size
  local device="$1" dir="$2" size="$3" failed=0 scene file actual
  for scene in "${SCENES[@]}"; do
    file="$dir/$scene.png"
    if [[ ! -f "$file" ]]; then
      echo "error: missing scene $scene for $device" >&2
      failed=1
      continue
    fi
    actual="$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}')"
    if [[ "$actual" != "$size" ]]; then
      echo "error: $file is $actual, expected $size" >&2
      failed=1
      continue
    fi
    strip_metadata "$file"
    echo "  ok  $file  $actual"
  done
  return $failed
}

main() {
  local what="${1:-all}"
  case "$what" in
    iphone | all)
      run_ui_device "iphone" "$(ensure_simulator "$IPHONE_NAME" "$IPHONE_TYPE")" "$IPHONE_SIZE"
      ;;
  esac
  case "$what" in
    ipad | watch | all)
      [[ "$what" == "all" ]] || { echo "error: $what is not implemented yet" >&2; exit 2; }
      echo "note: ipad and watch are not implemented yet (backlog S-04, S-05)"
      ;;
    iphone) ;;
    *) echo "usage: $0 [iphone|ipad|watch|all]" >&2; exit 2 ;;
  esac
}
main "$@"
