import Foundation
import CommonCrypto

struct AuthInfo: Codable {
    let sessionId: String
    let username: String
    let isSubscriber: Bool
    let lastVerified: Date
}

struct SignedAuthInfo: Codable {
    let payload: Data
    let signature: Data
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
    private static var hmacSalt: String { ObfuscatedStrings.hmacSalt }

    var hasEarlyAccessEntitlement: Bool {
        isSubscriber
    }

    var accessState: AppAccessState {
        AppAccessPolicy.accessState(hasEarlyAccess: hasEarlyAccessEntitlement)
    }

    var canUseApp: Bool {
        accessState.isUnlocked
    }

    @inline(__always)
    func verifyAuthIntegrity() -> Bool {
        if AppAccessPolicy.isPublicReleaseEnabled {
            return true
        }
        guard let signed: SignedAuthInfo = try? LocalStorage.shared.loadCodable(for: .authInfo) else {
            isSubscriber = false
            return false
        }
        let expectedSignature = computeHMAC(signed.payload)
        guard signed.signature == expectedSignature else {
            invalidatePersistedAuth()
            return false
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let info = try? decoder.decode(AuthInfo.self, from: signed.payload) else {
            invalidatePersistedAuth()
            return false
        }
        guard let storedSessionId = LocalStorage.shared.getSessionId(),
              storedSessionId == info.sessionId else {
            debugLog("Auth rejected: session mismatch between Keychain and signed payload")
            invalidatePersistedAuth()
            return false
        }
        guard info.isSubscriber, info.lastVerified <= Date(), isWithinGracePeriod(info) else {
            isSubscriber = false
            return false
        }
        return true
    }

    private init() {}

    func initialize() async {
        loadFromStorage()

        if let sessionId = LocalStorage.shared.getSessionId() {
            await verifyIfNeeded(sessionId: sessionId)
        }

        isInitialized = true
        debugLog("AuthManager initialized: earlyAccess=\(hasEarlyAccessEntitlement), public=\(AppAccessPolicy.isPublicReleaseEnabled), user=\(username ?? "none")")
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

            saveSignedAuthInfo(authInfo)

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
        guard let authInfo = loadVerifiedAuthInfo() else { return }

        guard let storedSessionId = LocalStorage.shared.getSessionId(),
              storedSessionId == authInfo.sessionId else {
            debugLog("Auth rejected: stored session missing or mismatched")
            invalidatePersistedAuth()
            return
        }

        isLoggedIn = true
        username = authInfo.username

        if authInfo.lastVerified > Date() {
            debugLog("Auth rejected: lastVerified is in the future (tampering?)")
            isSubscriber = false
            LocalStorage.shared.clearAuth()
            return
        }

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
        guard let info = loadVerifiedAuthInfo() else { return false }

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

            saveSignedAuthInfo(authInfo)

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

    private func saveSignedAuthInfo(_ authInfo: AuthInfo) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(authInfo) else {
            debugLog("Failed to encode AuthInfo for signing")
            return
        }

        let signature = computeHMAC(payload)
        let signed = SignedAuthInfo(payload: payload, signature: signature)
        try? LocalStorage.shared.saveCodable(signed, for: .authInfo)
    }

    private func loadVerifiedAuthInfo() -> AuthInfo? {
        if let signed: SignedAuthInfo = try? LocalStorage.shared.loadCodable(for: .authInfo) {
            let expectedSignature = computeHMAC(signed.payload)
            guard signed.signature == expectedSignature else {
                debugLog("Auth signature mismatch - data may be tampered")
                LocalStorage.shared.clearAuth()
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(AuthInfo.self, from: signed.payload)
        }

        if let legacy: AuthInfo = try? LocalStorage.shared.loadCodable(for: .authInfo) {
            debugLog("Migrating unsigned AuthInfo to signed format (forcing re-verification)")
            let unverified = AuthInfo(
                sessionId: legacy.sessionId,
                username: legacy.username,
                isSubscriber: false,
                lastVerified: Date.distantPast
            )
            saveSignedAuthInfo(unverified)
            return unverified
        }

        return nil
    }

    private func invalidatePersistedAuth() {
        LocalStorage.shared.clearAuth()
        isLoggedIn = false
        isSubscriber = false
        username = nil
        deviceMismatch = false
    }

    private func signingKey() -> Data {
        let deviceId = LocalStorage.shared.getOrCreateDeviceId()
        let bundleId = Bundle.main.bundleIdentifier ?? "app.nicevoice.NiceVoice"
        let material = "\(deviceId)\(bundleId)\(Self.hmacSalt)"

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let bytes = Array(material.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash)
    }

    private func computeHMAC(_ data: Data) -> Data {
        let key = signingKey()
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBytes.baseAddress,
                    key.count,
                    dataBytes.baseAddress,
                    data.count,
                    &hmac
                )
            }
        }

        return Data(hmac)
    }
}

extension Notification.Name {
    static let authDidChange = Notification.Name("authDidChange")
}
