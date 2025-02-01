#!/bin/zsh
set -uo pipefail
set +e

echo "--- BuildTools Resolve ---"
(cd BuildTools && NSUnbufferedIO=YES swift package resolve >/dev/null 2>/dev/null)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "swift package resolve failed with exit code $EXIT_CODE"
  exit 1
fi

echo "--- Build xcbeautify ---"
(cd BuildTools && NSUnbufferedIO=YES swift build -q -c release --product xcbeautify >/dev/null 2>/dev/null)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "swift build failed with exit code $EXIT_CODE"
  exit 1
fi

XCBEAUTIFY=$(find BuildTools/.build -type f -name xcbeautify | grep -v dSYM)
if [ -z "$XCBEAUTIFY" ]; then
  echo "xcbeautify not found"
  exit 1
fi

echo "--- Build SwiftFormat ---"
(cd BuildTools && NSUnbufferedIO=YES swift build -q -c release --product swiftformat >/dev/null 2>/dev/null)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "swift build failed with exit code $EXIT_CODE"
  exit 1
fi

SWIFTFORMAT=$(find BuildTools/.build -type f -name swiftformat | grep apple-macosx | grep -v dSYM)
if [ -z "$SWIFTFORMAT" ]; then
  echo "swiftformat not found"
  exit 1
fi

NUM_CORES=$(sysctl -n hw.ncpu)
if [ -z "$NUM_CORES" ]; then
  echo "sysctl failed to get number of cores"
  exit 1
fi

echo "--- Clean ---"
NSUnbufferedIO=YES xcodebuild clean -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Debug -destination 'generic/platform=iOS Simulator' 2>&1  | $XCBEAUTIFY --disable-logging
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild clean failed with exit code $EXIT_CODE"
  exit 1
fi

NSUnbufferedIO=YES xcodebuild clean -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles-macOS -configuration Debug -destination 'platform=macOS,arch=arm64' 2>&1  | $XCBEAUTIFY --disable-logging
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild clean failed with exit code $EXIT_CODE"
  exit 1
fi

(cd VideoSubtitlesLib && rm -rf .build)

echo "--- Format ---"
$SWIFTFORMAT . >/dev/null 2>/dev/null
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "swiftformat failed with exit code $EXIT_CODE"
  exit 1
fi

echo "--- Build (iOS Debug) ---"
NSUnbufferedIO=YES xcodebuild -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Debug -destination 'generic/platform=iOS Simulator' -jobs $NUM_CORES 2>&1 | $XCBEAUTIFY --disable-logging
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild failed with exit code $EXIT_CODE"
  exit 1
fi

echo "--- Build (macOS Debug) ---"
NSUnbufferedIO=YES xcodebuild -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles-macOS -configuration Debug -destination 'platform=macOS,arch=arm64' -jobs $NUM_CORES 2>&1 | $XCBEAUTIFY --disable-logging
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild failed with exit code $EXIT_CODE"
  exit 1
fi

echo "--- Test ---"
(cd VideoSubtitlesLib && NSUnbufferedIO=YES swift test -q -j $NUM_CORES 2>&1) | grep -v '^\[' | grep -v "^Test Case.*started" | grep -v '^Test.*passed'
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "swift test failed with exit code $EXIT_CODE"
  exit 1
fi

echo "===SUCCESS==="
