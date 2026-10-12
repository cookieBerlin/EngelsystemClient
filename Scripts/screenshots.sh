#!/usr/bin/env bash
# Generates the App Store screenshots from Demo Mode (UI test class ScreenshotTests, seeded by the Debug-only
# `-seed-demo-instance` launch argument) into Screenshots/<device>/<language>/NN-<scene>.png (git-ignored).
# Usage: Scripts/screenshots.sh [iphone|ipad|watch|all]   (default: all)
# Env:   IPHONE_TYPE (default iPhone-18-Pro-Max, the 6.9" class), IPAD_TYPE (default iPad-Pro-13-inch-M5-12GB),
#        WATCH_TYPE (default Apple-Watch-Ultra-4-49mm)
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
IPAD_NAME="EngelsystemClient Screenshots iPad"
IPAD_TYPE="com.apple.CoreSimulator.SimDeviceType.${IPAD_TYPE:-iPad-Pro-13-inch-M5-12GB}"
IPAD_SIZE="2752x2064" # landscape; the test rotates the iPad
WATCH_NAME="EngelsystemClient Screenshots Watch"
WATCH_TYPE="com.apple.CoreSimulator.SimDeviceType.${WATCH_TYPE:-Apple-Watch-Ultra-4-49mm}"
WATCH_SIZE="422x514"
WATCH_BUNDLE_ID="net.cuccato.engelsystem.de.EngelsystemClient.watchkitapp"
WATCH_SCENES=(01-next-shift 02-settings)

# Creates the simulator if missing and returns its UDID on stdout.
ensure_simulator() { # name device-type
  local udid
  udid="$(xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "$1" "$2")"
  fi
  echo "$udid"
}

# Switches a booted simulator to English (US) (a reboot is needed once) so system text and time formats are English.
ensure_english() { # udid
  local udid="$1"
  if [[ "$(xcrun simctl spawn "$udid" defaults read -g AppleLocale 2> /dev/null)" != "en_US" ]]; then
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array en
    xcrun simctl spawn "$udid" defaults write -g AppleLocale en_US
    xcrun simctl shutdown "$udid"
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b > /dev/null
  fi
}

# Boots the simulator with English (US), light appearance and the status bar Apple uses in marketing images
# (9:41, full battery without the charging bolt, Wi-Fi and cellular), and removes a previous install of the app so every run starts with
# fresh state (including the notification permission prompt the test handles).
prepare_simulator() { # udid
  local udid="$1"
  xcrun simctl boot "$udid" 2> /dev/null || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
  ensure_english "$udid"
  xcrun simctl ui "$udid" appearance light
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2> /dev/null || true
}

# Bakes the EXIF orientation of a PNG into its pixels (the simulator stores iPad landscape screenshots rotated
# and only marks the rotation in EXIF), then removes the EXIF and XMP chunks so the file is plain pixels.
normalize_png() { # file
  local degrees
  degrees="$(python3 - "$1" << 'PY'
import struct, sys
data = open(sys.argv[1], "rb").read()
index, orientation = 8, 1
while index < len(data):
    length = struct.unpack(">I", data[index:index + 4])[0]
    kind = data[index + 4:index + 8]
    if kind == b"eXIf":
        tiff = data[index + 8:index + 8 + length]
        endian = "<" if tiff[:2] == b"II" else ">"
        ifd = struct.unpack(endian + "I", tiff[4:8])[0]
        for entry in range(struct.unpack(endian + "H", tiff[ifd:ifd + 2])[0]):
            offset = ifd + 2 + entry * 12
            if struct.unpack(endian + "H", tiff[offset:offset + 2])[0] == 0x0112:
                orientation = struct.unpack(endian + "H", tiff[offset + 8:offset + 10])[0]
    index += 12 + length
print({3: 180, 6: 90, 8: 270}.get(orientation, 0))
PY
)"
  if [[ "$degrees" != "0" ]]; then
    sips -r "$degrees" "$1" > /dev/null
  fi
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
  verify_device "$device" "$target" "$size" "${SCENES[@]}"
}

# Every scene must exist with the exact App Store pixel size (after baking in the EXIF orientation); prints a summary.
verify_device() { # device dir expected-size scene...
  local device="$1" dir="$2" size="$3" failed=0 scene file actual
  shift 3
  for scene in "$@"; do
    file="$dir/$scene.png"
    if [[ ! -f "$file" ]]; then
      echo "error: missing scene $scene for $device" >&2
      failed=1
      continue
    fi
    normalize_png "$file"
    actual="$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}')"
    if [[ "$actual" != "$size" ]]; then
      echo "error: $file is $actual, expected $size" >&2
      failed=1
      continue
    fi
    echo "  ok  $file  $actual"
  done
  return $failed
}

# Apple Watch: no UI test (watchOS UI tests are slow and flaky); the Debug-only launch arguments seed a demo instance and
# skip the notification prompt, then the simulator screen is captured after the first sync.
run_watch() {
  local udid target="Screenshots/watch/$LANGUAGE"
  udid="$(ensure_simulator "$WATCH_NAME" "$WATCH_TYPE")"
  rm -rf "$target"
  mkdir -p "$target" build
  echo "==> watch ($udid)"
  xcrun simctl boot "$udid" 2> /dev/null || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
  ensure_english "$udid"
  xcrun simctl uninstall "$udid" "$WATCH_BUNDLE_ID" 2> /dev/null || true
  xcodebuild build -scheme "EngelsystemClient Watch App" -destination "platform=watchOS Simulator,id=$udid" \
    -derivedDataPath build/ScreenshotsDerivedData > build/Screenshots-watch.log 2>&1 \
    || { echo "error: the Watch app build failed — see build/Screenshots-watch.log" >&2; return 1; }
  local app
  app="$(find build/ScreenshotsDerivedData/Build/Products -name 'EngelsystemClient Watch App.app' -path '*watchsimulator*' | head -1)"
  xcrun simctl install "$udid" "$app"
  xcrun simctl launch "$udid" "$WATCH_BUNDLE_ID" -seed-demo-instance -skipNotificationPrompt YES > /dev/null
  sleep 45 # first sync of the seeded demo instance on a (possibly fresh, slow) simulator
  xcrun simctl io "$udid" screenshot "$target/01-next-shift.png" > /dev/null 2>&1
  # Second scene: relaunch straight into Settings (the instance is already seeded).
  xcrun simctl terminate "$udid" "$WATCH_BUNDLE_ID" > /dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$WATCH_BUNDLE_ID" -open-settings -skipNotificationPrompt YES > /dev/null
  sleep 20
  xcrun simctl io "$udid" screenshot "$target/02-settings.png" > /dev/null 2>&1
  verify_device "watch" "$target" "$WATCH_SIZE" "${WATCH_SCENES[@]}"
}

main() {
  local what="${1:-all}"
  case "$what" in
    iphone | ipad | watch | all) ;;
    *) echo "usage: $0 [iphone|ipad|watch|all]" >&2; exit 2 ;;
  esac
  if [[ "$what" == "iphone" || "$what" == "all" ]]; then
    run_ui_device "iphone" "$(ensure_simulator "$IPHONE_NAME" "$IPHONE_TYPE")" "$IPHONE_SIZE"
  fi
  if [[ "$what" == "ipad" || "$what" == "all" ]]; then
    run_ui_device "ipad" "$(ensure_simulator "$IPAD_NAME" "$IPAD_TYPE")" "$IPAD_SIZE"
  fi
  if [[ "$what" == "watch" || "$what" == "all" ]]; then
    run_watch
  fi
}
main "$@"
