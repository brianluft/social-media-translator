/// Protocol for reporting text detection progress
public protocol TextDetectionDelegate: AnyObject {
    func detectionDidProgress(_ progress: Float)
    func detectionDidReceiveFrame(_ frame: FrameSegments)
    func detectionDidComplete()
    func detectionDidFail(with error: Error)
}
