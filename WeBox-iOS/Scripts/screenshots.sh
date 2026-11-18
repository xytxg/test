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
# UI tests use this same simulator and import a source. Start the capture
# with a fresh app container so the empty-state screenshot has no sources.
if xcrun simctl get_app_container "$SIMULATOR_ID" com.xylyra.webox data >/dev/null 2>&1; then
  xcrun simctl uninstall "$SIMULATOR_ID" com.xylyra.webox
fi
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
CONTAINER_PATH=$(xcrun simctl get_app_container "$SIMULATOR_ID" com.xylyra.webox data)
mkdir -p "$CONTAINER_PATH/Documents/UIFixtures"
cp Tests/Fixtures/Screenshots/*.js "$CONTAINER_PATH/Documents/UIFixtures/"
for PAGE in empty discover detail sources library settings player; do
  xcrun simctl terminate "$SIMULATOR_ID" com.xylyra.webox || true
  rm -f "$CONTAINER_PATH/Documents/UIReady-$PAGE"
  if [ "$PAGE" = player ]; then
    sed 's@/sample.mp4@/portrait.mp4@g' Tests/Fixtures/Screenshots/01-cinema.webox.js > "$CONTAINER_PATH/Documents/UIFixtures/01-cinema.webox.js"
  fi
  if [ "$PAGE" = empty ]; then
    xcrun simctl launch "$SIMULATOR_ID" com.xylyra.webox --screenshots --screen-empty
  else
    xcrun simctl launch "$SIMULATOR_ID" com.xylyra.webox --screenshots "--screen-$PAGE" "--fixtures=$CONTAINER_PATH/Documents/UIFixtures"
  fi
  READY=0
  for ATTEMPT in $(seq 1 90); do
    if [ -f "$CONTAINER_PATH/Documents/UIReady-$PAGE" ]; then READY=1; break; fi
    sleep 1
  done
  if [ "$READY" != 1 ]; then
    xcrun simctl io "$SIMULATOR_ID" screenshot "$OUTPUT_PATH/failed-$PAGE.png" || true
    xcrun simctl spawn "$SIMULATOR_ID" log show --last 3m --style compact --predicate 'process == "WeBox"' > "ui-$PAGE.log" || true
    echo "UI did not become ready: $PAGE"
    exit 1
  fi
  sleep 2
  xcrun simctl io "$SIMULATOR_ID" screenshot "$OUTPUT_PATH/$PAGE.png"
done
xcrun simctl terminate "$SIMULATOR_ID" com.xylyra.webox || true
