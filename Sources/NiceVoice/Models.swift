import Foundation

struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let audioPath: String?

    init(text: String, timestamp: Date, audioPath: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.audioPath = audioPath
    }

    init(id: UUID, text: String, timestamp: Date, audioPath: String? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.audioPath = audioPath
    }

    var hasAudio: Bool {
        guard let path = audioPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

struct UsageStats: Codable {
    var totalConversions: Int = 0
    var totalCharacters: Int = 0
    var totalTokensUsed: Int = 0
    var todayConversions: Int = 0
    var todayCharacters: Int = 0
    var lastResetDate: Date = Date()

    mutating func resetTodayIfNeeded() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(lastResetDate) {
            todayConversions = 0
            todayCharacters = 0
            lastResetDate = Date()
        }
    }

    mutating func recordConversion(characters: Int, tokens: Int) {
        resetTodayIfNeeded()
        totalConversions += 1
        totalCharacters += characters
        totalTokensUsed += tokens
        todayConversions += 1
        todayCharacters += characters
    }
}

struct FillerSettings: Codable {
    var removeFillers: Bool = true
    var enabledPresets: Set<String> = [
        "えー", "えぅ", "えぇ",
        "あー", "あぁ",
        "うーん"
    ]

    var addPunctuation: Bool = true
    var removeRepetition: Bool = true

    var allEnabledFillers: [String] {
        enabledPresets.sorted { $0.count > $1.count }
    }
}

struct LocalServerEndpoint: Equatable {
    let port: Int
    let wsEndpoint: String
    let healthEndpoint: String
}

enum TranscriptionEngine: String, CaseIterable, Codable {
    case speechAnalyzer
    case voxtralLocal
    case qwen3ASR

    static let defaultEngine: TranscriptionEngine = .voxtralLocal

    var isDeveloperOnly: Bool {
        switch self {
        case .qwen3ASR:
            return true
        case .speechAnalyzer, .voxtralLocal:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .speechAnalyzer: return "Apple SpeechAnalyzer"
        case .voxtralLocal: return "Voxtral Local"
        case .qwen3ASR: return "Qwen3 ASR"
        }
    }

    var engineDescription: String {
        switch self {
        case .speechAnalyzer: return String(localized: "macOS 内蔵の音声認識。オフラインで動作し、遅延が少ない")
        case .voxtralLocal: return String(localized: "高精度な Voxtral のローカル推論。アプリ内ランタイムで動作")
        case .qwen3ASR: return String(localized: "Qwen3-ASR-1.7B (MLX, ローカル推論)")
        }
    }

    var requiresLocalServer: Bool {
        switch self {
        case .voxtralLocal, .qwen3ASR: return true
        case .speechAnalyzer: return false
        }
    }

    var finalResultTimeoutSeconds: Double {
        switch self {
        case .speechAnalyzer:
            return Constants.Timing.speechAnalyzerFinalResultTimeoutSeconds
        case .voxtralLocal, .qwen3ASR:
            return Constants.Timing.localASRFinalResultTimeoutSeconds
        }
    }

    var finalResultTimeoutMessage: String {
        switch self {
        case .speechAnalyzer:
            return String(localized: "音声認識がタイムアウトしました。もう一度試してください")
        case .voxtralLocal, .qwen3ASR:
            return String(localized: "\(displayName) の文字起こし処理がタイムアウトしました。もう一度試してください")
        }
    }

    var requiresExternalModelDownload: Bool {
        switch self {
        case .qwen3ASR:
            return true
        case .speechAnalyzer, .voxtralLocal:
            return false
        }
    }

    var serverCommandName: String? {
        switch self {
        case .voxtralLocal: return "voxmlx-serve"
        case .qwen3ASR: return "qwen3asr-serve"
        case .speechAnalyzer: return nil
        }
    }

    var localServerModule: String? {
        switch self {
        case .voxtralLocal: return "voxmlx.server"
        case .qwen3ASR: return "qwen3asr.server"
        case .speechAnalyzer: return nil
        }
    }

    var localServerPackagePath: String? {
        switch self {
        case .voxtralLocal: return ""
        case .qwen3ASR: return "qwen3asr"
        case .speechAnalyzer: return nil
        }
    }

    var modelSize: String? {
        switch self {
        case .voxtralLocal: return "2.5 GB"
        case .qwen3ASR: return "1.6 GB"
        case .speechAnalyzer: return nil
        }
    }

    var hfModelName: String? {
        switch self {
        case .voxtralLocal: return Constants.LocalASR.voxtralModel
        case .qwen3ASR: return Constants.LocalASR.qwen3Model
        case .speechAnalyzer: return nil
        }
    }

    var modelDisplayName: String? {
        switch self {
        case .voxtralLocal: return "Voxtral Mini 4B Realtime 2602"
        case .qwen3ASR: return "Qwen3 ASR 1.7B"
        case .speechAnalyzer: return nil
        }
    }

    private var localServerPortStorageKey: String? {
        switch self {
        case .voxtralLocal, .qwen3ASR:
            return "localServerPort.\(rawValue)"
        case .speechAnalyzer:
            return nil
        }
    }

    func makeLocalServerEndpoint(port: Int) -> LocalServerEndpoint? {
        guard requiresLocalServer else { return nil }
        return LocalServerEndpoint(
            port: port,
            wsEndpoint: Constants.LocalASR.wsEndpoint(port: port),
            healthEndpoint: Constants.LocalASR.healthEndpoint(port: port)
        )
    }

    var currentLocalServerEndpoint: LocalServerEndpoint? {
        guard let key = localServerPortStorageKey,
              let storedPort = UserDefaults.standard.object(forKey: key) as? Int else {
            return nil
        }
        return makeLocalServerEndpoint(port: storedPort)
    }

    func persistLocalServerPort(_ port: Int) {
        guard let key = localServerPortStorageKey else { return }
        UserDefaults.standard.set(port, forKey: key)
    }

    static func availableEngines(
        developerToolsEnabled: Bool = AppFeatureFlags.isDeveloperToolsEnabled()
    ) -> [TranscriptionEngine] {
        developerToolsEnabled
            ? allCases
            : allCases.filter { !$0.isDeveloperOnly }
    }

    static func normalized(
        rawValue: String,
        developerToolsEnabled: Bool = AppFeatureFlags.isDeveloperToolsEnabled()
    ) -> TranscriptionEngine {
        let engine = TranscriptionEngine(rawValue: rawValue) ?? defaultEngine
        guard developerToolsEnabled || !engine.isDeveloperOnly else {
            return defaultEngine
        }
        return engine
    }
}

enum TranscriptionLanguageMode: String, CaseIterable, Codable {
    case japaneseEnglish
    case japanese
    case english
    case multilingual

    static let defaultMode: TranscriptionLanguageMode = .japaneseEnglish

    var displayName: String {
        switch self {
        case .japaneseEnglish: return String(localized: "日本語 + English")
        case .japanese: return String(localized: "日本語のみ")
        case .english: return "English only"
        case .multilingual: return String(localized: "多言語")
        }
    }

    var description: String {
        switch self {
        case .japaneseEnglish:
            return String(localized: "既定値。日本語と英語だけを許可して、フランス語などへの誤認識を抑えます")
        case .japanese:
            return String(localized: "日本語の音声入力に固定します")
        case .english:
            return String(localized: "英語の音声入力に固定します")
        case .multilingual:
            return String(localized: "Voxtral が対応する言語を自動判定します")
        }
    }

    var singleLanguageCode: String? {
        switch self {
        case .japanese: return "ja"
        case .english: return "en"
        case .japaneseEnglish, .multilingual: return nil
        }
    }

    var allowedLanguageCodes: [String] {
        switch self {
        case .japaneseEnglish: return ["ja", "en"]
        case .japanese: return ["ja"]
        case .english: return ["en"]
        case .multilingual: return []
        }
    }

    var speechAnalyzerLanguages: [SupportedLanguage] {
        switch self {
        case .japaneseEnglish, .multilingual: return [.japanese, .english]
        case .japanese: return [.japanese]
        case .english: return [.english]
        }
    }

    var defaultSpeechAnalyzerLanguage: SupportedLanguage {
        switch self {
        case .english: return .english
        case .japaneseEnglish, .japanese, .multilingual: return .japanese
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case system
    case ja
    case en

    var displayName: String {
        switch self {
        case .system: return String(localized: "システム設定に従う")
        case .ja: return "日本語"
        case .en: return "English"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: return nil
        case .ja: return Locale(identifier: "ja")
        case .en: return Locale(identifier: "en")
        }
    }

    func apply() {
        if let locale {
            UserDefaults.standard.set([locale.identifier], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

struct BenchmarkSample: Identifiable, Codable {
    let id: UUID
    let name: String
    let audioFileName: String
    let expectedText: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, audioFileName: String, expectedText: String = "", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.audioFileName = audioFileName
        self.expectedText = expectedText
        self.createdAt = createdAt
    }
}

struct BenchmarkResult: Identifiable {
    let id = UUID()
    let sample: BenchmarkSample
    let rawText: String
    let formattedText: String
    let duration: TimeInterval
    let success: Bool
}
