import Foundation

extension Notification.Name {
    static let textFlashLanguageDidChange = Notification.Name("TextFlashLanguageDidChange")
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String { rawValue }

    var localizationCode: String? {
        switch self {
        case .system:
            return nil
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.t("settings.language.system")
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let languageKey = "TextFlashAppLanguage"
    private let deletionDelayKey = "TextFlashDeletionSettleDelayPerCharacter"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: languageKey)
            NotificationCenter.default.post(name: .textFlashLanguageDidChange, object: self)
        }
    }
    @Published var deletionSettleDelayPerCharacter: Double {
        didSet {
            UserDefaults.standard.set(deletionSettleDelayPerCharacter, forKey: deletionDelayKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: languageKey)
        language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
        let storedDelay = UserDefaults.standard.object(forKey: deletionDelayKey) as? Double
        deletionSettleDelayPerCharacter = storedDelay ?? 20
    }
}

enum L10n {
    static func t(_ key: String) -> String {
        let language = MainActor.assumeIsolated {
            AppSettings.shared.language
        }

        let bundle: Bundle
        if let code = language.localizationCode,
           let path = Bundle.module.path(forResource: code, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else {
            bundle = .module
        }

        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }
}
