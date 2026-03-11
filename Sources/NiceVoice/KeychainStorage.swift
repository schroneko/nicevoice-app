import Foundation
import Security

final class KeychainStorage {
    static let shared = KeychainStorage()
    private let missingEntitlementStatus = OSStatus(errSecMissingEntitlement)

    private var service: String { ObfuscatedStrings.keychainService }

    private init() {}

    @discardableResult
    func save(_ data: Data, account: String) -> Bool {
        delete(account: account)
        let status = performWithKeychainFallback(account: account) { useDataProtectionKeychain in
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String: data,
            ]
            if useDataProtectionKeychain {
                query[kSecUseDataProtectionKeychain as String] = true
            }
            return SecItemAdd(query as CFDictionary, nil)
        }
        if status != errSecSuccess {
            debugLog("Keychain save failed for \(account): \(status)")
        }
        return status == errSecSuccess
    }

    func load(account: String) -> Data? {
        var result: AnyObject?
        let status = performWithKeychainFallback(account: account) { useDataProtectionKeychain in
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if useDataProtectionKeychain {
                query[kSecUseDataProtectionKeychain as String] = true
            }
            return SecItemCopyMatching(query as CFDictionary, &result)
        }
        if status != errSecSuccess && status != errSecItemNotFound {
            debugLog("Keychain load failed for \(account): \(status)")
        }
        return result as? Data
    }

    @discardableResult
    func delete(account: String) -> Bool {
        let status = performWithKeychainFallback(account: account) { useDataProtectionKeychain in
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            if useDataProtectionKeychain {
                query[kSecUseDataProtectionKeychain as String] = true
            }
            return SecItemDelete(query as CFDictionary)
        }
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

    private func performWithKeychainFallback(
        account: String,
        operation: (Bool) -> OSStatus
    ) -> OSStatus {
        let primaryStatus = operation(true)
        if primaryStatus != missingEntitlementStatus {
            return primaryStatus
        }

        debugLog("Keychain data protection unavailable for \(account), retrying without it")
        return operation(false)
    }
}
