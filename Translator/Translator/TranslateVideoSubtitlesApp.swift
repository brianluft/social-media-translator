import SwiftUI

struct TranslatorApp: App {
    init() {
        // Clean up any orphaned temporary files on launch
        TempFileManager.cleanupTemporaryFiles()
    }

    var body: some Scene {
        WindowGroup {
            VideoSelectionView()
        }
    }
}
