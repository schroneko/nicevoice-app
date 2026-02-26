import Foundation
import AppKit

enum AuthError: LocalizedError {
    case networkError(Error)
    case serverError(Int, String?)
    case invalidResponse
    case unauthorized
    case deviceMismatch

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "unknown")"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Not authenticated"
        case .deviceMismatch:
            return "This account is already registered to another device"
        }
    }
}

struct AuthMeResponse: Codable {
    let user: AuthUser?
    let isSubscriber: Bool
}

struct AuthUser: Codable {
    let id: String
    let username: String
    let isAdmin: Bool
}

struct VerifyResponse: Codable {
    let isSubscriber: Bool
    let username: String
    let deviceRegistered: Bool
    let error: String?
}

struct DeregisterResponse: Codable {
    let deregistered: Bool
}

final class NukosukuAuthService {
    static let shared = NukosukuAuthService()

    private let baseURL = "https://nukosuku.com/api"

    private init() {}

    func startLogin() {
        guard let loginURL = URL(string: "\(baseURL)/auth/login?platform=nicevoice") else {
            return
        }

        NSWorkspace.shared.open(loginURL)
    }

    func verify(sessionId: String, deviceId: String) async throws -> VerifyResponse {
        return try await post(
            endpoint: "/nicevoice/verify",
            body: ["device_id": deviceId],
            sessionId: sessionId
        )
    }

    func checkSession(sessionId: String) async throws -> AuthMeResponse {
        return try await get(endpoint: "/auth/me", sessionId: sessionId)
    }

    func deregisterDevice(sessionId: String) async throws -> DeregisterResponse {
        return try await delete(endpoint: "/nicevoice/device", sessionId: sessionId)
    }

    private func get<T: Codable>(endpoint: String, sessionId: String) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(sessionId)", forHTTPHeaderField: "Authorization")
        request.setValue("NiceVoice/\((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"))", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        return try await execute(request)
    }

    private func post<T: Codable>(endpoint: String, body: [String: Any], sessionId: String) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionId)", forHTTPHeaderField: "Authorization")
        request.setValue("NiceVoice/\((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"))", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await execute(request)
    }

    private func delete<T: Codable>(endpoint: String, sessionId: String) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(sessionId)", forHTTPHeaderField: "Authorization")
        request.setValue("NiceVoice/\((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"))", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        return try await execute(request)
    }

    private func execute<T: Codable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AuthError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8)
            throw AuthError.serverError(httpResponse.statusCode, errorMessage)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            debugLog("JSON decode error: \(error)")
            throw AuthError.invalidResponse
        }
    }
}
