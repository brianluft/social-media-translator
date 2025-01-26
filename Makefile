.PHONY: all format test clean

all:
	cd VideoSubtitlesLib && swift build -c release
	xcodebuild -project TranslateVideoSubtitles/TranslateVideoSubtitles.xcodeproj -scheme TranslateVideoSubtitles -configuration Release

format:
	cd BuildTools && swift run -c release swiftformat ..

test:
	cd VideoSubtitlesLib && swift test

clean:
	cd VideoSubtitlesLib && rm -rf .build
	cd TranslateVideoSubtitles && xcodebuild clean -project TranslateVideoSubtitles.xcodeproj -scheme TranslateVideoSubtitles -configuration Release 
