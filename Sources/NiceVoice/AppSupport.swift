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
