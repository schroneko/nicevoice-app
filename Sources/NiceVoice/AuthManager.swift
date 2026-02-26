import Foundation

struct AuthInfo: Codable {
    let sessionId: String
    let username: String
    let isSubscriber: Bool
    let lastVerified: Date
}

@Observable
final class AuthManager {
    static let shared = AuthManager()

    private(set) var isInitialized = false
    private(set) var isSubscriber = false
    private(set) var username: String?
    private(set) var isLoggedIn = false
    private(set) var deviceMismatch = false

    private let offlineGracePeriodDays = 7

    var canUseApp: Bool {
        isSubscriber
    }

    private init() {}

    func initialize() async {
        loadFromStorage()

        if let sessionId = LocalStorage.shared.getSessionId() {
            await verifyIfNeeded(sessionId: sessionId)
        }

        isInitialized = true
        debugLog("AuthManager initialized: subscriber=\(isSubscriber), user=\(username ?? "none")")
    }

    func login() {
        NukosukuAuthService.shared.startLogin()
    }

    func handleLoginCallback(sessionId: String) async {
        LocalStorage.shared.saveSessionId(sessionId)

        let deviceId = LocalStorage.shared.getOrCreateDeviceId()

        do {
            let response = try await NukosukuAuthService.shared.verify(
                sessionId: sessionId,
                deviceId: deviceId
            )

            let authInfo = AuthInfo(
                sessionId: sessionId,
                username: response.username,
                isSubscriber: response.isSubscriber && response.deviceRegistered,
                lastVerified: Date()
            )

            try LocalStorage.shared.saveCodable(authInfo, for: .authInfo)

            await MainActor.run {
                self.isLoggedIn = true
                self.username = response.username
                self.isSubscriber = response.isSubscriber && response.deviceRegistered
                self.deviceMismatch = response.error == "device_mismatch"
                NotificationCenter.default.post(name: .authDidChange, object: nil)
            }
        } catch {
            debugLog("Login verification failed: \(error)")
        }
    }

    func switchDevice() async {
        guard let sessionId = LocalStorage.shared.getSessionId() else { return }

        do {
            _ = try await NukosukuAuthService.shared.deregisterDevice(sessionId: sessionId)
            await handleLoginCallback(sessionId: sessionId)
        } catch {
            debugLog("Device switch failed: \(error)")
        }
    }

    func logout() async {
        if let sessionId = LocalStorage.shared.getSessionId() {
            _ = try? await NukosukuAuthService.shared.deregisterDevice(sessionId: sessionId)
        }

        LocalStorage.shared.clearAuth()

        await MainActor.run {
            self.isLoggedIn = false
            self.isSubscriber = false
            self.username = nil
            self.deviceMismatch = false
            NotificationCenter.default.post(name: .authDidChange, object: nil)
        }
    }

    private func loadFromStorage() {
        guard let authInfo: AuthInfo = try? LocalStorage.shared.loadCodable(for: .authInfo) else {
            return
        }

        isLoggedIn = true
        username = authInfo.username
        isSubscriber = authInfo.isSubscriber

        if !isWithinGracePeriod(authInfo) {
            isSubscriber = false
            debugLog("Offline grace period exceeded")
        }
    }

    private func isWithinGracePeriod(_ info: AuthInfo) -> Bool {
        let gracePeriodEnd = Calendar.current.date(
            byAdding: .day,
            value: offlineGracePeriodDays,
            to: info.lastVerified
        ) ?? info.lastVerified

        return Date() < gracePeriodEnd
    }

    private func shouldVerifyOnline() -> Bool {
        guard let info: AuthInfo = try? LocalStorage.shared.loadCodable(for: .authInfo) else {
            return false
        }

        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return info.lastVerified < oneDayAgo
    }

    private func verifyIfNeeded(sessionId: String) async {
        guard shouldVerifyOnline() else { return }

        let deviceId = LocalStorage.shared.getOrCreateDeviceId()

        do {
            let response = try await NukosukuAuthService.shared.verify(
                sessionId: sessionId,
                deviceId: deviceId
            )

            let authInfo = AuthInfo(
                sessionId: sessionId,
                username: response.username,
                isSubscriber: response.isSubscriber && response.deviceRegistered,
                lastVerified: Date()
            )

            try LocalStorage.shared.saveCodable(authInfo, for: .authInfo)

            await MainActor.run {
                self.username = response.username
                self.isSubscriber = response.isSubscriber && response.deviceRegistered
                self.deviceMismatch = response.error == "device_mismatch"
            }
        } catch AuthError.unauthorized {
            await MainActor.run {
                self.isLoggedIn = false
                self.isSubscriber = false
                self.username = nil
            }
            LocalStorage.shared.clearAuth()
        } catch {
            debugLog("Verification failed (offline?): \(error)")
        }
    }
}

extension Notification.Name {
    static let authDidChange = Notification.Name("authDidChange")
}
