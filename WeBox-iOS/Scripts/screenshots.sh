#!/bin/bash
set -euo pipefail
SIMULATOR_ID="$1"
APP_PATH="$2"
OUTPUT_PATH="$3"
mkdir -p "$OUTPUT_PATH"
xcrun simctl boot "$SIMULATOR_ID" || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl status_bar "$SIMULATOR_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$SIMULATOR_ID" appearance light
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
for PAGE in discover detail sources library; do
  xcrun simctl terminate "$SIMULATOR_ID" com.xylyra.webox || true
  xcrun simctl launch "$SIMULATOR_ID" com.xylyra.webox --screenshots "--screen-$PAGE"
  sleep 6
  xcrun simctl io "$SIMULATOR_ID" screenshot "$OUTPUT_PATH/$PAGE.png"
done
