#!/bin/zsh
set -uo pipefail

echo "--- Resolve ---"
set -e
(cd BuildTools && swift package resolve)

echo "--- Xcbeautify ---"
set -e
(cd BuildTools && swift build -c release --product xcbeautify)

set +e
XCBEAUTIFY=$(find BuildTools/.build -type f -name xcbeautify | grep -v dSYM)
if [ -z "$XCBEAUTIFY" ]; then
  echo "xcbeautify not found"
  exit 1
fi

echo "--- SwiftFormat ---"
set -e
(cd BuildTools && swift package resolve && swift build -c release --product swiftformat)

set +e
SWIFTFORMAT=$(find BuildTools/.build -type f -name swiftformat | grep apple-macosx | grep -v dSYM)
if [ -z "$SWIFTFORMAT" ]; then
  echo "swiftformat not found"
  exit 1
fi

set -e
NUM_CORES=$(sysctl -n hw.ncpu)

echo "--- Clean ---"
set +e
NSUnbufferedIO=YES xcodebuild clean -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Debug -destination 'generic/platform=iOS Simulator' 2>&1  | $XCBEAUTIFY --disable-logging
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild clean failed with exit code $EXIT_CODE"
  exit 1
fi

NSUnbufferedIO=YES xcodebuild clean -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles-macOS -configuration Debug -destination 'platform=macOS,arch=arm64' 2>&1  | $XCBEAUTIFY --disable-logging
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild clean failed with exit code $EXIT_CODE"
  exit 1
fi

set -e
(cd VideoSubtitlesLib && rm -rf .build)

echo "--- Format ---"
set -e
$SWIFTFORMAT .

echo "--- Debug (iOS Simulator) ---"
set +e
NSUnbufferedIO=YES xcodebuild -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Debug -destination 'generic/platform=iOS Simulator' -jobs $NUM_CORES 2>&1 | $XCBEAUTIFY --disable-logging
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild failed with exit code $EXIT_CODE"
  exit 1
fi

echo "--- Debug (macOS) ---"
set +e
NSUnbufferedIO=YES xcodebuild -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles-macOS -configuration Debug -destination 'platform=macOS,arch=arm64' -jobs $NUM_CORES 2>&1 | $XCBEAUTIFY --disable-logging
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "xcodebuild failed with exit code $EXIT_CODE"
  exit 1
fi

echo "--- Test ---"
set +e
(cd VideoSubtitlesLib && NSUnbufferedIO=YES swift test 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "swift test failed with exit code $EXIT_CODE"
  exit 1
fi

echo "===SUCCESS==="
