import AVFoundation
import Foundation
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

@MainActor
class VideoSelectionViewModel: ObservableObject {
    @Published var selectedSourceLanguage: Locale.Language?
    @Published var supportedSourceLanguages: [Locale.Language] = []
    @Published var isLoading = true
    @Published var error: String?

    private let destinationLanguage: Locale.Language

    func displayName(for language: Locale.Language) -> String {
        let currentLocale = Locale.current

        if let languageCode = language.languageCode?.identifier,
           let baseName = currentLocale.localizedString(forLanguageCode: languageCode) {
            // Only show script if there are multiple scripts for this language
            let sameLanguageVariants = supportedSourceLanguages.filter {
                $0.languageCode?.identifier == languageCode
            }

            if sameLanguageVariants.count > 1,
               let script = language.script,
               let scriptName = currentLocale.localizedString(forScriptCode: script.identifier) {
                return "\(baseName) (\(scriptName))"
            }
            return baseName
        }

        return language.maximalIdentifier
    }

    init() {
        // Get system language as destination
        destinationLanguage = Locale.current.language
        Task {
            await loadSupportedLanguages()
        }
    }

    private func loadSupportedLanguages() async {
        let availability = LanguageAvailability()

        // Get all supported languages
        let languages = await availability.supportedLanguages

        // Filter languages that can translate to destination language
        var supported: [Locale.Language] = []
        for language in languages {
            let status = await availability.status(from: language, to: destinationLanguage)
            if status != .unsupported {
                supported.append(language)
            }
        }

        supportedSourceLanguages = supported.sorted {
            ($0.languageCode?.identifier ?? "") < ($1.languageCode?.identifier ?? "")
        }

        // Default to Simplified Chinese if available, otherwise first language
        if let chineseSimp = supported.first(where: { $0.languageCode?.identifier == "zh-Hans" }) {
            selectedSourceLanguage = chineseSimp
        } else if let first = supported.first {
            selectedSourceLanguage = first
        }

        isLoading = false
    }

    var canSelectVideo: Bool {
        selectedSourceLanguage != nil && !supportedSourceLanguages.isEmpty && !isLoading
    }

    func selectVideo() {
        // TODO: Implement PHPickerViewController presentation
    }

    func processVideo(_ asset: AVAsset) {
        // TODO: Implement video processing using VideoSubtitlesLib
    }
}
