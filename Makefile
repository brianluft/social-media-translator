.PHONY: all format test clean

all:
	@xcodebuild -quiet -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Release -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2'

format:
	@cd BuildTools && swift run -c release swiftformat ..

test:
	@cd VideoSubtitlesLib && swift test

clean:
	@cd VideoSubtitlesLib && rm -rf .build
	@xcodebuild -quiet clean -workspace TranslateVideoSubtitles.xcworkspace -scheme TranslateVideoSubtitles -configuration Release -destination 'platform=macOS,arch=arm64'
