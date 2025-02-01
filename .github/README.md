# Translate Video Subtitles app

An iOS app that translates burned-in video subtitles to your preferred language.

1. Choose a video from your photo library. This can be a video that you saved from social media.
2. The app detects the subtitles and translates them to your language.
3. The video plays with the translated subtitles.

## Building from Source

### Requirements
- Xcode 13.0 or later
- iOS 15.0+ / macOS 12.0+
- Swift 5.5+

### Steps

1. Clone the repository:
```bash
git clone https://github.com/brianluft/translate-video-subtitles.git
cd translate-video-subtitles
```

2. Open the project:
```bash
open TranslateVideoSubtitles/TranslateVideoSubtitles.xcodeproj
```

3. Build the project in Xcode:
- Select your target device
- Press ⌘B or select Product > Build

### Running Tests

1. Run the library tests:
```bash
cd VideoSubtitlesLib
swift test
```

2. Run the app tests in Xcode:
- Press ⌘U or select Product > Test
- This will run both unit tests and UI tests

Note: Some tests require test video assets which are included in the repository under `VideoSubtitlesLib/Tests/VideoSubtitlesLibTests/TestAssets/Videos/`.
