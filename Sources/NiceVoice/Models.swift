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
    var customFillers: [String] = []

    var addPunctuation: Bool = true
    var removeRepetition: Bool = true

    var useSmartFillerDetection: Bool = false
    var ambiguousFillers: Set<String> = [
        "あの", "その", "ちょっと",
        "なんか", "まあ", "まぁ",
        "こう", "ほら",
        "やっぱり", "やっぱ"
    ]

    var allEnabledFillers: [String] {
        var fillers = Array(enabledPresets)
        fillers.append(contentsOf: customFillers)
        return fillers.sorted { $0.count > $1.count }
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
