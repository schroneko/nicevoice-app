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

struct DictionaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var reading: String
    var writing: String
    var isEnabled: Bool = true

    init(id: UUID = UUID(), reading: String, writing: String, isEnabled: Bool = true) {
        self.id = id
        self.reading = reading
        self.writing = writing
        self.isEnabled = isEnabled
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

enum TranscriptionEngine: String, CaseIterable, Codable {
    case speechAnalyzer
    case voxtralLocal
    case qwen3ASR
    case deepgram

    var displayName: String {
        switch self {
        case .speechAnalyzer: return "Apple SpeechAnalyzer"
        case .voxtralLocal: return "Voxtral Local (voxmlx)"
        case .qwen3ASR: return "Qwen3 ASR"
        case .deepgram: return "Deepgram Nova-3"
        }
    }

    var engineDescription: String {
        switch self {
        case .speechAnalyzer: return String(localized: "macOS 内蔵の音声認識。オフラインで動作し、遅延が少ない")
        case .voxtralLocal: return String(localized: "voxmlx-serve によるローカル推論。サーバーの起動が必要")
        case .qwen3ASR: return String(localized: "Qwen3-ASR-1.7B (MLX, ローカル推論)")
        case .deepgram: return String(localized: "Deepgram Nova-3 (クラウド API, 高精度)")
        }
    }

    var requiresLocalServer: Bool {
        switch self {
        case .voxtralLocal, .qwen3ASR: return true
        case .speechAnalyzer, .deepgram: return false
        }
    }

    var requiresApiKey: Bool {
        switch self {
        case .deepgram: return true
        case .speechAnalyzer, .voxtralLocal, .qwen3ASR: return false
        }
    }

    var serverCommandName: String? {
        switch self {
        case .voxtralLocal: return "voxmlx-serve"
        case .qwen3ASR: return "qwen3asr-serve"
        case .speechAnalyzer, .deepgram: return nil
        }
    }

    var modelSize: String? {
        switch self {
        case .voxtralLocal: return "2.5 GB"
        case .qwen3ASR: return "1.6 GB"
        case .speechAnalyzer, .deepgram: return nil
        }
    }

    var hfModelName: String? {
        switch self {
        case .voxtralLocal: return Constants.VoxtralLocal.defaultModel
        case .qwen3ASR: return Constants.Qwen3ASR.defaultModel
        case .speechAnalyzer, .deepgram: return nil
        }
    }

    var modelDisplayName: String? {
        switch self {
        case .voxtralLocal: return "Voxtral Mini 4B Realtime 2602"
        case .qwen3ASR: return "Qwen3 ASR 1.7B"
        case .speechAnalyzer, .deepgram: return nil
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

