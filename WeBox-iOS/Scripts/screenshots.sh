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
CONTAINER_PATH=$(xcrun simctl get_app_container "$SIMULATOR_ID" com.xylyra.webox data)
mkdir -p "$CONTAINER_PATH/Documents/UIFixtures"
cp Tests/Fixtures/Screenshots/*.js "$CONTAINER_PATH/Documents/UIFixtures/"
for PAGE in empty discover detail sources library settings player; do
  xcrun simctl terminate "$SIMULATOR_ID" com.xylyra.webox || true
  rm -f "$CONTAINER_PATH/Documents/UIReady-$PAGE"
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
  test "$READY" = 1 || { echo "UI did not become ready: $PAGE"; exit 1; }
  sleep 2
  xcrun simctl io "$SIMULATOR_ID" screenshot "$OUTPUT_PATH/$PAGE.png"
done
xcrun simctl terminate "$SIMULATOR_ID" com.xylyra.webox || true
