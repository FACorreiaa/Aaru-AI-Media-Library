#!/usr/bin/env bash
# Takes the App Store's pictures from the simulator (REL-005).
#
#   scripts/store-screenshots.sh "iPhone 17 Pro" "Aaru iPad 13"
#
# Each simulator must be booted with Aaru Beta signed in: the walk-through never signs in.
# Raw PNGs land in aaru-ios/fastlane/screenshots/raw/<device>/ (ignored by git).
set -euo pipefail

cd "$(dirname "$0")/../aaru-ios"
out="$PWD/fastlane/screenshots/raw"
derived="${DERIVED_DATA:-$PWD/.build/screenshots}"

for device in "$@"; do
  folder="$out/${device// /-}"
  rm -rf "$folder"
  mkdir -p "$folder"
  # The store's clock: 9:41, full battery, full signal.
  xcrun simctl status_bar "$device" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 --dataNetwork wifi
  TEST_RUNNER_SCREENSHOT_DIR="$folder" xcodebuild test -only-testing:AaruScreenshots/StoreScreenshots \
    -project Aaru.xcodeproj -scheme "Aaru Screenshots" \
    -destination "platform=iOS Simulator,name=$device" \
    -derivedDataPath "$derived" | grep -E "error:|Test Case|TEST (SUCCEEDED|FAILED)" || true
  xcrun simctl status_bar "$device" clear
  echo "$device: $(find "$folder" -name '*.png' | wc -l | tr -d ' ') pictures in $folder"
done
