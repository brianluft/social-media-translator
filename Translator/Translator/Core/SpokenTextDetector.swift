import AVFoundation
import Foundation
import Speech

/// Theory of Operation:
/// The SpokenTextDetector processes video audio to extract spoken text through the following steps:
///
/// 1. Audio Extraction:
///    - Uses AVAssetReader to extract audio from video
///    - Configures audio format for speech recognition
///    - Processes audio in chunks to stay within system limits
///
/// 2. Speech Recognition:
///    - Uses Speech framework's SFSpeechRecognizer
///    - Processes audio buffers for text recognition
///    - Captures text content and timing
///
/// 3. Segment Processing:
///    - Groups recognized text into segments
///    - Maintains timing information
///
/// 4. Progress Reporting:
///    - Reports progress through delegate pattern
///    - Provides completion callback with frame segments
///    - Reports errors if they occur during processing
///
/// The detector is designed to be memory-efficient (processing audio in chunks)
/// and accurate (using on-device speech recognition with language correction).

/// Handles detection of spoken text from video audio using Speech framework
public final class SpokenTextDetector: TextDetector {
    // MARK: - Properties

    private let audioActor: AudioProcessingActor
    private let delegateActor: TextDetectionDelegateActor
    private let recognitionLocale: Locale
    private let translationService: TranslationService?

    /// The delegate to receive detection progress and results
    public var delegate: TextDetectionDelegate? {
        get async { await delegateActor.delegate }
    }

    // MARK: - Initialization

    /// Creates a new speech detector for processing audio from video
    /// - Parameters:
    ///   - videoAsset: The AVAsset to process for speech detection
    ///   - delegate: Optional delegate to receive progress updates and results
    ///   - recognitionLocale: Locale for speech recognition (e.g. Locale(identifier: "en_US"))
    ///   - translationService: Optional translation service to translate detected text
    public init(
        videoAsset: AVAsset,
        delegate: TextDetectionDelegate? = nil,
        recognitionLocale: Locale = Locale(identifier: "en_US"),
        translationService: TranslationService? = nil
    ) throws {
        self.recognitionLocale = recognitionLocale
        self.translationService = translationService
        self.delegateActor = TextDetectionDelegateActor(delegate: delegate)
        self.audioActor = try AudioProcessingActor(
            videoAsset: videoAsset,
            recognitionLocale: recognitionLocale,
            translationService: translationService
        )
    }

    // MARK: - Public Methods

    /// Cancels any ongoing detection
    public func cancelDetection() {
        Task {
            await delegateActor.setCancelled(true)
            await audioActor.cancel()
        }
    }

    /// Processes the video asset to detect spoken text
    /// - Throws: Error if audio processing fails or if cancelled
    /// - Returns: Void, but calls delegate methods with progress and results
    public func detectText() async throws {
        do {
            // Reset cancellation state
            await delegateActor.setCancelled(false)

            // Request speech recognition authorization
            guard await requestSpeechAuthorization() else {
                throw NSError(
                    domain: "SpokenTextDetector",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"]
                )
            }

            // Get video duration
            let duration = try await audioActor.getDuration()
            let durationSeconds = CMTimeGetSeconds(duration)

            // Process audio in chunks
            let chunkDuration = 60.0
            let overlap = 2.0 // add 2-second overlap between chunks
            let chunkCount = Int(ceil(durationSeconds / chunkDuration))

            for chunkIndex in 0 ..< chunkCount {
                // Check for cancellation
                if await delegateActor.isCancelled() {
                    throw CancellationError()
                }

                // Revised: Use overlap for chunks after the first
                let startTime = Double(chunkIndex) * chunkDuration
                let adjustedStartTime = max(0, startTime - (chunkIndex > 0 ? overlap : 0))
                let endTime = min(startTime + chunkDuration, durationSeconds)
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: adjustedStartTime, preferredTimescale: 600),
                    end: CMTime(seconds: endTime, preferredTimescale: 600)
                )

                let segmentsWithTimestamps = try await audioActor.recognizeSpeech(in: timeRange)

                // Create a FrameSegments for each phrase with its timestamp
                for (segment, timestamp) in segmentsWithTimestamps {
                    let frameSegments = FrameSegments(
                        timestamp: startTime + timestamp,
                        segments: [segment]
                    )
                    print("Creating FrameSegments at time \(String(format: "%.2f", startTime + timestamp))s")
                    await delegateActor.didReceiveFrame(frameSegments)
                }

                // Report progress
                let progress = Float(chunkIndex + 1) / Float(chunkCount)
                await delegateActor.didProgress(progress)
            }

            // Final cancellation check before completing
            if await delegateActor.isCancelled() {
                throw CancellationError()
            }

            await delegateActor.didComplete()

        } catch {
            await delegateActor.didFail(error)
            throw error
        }
    }

    // MARK: - Private Methods

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

/// Actor to safely handle audio processing operations with non-Sendable AVFoundation types
private actor AudioProcessingActor {
    private let videoAsset: AVAsset
    private let speechRecognizer: SFSpeechRecognizer
    private let translationService: TranslationService?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isCancelled = false
    private var finalResults: [SFSpeechRecognitionResult] = [] // Add storage for final results

    init(
        videoAsset: AVAsset,
        recognitionLocale: Locale,
        translationService: TranslationService? = nil
    ) throws {
        self.videoAsset = videoAsset
        guard let recognizer = SFSpeechRecognizer(locale: recognitionLocale),
              recognizer.isAvailable
        else {
            throw NSError(
                domain: "SpokenTextDetector",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Speech recognition not available for locale: \(recognitionLocale.identifier)",
                ]
            )
        }
        self.speechRecognizer = recognizer
        self.speechRecognizer.defaultTaskHint = .dictation
        self.translationService = translationService
    }

    func getDuration() async throws -> CMTime {
        try await videoAsset.load(.duration)
    }

    func cancel() {
        isCancelled = true
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func processRecognitionResult(_ result: SFSpeechRecognitionResult) -> [(
        segment: TextSegment,
        timestamp: TimeInterval
    )] {
        print("\n=== Processing recognition result ===")
        print("Full transcription: \(result.bestTranscription.formattedString)")
        print("Confidence: \(result.bestTranscription.segments.map(\.confidence))")

        // First collect all segments with timing info
        var rawSegments: [(text: String, timestamp: TimeInterval, duration: TimeInterval)] = []
        for segment in result.bestTranscription.segments {
            // Don't filter on confidence here - we'll use the overall confidence
            rawSegments.append((
                text: segment.substring.trimmingCharacters(in: .whitespaces),
                timestamp: segment.timestamp,
                duration: segment.duration
            ))
            print(
                "Raw segment: '\(segment.substring)' at time \(String(format: "%.2f", segment.timestamp))s, duration \(String(format: "%.2f", segment.duration))s"
            )
        }

        print("Collected \(rawSegments.count) raw segments")

        // Handle empty results
        guard !rawSegments.isEmpty else {
            print("No segments found in result")
            return []
        }

        // Find all gaps between segments
        var gaps: [(index: Int, length: TimeInterval)] = []
        for i in 1 ..< rawSegments.count {
            let previous = rawSegments[i - 1]
            let current = rawSegments[i]
            let gap = current.timestamp - (previous.timestamp + previous.duration)
            gaps.append((index: i, length: gap))
            print("Gap between '\(previous.text)' and '\(current.text)': \(String(format: "%.2f", gap))s")
        }

        // Sort gaps by length descending
        gaps.sort { $0.length > $1.length }
        print("Found \(gaps.count) gaps, largest: \(String(format: "%.2f", gaps.first?.length ?? 0))s")

        // Start with one big phrase
        var phraseBreaks = Set<Int>([0, rawSegments.count])

        // Recursive function to split segments at largest gaps
        func splitSegmentAtLargestGap(start: Int, end: Int) -> [Int] {
            // Base case: single word or empty segment
            if end - start <= 1 {
                return [start, end]
            }

            // Calculate duration of this segment
            let startTime = rawSegments[start].timestamp
            let endTime = rawSegments[end - 1].timestamp + rawSegments[end - 1].duration
            let duration = endTime - startTime

            // If segment is short enough, keep it whole
            if duration <= 5.0 {
                return [start, end]
            }

            // Calculate all gaps and their properties
            var gaps: [(index: Int, length: TimeInterval)] = []
            var totalGapLength: TimeInterval = 0

            for i in (start + 1) ..< end {
                let previous = rawSegments[i - 1]
                let current = rawSegments[i]
                let gap = current.timestamp - (previous.timestamp + previous.duration)
                gaps.append((index: i, length: gap))
                totalGapLength += gap
            }

            // Calculate average gap length
            let averageGapLength = totalGapLength / TimeInterval(gaps.count)

            // Find largest gap
            let largestGap = gaps.max(by: { $0.length < $1.length })!

            // Determine split index based on gap analysis
            let splitIndex: Int
            if largestGap.length >= averageGapLength * 1.5 {
                // Use largest gap if it's at least 50% longer than average
                splitIndex = largestGap.index
                print(
                    "Splitting at largest gap: \(String(format: "%.2f", largestGap.length))s (avg: \(String(format: "%.2f", averageGapLength))s)"
                )
            } else {
                // Find the gap closest to the middle of the segment
                let midTime = startTime + (duration / 2)
                splitIndex = gaps.min(by: { gap1, gap2 in
                    let time1 = rawSegments[gap1.index].timestamp
                    let time2 = rawSegments[gap2.index].timestamp
                    return abs(time1 - midTime) < abs(time2 - midTime)
                })!.index
                print(
                    "Splitting at middle gap: \(String(format: "%.2f", gaps.first(where: { $0.index == splitIndex })?.length ?? 0))s"
                )
            }

            print("Splitting segment [\(start)-\(end)] at index \(splitIndex)")

            // Recursively split both halves
            let leftBreaks = splitSegmentAtLargestGap(start: start, end: splitIndex)
            let rightBreaks = splitSegmentAtLargestGap(start: splitIndex, end: end)

            // Combine breaks, removing duplicate boundary
            return leftBreaks + rightBreaks.dropFirst()
        }

        // Start with one big segment and recursively split it
        let allBreaks = splitSegmentAtLargestGap(start: 0, end: rawSegments.count)
        phraseBreaks = Set(allBreaks)

        // Convert breaks into phrases
        var phrases: [(text: String, timestamp: TimeInterval, duration: TimeInterval)] = []
        let sortedBreaks = Array(phraseBreaks).sorted()

        print("\nCreating phrases from \(sortedBreaks.count - 1) segments:")
        for i in 1 ..< sortedBreaks.count {
            let start = sortedBreaks[i - 1]
            let end = sortedBreaks[i]

            let segmentSlice = rawSegments[start ..< end]
            // Join with single space and trim any extra whitespace
            let text = segmentSlice.map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let timestamp = segmentSlice.first?.timestamp ?? 0
            let duration = (segmentSlice.last?.timestamp ?? 0) + (segmentSlice.last?.duration ?? 0) - timestamp

            if !text.isEmpty {
                phrases.append((text: text, timestamp: timestamp, duration: duration))
                print(
                    "✓ Created phrase: '\(text)' from \(String(format: "%.2f", timestamp))s to \(String(format: "%.2f", timestamp + duration))s (duration: \(String(format: "%.2f", duration))s)"
                )
            }
        }

        print("\nConverting \(phrases.count) phrases to TextSegments...")
        let segments = phrases.map { phrase in
            (
                segment: TextSegment(
                    text: phrase.text,
                    translatedText: nil,
                    position: CGRect(x: 0.2, y: 0.8, width: 0.6, height: 0.1),
                    confidence: Float(result.bestTranscription.segments.first?.confidence ?? 0.0)
                ),
                timestamp: phrase.timestamp
            )
        }
        print("Created \(segments.count) TextSegments")
        return segments
    }

    private func translateSegments(_ segments: [(segment: TextSegment, timestamp: TimeInterval)]) async throws -> [(
        segment: TextSegment,
        timestamp: TimeInterval
    )] {
        print("=== Starting translation of \(segments.count) segments ===")
        var translatedSegments: [(segment: TextSegment, timestamp: TimeInterval)] = []
        for (index, item) in segments.enumerated() {
            print("[\(index + 1)/\(segments.count)] Translating segment: '\(item.segment.text)'")
            var translatedText: String?
            if let translationService = self.translationService {
                print("Translation service available, attempting translation...")
                translatedText = try await translationService.translateText(item.segment.text)
                print("Translation result: '\(translatedText ?? "<nil>")'")
            } else {
                print("WARNING: No translation service available!")
            }

            translatedSegments.append((
                segment: TextSegment(
                    text: item.segment.text,
                    translatedText: translatedText,
                    position: item.segment.position,
                    confidence: item.segment.confidence
                ),
                timestamp: item.timestamp
            ))
            print("Added translated segment at timestamp \(String(format: "%.2f", item.timestamp))s")
        }
        print("=== Completed translation of \(translatedSegments.count) segments ===")
        return translatedSegments
    }

    func recognizeSpeech(in timeRange: CMTimeRange) async throws -> [(TextSegment, TimeInterval)] {
        print("\n=== Starting speech recognition for time range: \(timeRange) ===")
        finalResults = [] // Reset results at start of recognition

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create asset reader
        guard let audioTrack = try await videoAsset.loadTracks(withMediaType: .audio).first else {
            print("No audio track found in video")
            throw NSError(
                domain: "SpokenTextDetector",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No audio track found"]
            )
        }
        print("Found audio track: \(audioTrack)")

        let reader = try AVAssetReader(asset: videoAsset)
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100, // Standard audio rate
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
            ]
        )

        reader.timeRange = timeRange
        reader.add(output)
        reader.startReading()
        print("Started reading audio track")

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false
        request.taskHint = .dictation
        print("Created speech recognition request")

        // Process audio buffers
        defer {
            print("Cleaning up reader and request")
            reader.cancelReading()
        }

        var bufferCount = 0
        while let buffer = output.copyNextSampleBuffer() {
            bufferCount += 1
            if isCancelled {
                print("Processing cancelled after \(bufferCount) buffers")
                throw CancellationError()
            }

            // Convert CMSampleBuffer to AVAudioPCMBuffer
            let audioBuffer = try await convertToAudioBuffer(buffer)

            // Convert to float format for speech recognition
            guard let floatFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44100,
                channels: 1,
                interleaved: true
            ),
                let floatBuffer = AVAudioPCMBuffer(
                    pcmFormat: floatFormat,
                    frameCapacity: audioBuffer.frameLength
                ) else {
                print("Failed to create float format buffers")
                throw NSError(
                    domain: "SpokenTextDetector",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create float format"]
                )
            }

            // Convert Int16 samples to Float32 in range [-1, 1]
            let int16Data = audioBuffer.int16ChannelData![0]
            let floatData = floatBuffer.floatChannelData![0]
            let scale = Float32(Int16.max)

            for frame in 0 ..< Int(audioBuffer.frameLength) {
                floatData[frame] = Float32(int16Data[frame]) / scale
            }

            floatBuffer.frameLength = audioBuffer.frameLength
            request.append(floatBuffer)

            if bufferCount % 100 == 0 {
                print("Processed \(bufferCount) audio buffers")
            }
        }

        // After reading every buffer, end the audio stream
        print("All buffers appended - ending audio stream...")
        request.endAudio()
        print("Audio processing complete, waiting for final recognition results...")

        print("Starting recognition task")
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [self] result, error in
                guard !hasResumed else { return }

                if let error {
                    print("Recognition error: \(error)")
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }

                if let result {
                    print("Got recognition result: \(result.bestTranscription.formattedString)")
                    self.finalResults.append(result)
                    print("Now have \(self.finalResults.count) final results")

                    // If this is the final result, process it
                    if result.isFinal {
                        print("Got final result - processing now...")
                        hasResumed = true
                        Task {
                            do {
                                var allSegments: [(TextSegment, TimeInterval)] = []
                                for result in self.finalResults {
                                    let segments = self.processRecognitionResult(result)
                                    allSegments.append(contentsOf: segments)
                                }
                                print("Created \(allSegments.count) total segments, starting translation...")
                                let translatedSegments = try await self.translateSegments(allSegments)
                                print("Translation complete, resuming with \(translatedSegments.count) segments")
                                continuation.resume(returning: translatedSegments)
                            } catch {
                                print("ERROR during final processing: \(error)")
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
        }
    }

    private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) async throws -> AVAudioPCMBuffer {
        // Get audio buffer format
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw NSError(
                domain: "SpokenTextDetector",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get audio format"]
            )
        }

        // Create audio format
        let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(streamBasicDescription.pointee.mSampleRate),
            channels: AVAudioChannelCount(streamBasicDescription.pointee.mChannelsPerFrame),
            interleaved: true
        )

        guard let audioFormat else {
            throw NSError(
                domain: "SpokenTextDetector",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"]
            )
        }

        // Get audio buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw NSError(
                domain: "SpokenTextDetector",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get audio data"]
            )
        }

        // Create audio buffer
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frameCount))
        else {
            throw NSError(
                domain: "SpokenTextDetector",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"]
            )
        }

        // Copy data
        var size = 0
        var data: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &size,
            totalLengthOut: nil,
            dataPointerOut: &data
        )

        let channelCount = Int(audioFormat.channelCount)
        let source = UnsafeRawPointer(data!).assumingMemoryBound(to: Int16.self)
        let destination = pcmBuffer.int16ChannelData![0]

        // Simple copy for mono audio (most common case)
        if channelCount == 1 {
            for frame in 0 ..< frameCount {
                destination[Int(frame)] = source[Int(frame)]
            }
        } else {
            // Mix down multiple channels to mono
            for frame in 0 ..< frameCount {
                var sum: Int32 = 0
                for channel in 0 ..< channelCount {
                    sum += Int32(source[Int(frame) * channelCount + channel])
                }
                destination[Int(frame)] = Int16(sum / Int32(channelCount))
            }
        }

        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        return pcmBuffer
    }
}
