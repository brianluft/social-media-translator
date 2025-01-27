# Development Plan

## Phase 1: Project Setup
1. Create Swift Package for core library `VideoSubtitlesLib`
   - 👤 Create new project in Xcode
   - Set up package manifest
   - Define basic module structure
   - Add test target with XCTest

2. Create basic models
   - `TextSegment` struct for individual text blocks
     - Position (rect in normalized coordinates)
     - Text content
     - Confidence score
   - `FrameSegments` struct for all text in a frame
     - Timestamp
     - Array of TextSegments
   - `TranslatedSegment` struct
     - Original TextSegment
     - Translated text
     - Style/formatting info
   - Add JSON coding for testing

3. Set up test infrastructure
   - 👤 Source and add sample .mp4 files with burned-in subtitles
   - Create test utilities
   - Add debug logging helpers

## Phase 2: Core Subtitle Detection
1. Implement `SubtitleDetector`
   - 👤 Add required framework dependencies in Xcode
   - Basic frame extraction using AVFoundation
   - Vision setup for OCR with text rectangle detection
   - Test with single frame first
   - Implement text segment classification
   - Track segments across frames by position
   - Add frame-by-frame processing
   - Add progress reporting protocol

2. Write tests for SubtitleDetector
   - Test with known frames
   - Test progress reporting
   - Test error handling
   - Debug logging for frame data and OCR results

## Phase 3: Translation Integration
1. Implement `TranslationService`
   - 👤 Enable translation capabilities in Xcode project
   - Basic Apple Translation setup within UI context
   - Single text translation with UI delegate
   - Batch processing in-app
   - Progress reporting
   - Error handling

## Phase 4: iOS App Development
1. Create SwiftUI project
   - 👤 Create new iOS app target in Xcode
   - 👤 Configure signing and capabilities
   - Set up dependency on VideoSubtitlesLib
   - Basic UI structure

2. Implement video selection
   - 👤 Add PhotosKit permissions to Info.plist
   - PhotosKit integration
   - Permission handling
   - File size handling

3. Add processing UI
   - Progress indicators
   - Cancel support
   - Error handling

4. Create basic app flow
   - Navigation structure
   - Error views
   - Loading states
   - Settings view for language selection

## Phase 5: Video Player Integration
1. Implement `VideoPlayerController`
   - 👤 Add required AVKit permissions/entitlements
   - Basic AVKit setup
   - Playback controls
   - Subtitle timing integration

2. Create `SubtitleOverlayRenderer`
   - Basic text rendering
   - Position calculation
   - Style management

3. Integrate player UI
   - Video player view
   - Subtitle overlay
   - Playback controls
   - Full-screen support

## Development Notes

### Testing Strategy
👤 Required test assets:
- Short video clips (5-10s) with burned-in subtitles
- Videos with different subtitle styles/positions
- Videos in different source languages

### Performance Considerations
- Process video in chunks
- Batch translations within UI context
- Cache frame analysis
- Profile memory usage early

### SwiftUI Notes
- MVVM architecture
- Separate view models for:
  - Video selection
  - Processing
  - Playback
- Use Combine for async operations

### Environment Setup
👤 Required setup:
- Xcode 15+ installed
- iOS development certificates
- Device or simulator for testing
- Source videos for testing
