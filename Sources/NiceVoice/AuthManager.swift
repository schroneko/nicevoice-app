import Foundation

@Observable
final class AuthManager {
    static let shared = AuthManager()

    var canUseApp: Bool { true }

    private init() {}

    func initialize() async {
        debugLog("AuthManager initialized")
    }
}

extension Notification.Name {
    static let authDidChange = Notification.Name("authDidChange")
}
