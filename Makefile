.PHONY: all format test clean

all:
	cd VideoSubtitlesLib && swift build -c release
	xcodebuild -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Release 2>&1 | grep -E "warning:|error:"

format:
	cd BuildTools && swift run -c release swiftformat ..

test:
	cd VideoSubtitlesLib && swift test

clean:
	cd VideoSubtitlesLib && rm -rf .build
	xcodebuild -quiet clean -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Release 2>&1 | grep -E "warning:|error:"
