/// Actor to safely handle delegate calls and state
actor TextDetectionDelegateActor {
    weak var delegate: TextDetectionDelegate?
    private var isCancelledFlag = false

    init(delegate: TextDetectionDelegate?) {
        self.delegate = delegate
    }

    func isCancelled() -> Bool {
        isCancelledFlag
    }

    func setCancelled(_ value: Bool) {
        isCancelledFlag = value
    }

    func didProgress(_ progress: Float) {
        delegate?.detectionDidProgress(progress)
    }

    func didReceiveFrame(_ frame: FrameSegments) {
        delegate?.detectionDidReceiveFrame(frame)
    }

    func didComplete() {
        delegate?.detectionDidComplete()
    }

    func didFail(_ error: Error) {
        delegate?.detectionDidFail(with: error)
    }
}
