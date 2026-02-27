import Foundation

enum StorageKey: String {
    case deviceId = "com.nicevoice.device-id"
    case authInfo = "com.nicevoice.auth-info"
    case sessionId = "com.nicevoice.session-id"
    case deepgramApiKey = "com.nicevoice.deepgram-api-key"
}

enum StorageError: LocalizedError {
    case itemNotFound
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Item not found"
        case .encodingFailed:
            return "Failed to encode data"
        case .decodingFailed:
            return "Failed to decode data"
        }
    }
}

final class LocalStorage {
    static let shared = LocalStorage()

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStorage.shared

    private static let keychainAccountAuthInfo = "authInfo"
    private static let keychainAccountSessionId = "sessionId"

    private init() {
        migrateToKeychainIfNeeded()
    }

    func saveCodable<T: Codable>(_ value: T, for key: StorageKey) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else {
            throw StorageError.encodingFailed
        }

        switch key {
        case .authInfo:
            guard keychain.save(data, account: Self.keychainAccountAuthInfo) else {
                throw StorageError.encodingFailed
            }
        default:
            defaults.set(data, forKey: key.rawValue)
        }
    }

    func loadCodable<T: Codable>(for key: StorageKey) throws -> T {
        let data: Data?

        switch key {
        case .authInfo:
            data = keychain.load(account: Self.keychainAccountAuthInfo)
        default:
            data = defaults.data(forKey: key.rawValue)
        }

        guard let data else {
            throw StorageError.itemNotFound
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(T.self, from: data) else {
            throw StorageError.decodingFailed
        }
        return value
    }

    func delete(for key: StorageKey) {
        switch key {
        case .authInfo:
            keychain.delete(account: Self.keychainAccountAuthInfo)
        case .sessionId:
            keychain.delete(account: Self.keychainAccountSessionId)
        default:
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    func getOrCreateDeviceId() -> String {
        if let deviceId = defaults.string(forKey: StorageKey.deviceId.rawValue) {
            return deviceId
        }
        let newDeviceId = UUID().uuidString
        defaults.set(newDeviceId, forKey: StorageKey.deviceId.rawValue)
        return newDeviceId
    }

    func saveSessionId(_ sessionId: String) {
        _ = keychain.saveString(sessionId, account: Self.keychainAccountSessionId)
    }

    func getSessionId() -> String? {
        keychain.loadString(account: Self.keychainAccountSessionId)
    }

    func clearAuth() {
        delete(for: .authInfo)
        delete(for: .sessionId)
    }

    private func migrateToKeychainIfNeeded() {
        if let sessionId = defaults.string(forKey: StorageKey.sessionId.rawValue) {
            _ = keychain.saveString(sessionId, account: Self.keychainAccountSessionId)
            defaults.removeObject(forKey: StorageKey.sessionId.rawValue)
            debugLog("Migrated sessionId from UserDefaults to Keychain")
        }

        if let authData = defaults.data(forKey: StorageKey.authInfo.rawValue) {
            keychain.save(authData, account: Self.keychainAccountAuthInfo)
            defaults.removeObject(forKey: StorageKey.authInfo.rawValue)
            debugLog("Migrated authInfo from UserDefaults to Keychain")
        }
    }
}
