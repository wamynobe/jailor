import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case vietnamese = "vi"

    var id: String { rawValue }

    /// Language names are intentionally shown in their own language.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }
}

extension Notification.Name {
    static let jailorLanguageDidChange = Notification.Name("JailorLanguageDidChange")
}

/// Lightweight runtime localization.
///
/// English is the source language and the default. Keys are English phrases;
/// missing Vietnamese keys fall back to English, so the UI never breaks when a
/// new string is added. The selected language is persisted in UserDefaults and
/// can be changed live from Settings.
@MainActor
final class Localization: ObservableObject {
    static let shared = Localization()

    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
            NotificationCenter.default.post(name: .jailorLanguageDidChange, object: nil)
        }
    }

    private static let storageKey = "jailor.language"

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        language = AppLanguage(rawValue: stored ?? "") ?? .english
    }

    func t(_ key: String) -> String {
        guard language == .vietnamese else { return key }
        return VietnameseStrings.table[key] ?? key
    }

    func t(_ key: String, _ arguments: CVarArg...) -> String {
        let format = t(key)
        let locale = Locale(identifier: language.rawValue)
        return String(format: format, locale: locale, arguments: arguments)
    }
}

@MainActor
func L(_ key: String) -> String {
    Localization.shared.t(key)
}

@MainActor
func L(_ key: String, _ arguments: CVarArg...) -> String {
    Localization.shared.t(key, arguments)
}
