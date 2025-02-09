import Foundation

/// Manages temporary files used during video processing
enum TempFileManager {
    /// Returns the app's temporary directory for video files
    static var temporaryVideoDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AutoDeletedTempFiles", isDirectory: true)
    }

    /// Cleans up any orphaned temporary video files
    static func cleanupTemporaryFiles() {
        do {
            let fileManager = FileManager.default
            // Create directory if it doesn't exist
            try? fileManager.createDirectory(at: temporaryVideoDirectory, withIntermediateDirectories: true)

            // Get all files in the directory
            let files = try fileManager.contentsOfDirectory(
                at: temporaryVideoDirectory,
                includingPropertiesForKeys: nil
            )

            // Remove each file
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        } catch {
            print("Failed to cleanup temporary files: \(error)")
        }
    }
}
