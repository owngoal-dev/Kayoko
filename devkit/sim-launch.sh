#!/bin/sh
set -eu

if [ "${THEOS_DEVICE_SIMULATOR:-}" != 1 ]; then
  echo "Source devkit/simulator.sh first." >&2
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <device_id>" >&2
  exit 1
fi

xcrun simctl bootstatus "$1" -b
open "$(xcode-select -p)/Applications/Simulator.app"
