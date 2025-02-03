import AVFoundation
import Foundation
import os
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

@MainActor
class VideoSelectionViewModel: ObservableObject {
    @Published var selectedSourceLanguage: Locale.Language? {
        didSet {
            if let language = selectedSourceLanguage {
                saveSelectedLanguage(language)
            }
        }
    }

    @Published var supportedSourceLanguages: [Locale.Language] = []
    @Published var isLoading = true
    @Published var error: String?

    private let destinationLanguage: Locale.Language
    private let userDefaults = UserDefaults.standard
    private let selectedLanguageKey = "SelectedSourceLanguage"

    private func saveSelectedLanguage(_ language: Locale.Language) {
        let identifier = language.maximalIdentifier
        userDefaults.set(identifier, forKey: selectedLanguageKey)
        // Force synchronize to ensure it's written immediately
        userDefaults.synchronize()
    }

    private func loadSavedLanguage() -> Locale.Language? {
        guard let identifier = userDefaults.string(forKey: selectedLanguageKey) else {
            return nil
        }
        return Locale.Language(identifier: identifier)
    }

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
            displayName(for: $0) < displayName(for: $1)
        }

        // Try to restore saved language first
        if let savedLanguage = loadSavedLanguage() {
            if let matchingLanguage = supportedSourceLanguages
                .first(where: { $0.maximalIdentifier == savedLanguage.maximalIdentifier }) {
                selectedSourceLanguage = matchingLanguage
            }
        }

        // Otherwise use default logic
        if selectedSourceLanguage == nil {
            if let chineseSimp = supportedSourceLanguages.first(where: { $0.maximalIdentifier.contains("zh-Hans") }) {
                selectedSourceLanguage = chineseSimp
            } else if let first = supportedSourceLanguages.first {
                selectedSourceLanguage = first
            }
        }

        isLoading = false
    }

    var canSelectVideo: Bool {
        selectedSourceLanguage != nil && !supportedSourceLanguages.isEmpty && !isLoading
    }
}
