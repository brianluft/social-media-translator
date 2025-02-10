/// Base protocol for text detection from various sources
public protocol TextDetector: Sendable {
    /// The delegate to receive detection progress and results
    var delegate: TextDetectionDelegate? { get async }

    /// Cancels any ongoing detection
    func cancelDetection()

    /// Processes the source to detect text
    /// - Throws: Error if processing fails or if cancelled
    func detectText() async throws
}
