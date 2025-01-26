.PHONY: all format test clean

all:
	cd VideoSubtitlesLib && swift build -c release
	xcodebuild -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Release

format:
	cd BuildTools && swift run -c release swiftformat ..

test:
	cd VideoSubtitlesLib && swift test

clean:
	cd VideoSubtitlesLib && rm -rf .build
	xcodebuild clean -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Release 
