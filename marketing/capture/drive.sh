#!/usr/bin/env bash
# Drives the signed-in Aaru Beta app on the booted Simulator with a Driver script
# (aaru-ios/AaruScreenshots/Driver.swift) and, with --record, films it.
#
#   capture/drive.sh scripts/a3-search.txt [--record out.mov]
#
# Needs: `xcodebuild build-for-testing -scheme "Aaru Screenshots" -derivedDataPath
# aaru-ios/.build/marketing` once. Beta config = production API: film only the demo account.
set -euo pipefail
sim="${SIM:-105FD44C-3BDD-4005-A966-6EC7E91D327A}"   # "Aaru Film" (iPhone 17), filming only; other sims may be booted
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out_dir="$repo/marketing/assets/raw/capture"
mkdir -p "$out_dir"
xcrun simctl status_bar "$sim" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi
rec_pid=""
if [[ "${2:-}" == "--record" ]]; then
  xcrun simctl io "$sim" recordVideo --codec=h264 --force "$out_dir/$3" &
  rec_pid=$!
  sleep 2
fi
derived="${IOS_DERIVED:-$repo/aaru-ios/.build/marketing}"
xctestrun="$(ls "$derived"/Build/Products/*.xctestrun | head -1)"
TEST_RUNNER_DRIVER_SCRIPT="$script" TEST_RUNNER_SCREENSHOT_DIR="$out_dir" \
  xcodebuild test-without-building -xctestrun "$xctestrun" \
  -destination "id=$sim" \
  -only-testing:AaruScreenshots/Driver/testRunScript 2>&1 | grep -E "error|Test Case .* (passed|failed)" || true
if [[ -n "$rec_pid" ]]; then
  sleep 1
  kill -INT "$rec_pid"; wait "$rec_pid" 2>/dev/null || true
fi
cat "$out_dir/log.txt" 2>/dev/null
