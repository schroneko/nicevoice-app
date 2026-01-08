import Foundation
import AppKit

enum StripeError: LocalizedError {
    case networkError(Error)
    case serverError(Int, String?)
    case invalidResponse
    case noCheckoutURL

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .serverError(let code, let message):
            if let message = message {
                return "サーバーエラー (\(code)): \(message)"
            }
            return "サーバーエラー: \(code)"
        case .invalidResponse:
            return "サーバーからの応答が不正です"
        case .noCheckoutURL:
            return "チェックアウト URL を取得できませんでした"
        }
    }
}

struct CheckoutSessionResponse: Codable {
    let url: String
    let sessionId: String
}

struct CustomerPortalResponse: Codable {
    let url: String
}

struct LicenseVerificationResponse: Codable {
    let valid: Bool
    let plan: String
    let status: String
    let currentPeriodEnd: Date?
    let trialEnd: Date?
    let customerId: String?
    let subscriptionId: String?

    enum CodingKeys: String, CodingKey {
        case valid, plan, status
        case currentPeriodEnd = "current_period_end"
        case trialEnd = "trial_end"
        case customerId = "customer_id"
        case subscriptionId = "subscription_id"
    }
}

enum URLSchemeResult {
    case checkoutSuccess(sessionId: String)
    case checkoutCanceled
    case portalReturn
}

final class StripeService {
    static let shared = StripeService()

    private let baseURL = "https://nicevoice.app/api"

    private init() {}

    func createCheckoutSession(
        plan: Plan,
        interval: BillingInterval,
        customerId: String?
    ) async throws -> CheckoutSessionResponse {
        let deviceId = KeychainService.shared.getOrCreateDeviceId()

        var params: [String: Any] = [
            "plan": plan.rawValue,
            "interval": interval.rawValue,
            "device_id": deviceId
        ]

        if let customerId = customerId {
            params["customer_id"] = customerId
        }

        let response: CheckoutSessionResponse = try await post(
            endpoint: "/checkout",
            body: params
        )

        return response
    }

    func createCustomerPortalSession(customerId: String) async throws -> CustomerPortalResponse {
        let params: [String: Any] = [
            "customer_id": customerId
        ]

        let response: CustomerPortalResponse = try await post(
            endpoint: "/portal",
            body: params
        )

        return response
    }

    func verifyLicense() async throws -> LicenseVerificationResponse {
        let deviceId = KeychainService.shared.getOrCreateDeviceId()

        guard let licenseInfo: LicenseInfo = try? KeychainService.shared.loadCodable(for: .licenseInfo),
              !licenseInfo.customerId.isEmpty else {
            return LicenseVerificationResponse(
                valid: false,
                plan: Plan.free.rawValue,
                status: SubscriptionStatus.none.rawValue,
                currentPeriodEnd: nil,
                trialEnd: nil,
                customerId: nil,
                subscriptionId: nil
            )
        }

        let params: [String: Any] = [
            "customer_id": licenseInfo.customerId,
            "device_id": deviceId
        ]

        let response: LicenseVerificationResponse = try await post(
            endpoint: "/verify",
            body: params
        )

        return response
    }

    func openCheckout(plan: Plan, interval: BillingInterval = .monthly) async throws {
        let customerId = (try? KeychainService.shared.loadCodable(for: .licenseInfo) as LicenseInfo)?.customerId

        let response = try await createCheckoutSession(
            plan: plan,
            interval: interval,
            customerId: customerId
        )

        guard let url = URL(string: response.url) else {
            throw StripeError.noCheckoutURL
        }

        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    func openCustomerPortal() async throws {
        guard let licenseInfo: LicenseInfo = try? KeychainService.shared.loadCodable(for: .licenseInfo),
              !licenseInfo.customerId.isEmpty else {
            debugLog("⚠️ No customer ID for portal")
            return
        }

        let response = try await createCustomerPortalSession(customerId: licenseInfo.customerId)

        guard let url = URL(string: response.url) else {
            throw StripeError.invalidResponse
        }

        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    func handleURLScheme(_ url: URL) -> URLSchemeResult? {
        guard url.scheme == "nicevoice" else { return nil }

        let path = url.host ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        switch path {
        case "checkout":
            let action = url.pathComponents.last ?? ""
            if action == "success" {
                if let sessionId = queryItems.first(where: { $0.name == "session_id" })?.value {
                    return .checkoutSuccess(sessionId: sessionId)
                }
            } else if action == "cancel" {
                return .checkoutCanceled
            }

        case "portal":
            return .portalReturn

        default:
            break
        }

        return nil
    }

    private func post<T: Codable>(endpoint: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw StripeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NiceVoice/\(Bundle.main.appVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8)
            throw StripeError.serverError(httpResponse.statusCode, errorMessage)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            debugLog("❌ JSON decode error: \(error)")
            throw StripeError.invalidResponse
        }
    }
}

enum BillingInterval: String {
    case monthly
    case yearly
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
