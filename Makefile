.PHONY: all release format test clean

all: clean test debug

debug:
	cd VideoSubtitlesLib && swift build -c debug
	xcodebuild -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Debug -destination 'generic/platform=iOS Simulator'

release:
	cd VideoSubtitlesLib && swift build -c release
	xcodebuild -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Release -destination 'generic/platform=iOS Simulator'

format:
	cd BuildTools && swift run -c release swiftformat ..

test: clean
	cd VideoSubtitlesLib && swift test

clean:
	cd VideoSubtitlesLib && rm -rf .build
	xcodebuild -quiet clean -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Release -destination 'generic/platform=iOS Simulator'
