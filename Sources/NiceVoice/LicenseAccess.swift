import Foundation

struct LicenseCode: Equatable {
    let value: String

    init?(_ input: String) {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
            .uppercased()

        guard normalized.count >= 8 else { return nil }
        self.value = normalized
    }
}

struct BetaEntitlement: Codable, Equatable {
    let token: String
    let activatedAt: Date
    let expiresAt: Date?

    func isActive(now: Date = Date()) -> Bool {
        guard !token.isEmpty else { return false }
        guard let expiresAt else { return true }
        return now < expiresAt
    }
}

enum LicenseActivationState: Equatable {
    case idle
    case activating
    case activated
    case unavailable(String)
    case failed(String)
}

enum LicenseActivationError: LocalizedError, Equatable {
    case invalidCode
    case missingEndpoint
    case rejected(String)
    case badResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "ライセンスコードの形式を確認してください"
        case .missingEndpoint:
            return "ライセンス受付は準備中です"
        case .rejected(let message):
            return message
        case .badResponse:
            return "ライセンスサーバーから正しい応答を受け取れませんでした"
        case .network(let message):
            return message
        }
    }
}

enum LicenseConfiguration {
    private static let endpointURLKey = "NiceVoiceLicenseAPIURL"
    private static let endpointEnvironmentKey = "NICEVOICE_LICENSE_API_URL"

    static func endpointURL(
        in bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let value = environment[endpointEnvironmentKey],
           let url = normalizedURL(value) {
            return url
        }

        let value = bundle.object(forInfoDictionaryKey: endpointURLKey) as? String
        return normalizedURL(value)
    }

    private static func normalizedURL(_ value: String?) -> URL? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}

struct LicenseActivationRequest: Encodable, Equatable {
    let code: String
    let deviceID: String
    let appVersion: String
}

struct LicenseActivationResponse: Decodable, Equatable {
    let betaAccess: Bool
    let entitlementToken: String
    let expiresAt: Date?
}

struct LicenseStatusResponse: Decodable, Equatable {
    let betaAccess: Bool
    let expiresAt: Date?
}

final class LicenseAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func activate(_ requestBody: LicenseActivationRequest) async throws -> BetaEntitlement {
        let url = baseURL.appendingPathComponent("v1/licenses/activate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseActivationError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.badResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw error(for: httpResponse.statusCode, data: data)
        }

        let activationResponse = try decoder.decode(LicenseActivationResponse.self, from: data)
        guard activationResponse.betaAccess, !activationResponse.entitlementToken.isEmpty else {
            throw LicenseActivationError.rejected("このライセンスではベータ機能を有効にできません")
        }

        return BetaEntitlement(
            token: activationResponse.entitlementToken,
            activatedAt: Date(),
            expiresAt: activationResponse.expiresAt
        )
    }

    private func error(for statusCode: Int, data: Data) -> LicenseActivationError {
        if let message = decodeErrorMessage(from: data) {
            return .rejected(message)
        }

        switch statusCode {
        case 409:
            return .rejected("このライセンスコードはすでに使用されています")
        case 401, 403:
            return .rejected("このライセンスコードは利用できません")
        case 404:
            return .rejected("ライセンス受付が見つかりません")
        default:
            return .badResponse
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let message: String?
        }

        guard let response = try? decoder.decode(ErrorResponse.self, from: data) else {
            return nil
        }
        let trimmed = response.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

@Observable
final class LicenseAccessManager {
    static let shared = LicenseAccessManager()

    private let keychain: KeychainStorage
    private let bundle: Bundle
    private let environment: [String: String]

    private(set) var entitlement: BetaEntitlement?
    var state: LicenseActivationState = .idle

    var hasBetaAccess: Bool {
        entitlement?.isActive() == true
    }

    var isLicenseServerConfigured: Bool {
        LicenseConfiguration.endpointURL(in: bundle, environment: environment) != nil
    }

    private init(
        keychain: KeychainStorage = .shared,
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.keychain = keychain
        self.bundle = bundle
        self.environment = environment
        reload()
    }

    func reload() {
        entitlement = loadEntitlement()
        if entitlement?.isActive() == true {
            state = .activated
        } else if isLicenseServerConfigured {
            state = .idle
        } else {
            state = .unavailable("ライセンス受付は準備中です")
        }
    }

    func activate(code input: String) async {
        guard let code = LicenseCode(input) else {
            state = .failed(LicenseActivationError.invalidCode.localizedDescription)
            return
        }

        guard let endpointURL = LicenseConfiguration.endpointURL(in: bundle, environment: environment) else {
            state = .unavailable(LicenseActivationError.missingEndpoint.localizedDescription)
            return
        }

        state = .activating

        do {
            let request = LicenseActivationRequest(
                code: code.value,
                deviceID: deviceID(),
                appVersion: BundleInfo.shortVersion(in: bundle)
            )
            let entitlement = try await LicenseAPIClient(baseURL: endpointURL).activate(request)
            saveEntitlement(entitlement)
            self.entitlement = entitlement
            state = .activated
            NotificationCenter.default.post(name: .authDidChange, object: nil)
        } catch let error as LicenseActivationError {
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func deviceID() -> String {
        if let stored = keychain.loadString(account: StorageKey.licenseDeviceID.rawValue),
           !stored.isEmpty {
            return stored
        }

        let newID = UUID().uuidString
        _ = keychain.saveString(newID, account: StorageKey.licenseDeviceID.rawValue)
        return newID
    }

    private func saveEntitlement(_ entitlement: BetaEntitlement) {
        guard let data = try? JSONEncoder.licenseEncoder.encode(entitlement) else { return }
        _ = keychain.save(data, account: StorageKey.betaEntitlement.rawValue)
    }

    private func loadEntitlement() -> BetaEntitlement? {
        guard let data = keychain.load(account: StorageKey.betaEntitlement.rawValue) else {
            return nil
        }
        return try? JSONDecoder.licenseDecoder.decode(BetaEntitlement.self, from: data)
    }
}

private extension JSONEncoder {
    static var licenseEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var licenseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
