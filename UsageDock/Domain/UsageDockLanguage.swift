import Foundation

enum UsageDockLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case japanese = "ja"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .japanese: "日本語"
        case .english: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .japanese: Locale(identifier: "ja")
        case .english: Locale(identifier: "en")
        }
    }

    var prefersJapanese: Bool {
        switch self {
        case .japanese:
            true
        case .english:
            false
        case .system:
            Locale.preferredLanguages.first?.lowercased().hasPrefix("ja") == true
        }
    }

    var settingsWindowTitle: String {
        prefersJapanese ? "UsageDock 設定" : "UsageDock Settings"
    }
}
