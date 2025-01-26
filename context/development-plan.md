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
   - 👤 Create expected .srt outputs (manually transcribe timing/text)
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
   - Basic Apple Translation setup
   - Single text translation
   - Batch processing
   - Progress reporting
   - Error handling

2. Write translation tests
   - Mock translation service for tests
   - Test batch processing
   - Test progress reporting
   - Debug logging for translation steps

## Phase 4: SRT Generation
1. Create SRT writer
   - Basic SRT format implementation
   - Timestamp formatting
   - File output

2. Write SRT tests
   - Test timestamp formatting
   - Test file output
   - Test with known subtitles
   - Compare generated vs expected SRT files

## Phase 5: Integration Testing
1. End-to-end tests
   - 👤 Record performance metrics
   - 👤 Monitor memory usage in Xcode
   - Process sample videos
   - Verify outputs against known good SRTs
   - Detailed debug logging

## Phase 6: Video Player Integration
1. Implement `VideoPlayerController`
   - 👤 Add required AVKit permissions/entitlements
   - Basic AVKit setup
   - Playback controls
   - Subtitle timing integration

2. Create `SubtitleOverlayRenderer`
   - Basic text rendering
   - Position calculation
   - Style management

## Phase 7: iOS App Development
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

4. Create playback UI
   - Video player integration
   - Subtitle overlay
   - Basic controls

## Development Notes

### Testing Strategy
👤 Required test assets:
- Short video clips (5-10s) with burned-in subtitles
- Videos with different subtitle styles/positions
- Videos in different source languages
- Manually created .srt files matching test videos

### Performance Considerations
- Process video in chunks
- Batch translations
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
