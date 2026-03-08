import Foundation

enum AppBuildChannel: Equatable {
    case debug
    case release

    static var current: AppBuildChannel {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }
}

enum AppFeatureFlags {
    private static let enableDeveloperUIKey = "NICEVOICE_ENABLE_DEVELOPER_UI"
    private static let disableDeveloperUIKey = "NICEVOICE_DISABLE_DEVELOPER_UI"

    static func isDeveloperToolsEnabled(
        build: AppBuildChannel = .current,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment[disableDeveloperUIKey] == "1" {
            return false
        }
        if environment[enableDeveloperUIKey] == "1" {
            return true
        }
        return build == .debug
    }
}

enum BundleInfo {
    static func shortVersion(in bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func buildNumber(in bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? shortVersion(in: bundle)
    }
}

enum AppUpdateConfiguration {
    private static let feedURLKey = "SUFeedURL"
    private static let publicKeyKey = "SUPublicEDKey"

    static func feedURLString(in bundle: Bundle = .main) -> String? {
        let value = bundle.object(forInfoDictionaryKey: feedURLKey) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func publicKey(in bundle: Bundle = .main) -> String? {
        let value = bundle.object(forInfoDictionaryKey: publicKeyKey) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func isConfigured(in bundle: Bundle = .main) -> Bool {
        feedURLString(in: bundle) != nil && publicKey(in: bundle) != nil
    }
}

enum SupportLink: String, CaseIterable, Identifiable {
    case updates
    case privacyPolicy
    case termsOfService
    case commercialDisclosure
    case supportEmail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updates: return "更新履歴"
        case .privacyPolicy: return "プライバシーポリシー"
        case .termsOfService: return "利用規約"
        case .commercialDisclosure: return "特定商取引法に基づく表記"
        case .supportEmail: return "お問い合わせ"
        }
    }

    var subtitle: String {
        switch self {
        case .updates: return "最新のリリース内容と更新状況"
        case .privacyPolicy: return "保存データと外部送信先の取り扱い"
        case .termsOfService: return "利用条件と禁止事項"
        case .commercialDisclosure: return "販売条件・提供時期・返金方針"
        case .supportEmail: return "不具合報告やサポートへの連絡先"
        }
    }

    var url: URL {
        switch self {
        case .updates:
            return URL(string: "https://nicevoice.app/updates.html")!
        case .privacyPolicy:
            return URL(string: "https://nicevoice.app/privacy.html")!
        case .termsOfService:
            return URL(string: "https://nicevoice.app/terms.html")!
        case .commercialDisclosure:
            return URL(string: "https://nicevoice.app/commercial.html")!
        case .supportEmail:
            return URL(string: "mailto:support@nicevoice.app")!
        }
    }
}
