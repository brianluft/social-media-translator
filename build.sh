#!/bin/zsh
set -uo pipefail

echo "--- Tools ---"
set -e
(cd BuildTools && swift package resolve && swift build -c release --product xcbeautify && swift build -c release --product swiftformat)

set +e
XCBEAUTIFY=$(find BuildTools/.build -type f -name xcbeautify | grep -v dSYM)
if [ -z "$XCBEAUTIFY" ]; then
  echo "xcbeautify not found"
  exit 1
fi

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
if [ $? -ne 0 ]; then
  echo "`xcodebuild clean` failed with exit code $?"
  exit 1
fi

set -e
(cd VideoSubtitlesLib && rm -rf .build)

echo "--- Format ---"
set -e
$SWIFTFORMAT .

echo "--- Debug ---"
set +e
NSUnbufferedIO=YES xcodebuild -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Debug -destination 'generic/platform=iOS Simulator' -jobs $NUM_CORES 2>&1 | $XCBEAUTIFY --disable-logging
if [ $? -ne 0 ]; then
  echo "`xcodebuild` failed with exit code $?"
  exit 1
fi

echo "--- Test ---"
set +e
(cd VideoSubtitlesLib && NSUnbufferedIO=YES swift test 2>&1)
if [ $? -ne 0 ]; then
  echo "`swift test` failed with exit code $?"
  exit 1
fi

echo "===SUCCESS==="
