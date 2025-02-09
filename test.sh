#!/bin/zsh
set -uo pipefail
set +e

NUM_CORES=$(sysctl -n hw.ncpu)
if [ -z "$NUM_CORES" ]; then
  echo "sysctl failed to get number of cores"
  exit 1
fi

echo "--- Test ---"
NSUnbufferedIO=YES xcodebuild test -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -jobs $NUM_CORES 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild test failed with exit code $EXIT_CODE"
  exit 1
fi

echo "===SUCCESS==="
