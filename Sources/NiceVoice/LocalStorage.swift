import Foundation

enum StorageKey: String {
    case licenseDeviceID = "com.nicevoice.license-device-id"
    case betaEntitlement = "com.nicevoice.beta-entitlement"
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

    private init() {}

    func saveCodable<T: Codable>(_ value: T, for key: StorageKey) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else {
            throw StorageError.encodingFailed
        }
        defaults.set(data, forKey: key.rawValue)
    }

    func loadCodable<T: Codable>(for key: StorageKey) throws -> T {
        guard let data = defaults.data(forKey: key.rawValue) else {
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
        defaults.removeObject(forKey: key.rawValue)
    }
}
