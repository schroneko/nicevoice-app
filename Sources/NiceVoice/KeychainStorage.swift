import Foundation
import Security

final class KeychainStorage {
    static let shared = KeychainStorage()

    private var service: String { ObfuscatedStrings.keychainService }

    private init() {}

    @discardableResult
    func save(_ data: Data, account: String) -> Bool {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            debugLog("Keychain save failed for \(account): \(status)")
        }
        return status == errSecSuccess
    }

    func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            debugLog("Keychain load failed for \(account): \(status)")
        }
        return result as? Data
    }

    @discardableResult
    func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func saveString(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(data, account: account)
    }

    func loadString(account: String) -> String? {
        guard let data = load(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
