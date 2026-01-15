import Foundation

final class FillerDetectionService {
    private static let legacyConfigDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NiceVoice")
    }()

    private static let legacyConfigPath: URL = {
        legacyConfigDirectory.appendingPathComponent("config.json")
    }()

    private struct LegacyConfig: Codable {
        var anthropicAPIKey: String?
    }

    static func getAPIKey() -> String? {
        migrateFromLegacyConfigIfNeeded()
        return try? KeychainService.shared.loadString(for: .anthropicAPIKey)
    }

    static func setAPIKey(_ key: String) {
        do {
            try KeychainService.shared.saveString(key, for: .anthropicAPIKey)
            debugLog("✅ Anthropic API key saved to Keychain")
        } catch {
            debugLog("❌ Failed to save API key: \(error)")
        }
    }

    static func hasAPIKey() -> Bool {
        KeychainService.shared.exists(for: .anthropicAPIKey)
    }

    static func deleteAPIKey() {
        try? KeychainService.shared.delete(for: .anthropicAPIKey)
    }

    private static func migrateFromLegacyConfigIfNeeded() {
        guard !KeychainService.shared.exists(for: .anthropicAPIKey) else { return }

        guard let data = try? Data(contentsOf: legacyConfigPath),
              let config = try? JSONDecoder().decode(LegacyConfig.self, from: data),
              let key = config.anthropicAPIKey, !key.isEmpty else {
            return
        }

        do {
            try KeychainService.shared.saveString(key, for: .anthropicAPIKey)
            try FileManager.default.removeItem(at: legacyConfigPath)
            debugLog("✅ Migrated API key from config.json to Keychain")
        } catch {
            debugLog("⚠️ Migration failed: \(error)")
        }
    }

    static func setupAPIKey(from devVarsPath: String) {
        guard let content = try? String(contentsOfFile: devVarsPath, encoding: .utf8) else {
            debugLog("⚠️ .dev.vars not found at \(devVarsPath)")
            return
        }

        guard let key = content.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("ANTHROPIC_API_KEY=") })?
            .components(separatedBy: "=")
            .dropFirst()
            .joined(separator: "="),
            !key.isEmpty else {
            debugLog("⚠️ ANTHROPIC_API_KEY not found in .dev.vars")
            return
        }

        setAPIKey(key)
    }

    static func detectFillers(in text: String, ambiguousWords: Set<String>) async -> [String] {
        guard let apiKey = getAPIKey(), !apiKey.isEmpty else {
            debugLog("⚠️ Anthropic API key not configured")
            return []
        }

        let wordsInText = ambiguousWords.filter { text.contains($0) }
        guard !wordsInText.isEmpty else {
            return []
        }

        let targetWords = wordsInText.sorted().joined(separator: "、")
        let prompt = """
        以下の単語がフィラー（言い淀み）かどうか判定してください。

        【検査対象】
        \(targetWords)

        【判定基準】
        - フィラー: 話し言葉で無意識に挿入される言葉
          例: 「登録していて、あの支払いも」の「あの」（特定の対象を指していない）
          例: 「なんか、えーと」「あの、その」
        - 非フィラー: 特定の対象を指す指示詞として使われている
          例: 「あの人が来た」「その本を読んだ」「なんかいい感じ」

        【ヒント】
        - 読点（、）の直後に来る「あの」「その」はフィラーの可能性が高い
        - 「あの＋名詞」の形でも、文脈上特定の対象を指していなければフィラー

        【入力】
        \(text)

        【出力形式】
        検査対象の中でフィラーと判定したものだけをカンマ区切りで出力。説明不要。
        フィラーがなければ: なし
        """

        do {
            let fillers = try await callClaudeAPI(prompt: prompt, apiKey: apiKey)
            return fillers.filter { wordsInText.contains($0) }
        } catch {
            debugLog("❌ Filler detection error: \(error)")
            return []
        }
    }

    private static func callClaudeAPI(prompt: String, apiKey: String) async throws -> [String] {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 5

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 100,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "FillerDetection", code: 1, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw NSError(domain: "FillerDetection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "なし" {
            return []
        }

        let fillers = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        debugLog("🔍 Smart filler detection: \(fillers)")
        return fillers
    }
}
