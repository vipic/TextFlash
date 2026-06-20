import Foundation

extension Notification.Name {
    static let textFlashLanguageDidChange = Notification.Name("TextFlashLanguageDidChange")
    static let textFlashTriggerMatchingModeDidChange = Notification.Name("TextFlashTriggerMatchingModeDidChange")
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

enum TriggerMatchingMode: String, CaseIterable, Identifiable {
    case anywhere
    case boundary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anywhere:
            return L10n.t("settings.triggerMode.anywhere")
        case .boundary:
            return L10n.t("settings.triggerMode.boundary")
        }
    }
}

enum AppSettingsKeys {
    static let language = "TextFlashAppLanguage"
    static let deletionDelay = "TextFlashDeletionSettleDelayPerCharacter"
    static let triggerMatchingMode = "TextFlashTriggerMatchingMode"
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: AppSettingsKeys.language)
            NotificationCenter.default.post(name: .textFlashLanguageDidChange, object: self)
        }
    }
    @Published var deletionSettleDelayPerCharacter: Double {
        didSet {
            UserDefaults.standard.set(deletionSettleDelayPerCharacter, forKey: AppSettingsKeys.deletionDelay)
        }
    }
    @Published var triggerMatchingMode: TriggerMatchingMode {
        didSet {
            UserDefaults.standard.set(triggerMatchingMode.rawValue, forKey: AppSettingsKeys.triggerMatchingMode)
            NotificationCenter.default.post(name: .textFlashTriggerMatchingModeDidChange, object: self)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: AppSettingsKeys.language)
        language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
        let storedDelay = UserDefaults.standard.object(forKey: AppSettingsKeys.deletionDelay) as? Double
        deletionSettleDelayPerCharacter = storedDelay ?? 20
        let storedTriggerMode = UserDefaults.standard.string(forKey: AppSettingsKeys.triggerMatchingMode)
        triggerMatchingMode = storedTriggerMode.flatMap(TriggerMatchingMode.init(rawValue:)) ?? .anywhere
    }
}

enum L10n {
    /// 直接读 UserDefaults，避免 MainActor 依赖，非主线程也能安全调用
    private static var currentLanguageCode: String? {
        let raw = UserDefaults.standard.string(forKey: AppSettingsKeys.language)
        return raw.flatMap(AppLanguage.init(rawValue:))?.localizationCode
    }

    static func t(_ key: String) -> String {
        let bundle: Bundle
        if let code = currentLanguageCode,
           let resourcePath = Bundle.module.resourcePath {
            // .lproj 是目录，不能用 path(forResource:ofType:)（只查文件）
            let lproj = (resourcePath as NSString).appendingPathComponent("\(code).lproj")
            if let localizedBundle = Bundle(path: lproj) {
                bundle = localizedBundle
            } else {
                bundle = .module
            }
        } else {
            bundle = .module
        }

        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }
}
