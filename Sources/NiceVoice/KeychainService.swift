import Foundation
import Security

enum KeychainKey: String {
    case licenseInfo = "com.nicevoice.license-info"
    case deviceId = "com.nicevoice.device-id"
    case firstLaunchDate = "com.nicevoice.first-launch-date"
}

enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found"
        case .duplicateItem:
            return "Keychain item already exists"
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) {
                return message as String
            }
            return "Keychain error: \(status)"
        case .encodingFailed:
            return "Failed to encode data"
        case .decodingFailed:
            return "Failed to decode data"
        }
    }
}

final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "app.nicevoice.NiceVoice"

    private init() {}

    func save(_ data: Data, for key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            try update(data, for: key)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func update(_ data: Data, for key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func load(for key: KeychainKey) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw KeychainError.itemNotFound
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.decodingFailed
        }

        return data
    }

    func delete(for key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func exists(for key: KeychainKey) -> Bool {
        do {
            _ = try load(for: key)
            return true
        } catch {
            return false
        }
    }

    func saveString(_ string: String, for key: KeychainKey) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data, for: key)
    }

    func loadString(for key: KeychainKey) throws -> String {
        let data = try load(for: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    func saveCodable<T: Codable>(_ value: T, for key: KeychainKey) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else {
            throw KeychainError.encodingFailed
        }
        try save(data, for: key)
    }

    func loadCodable<T: Codable>(for key: KeychainKey) throws -> T {
        let data = try load(for: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(T.self, from: data) else {
            throw KeychainError.decodingFailed
        }
        return value
    }

    func getOrCreateDeviceId() -> String {
        if let deviceId = try? loadString(for: .deviceId) {
            return deviceId
        }

        let newDeviceId = UUID().uuidString
        try? saveString(newDeviceId, for: .deviceId)
        return newDeviceId
    }

    func getFirstLaunchDate() -> Date {
        if let date: Date = try? loadCodable(for: .firstLaunchDate) {
            return date
        }

        let now = Date()
        try? saveCodable(now, for: .firstLaunchDate)
        return now
    }
}
