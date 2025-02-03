import SwiftUI

struct TranslateVideoSubtitlesApp: App {
    init() {
        // Clean up any orphaned temporary files on launch
        VideoProcessor.cleanupTemporaryFiles()
    }

    var body: some Scene {
        WindowGroup {
            VideoSelectionView()
        }
    }
}
