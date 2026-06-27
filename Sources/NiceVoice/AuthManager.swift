import Foundation

@Observable
final class AuthManager {
    static let shared = AuthManager()

    var canUseApp: Bool { true }
    var canUseBetaFeatures: Bool { LicenseAccessManager.shared.hasBetaAccess }

    private init() {}

    func initialize() async {
        LicenseAccessManager.shared.reload()
        debugLog("AuthManager initialized")
    }
}

extension Notification.Name {
    static let authDidChange = Notification.Name("authDidChange")
}
