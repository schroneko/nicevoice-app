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
    case voxtral

    var displayName: String {
        switch self {
        case .speechAnalyzer: return "Apple SpeechAnalyzer"
        case .voxtral: return "Voxtral (Mistral AI)"
        }
    }

    var engineDescription: String {
        switch self {
        case .speechAnalyzer: return "macOS 内蔵の音声認識。オフラインで動作し、遅延が少ない"
        case .voxtral: return "Mistral AI のリアルタイム音声認識。API キーが必要"
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

enum Plan: String, Codable, CaseIterable {
    case free
    case plus
    case pro

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro: return "Pro"
        }
    }

    var monthlyPrice: Int {
        switch self {
        case .free: return 0
        case .plus: return 10
        case .pro: return 30
        }
    }

    var yearlyPrice: Int {
        switch self {
        case .free: return 0
        case .plus: return 96
        case .pro: return 300
        }
    }

    var stripePriceIdMonthly: String {
        switch self {
        case .free: return ""
        case .plus: return "price_plus_monthly"
        case .pro: return "price_pro_monthly"
        }
    }

    var stripePriceIdYearly: String {
        switch self {
        case .free: return ""
        case .plus: return "price_plus_yearly"
        case .pro: return "price_pro_yearly"
        }
    }
}

enum SubscriptionStatus: String, Codable {
    case active
    case trialing
    case pastDue
    case canceled
    case unpaid
    case none

    var isActive: Bool {
        switch self {
        case .active, .trialing:
            return true
        case .pastDue, .canceled, .unpaid, .none:
            return false
        }
    }
}

struct LicenseInfo: Codable {
    let customerId: String
    let subscriptionId: String?
    let plan: Plan
    let status: SubscriptionStatus
    let currentPeriodEnd: Date?
    let trialEnd: Date?
    let lastVerified: Date

    var isValid: Bool {
        guard status.isActive else { return false }
        if let periodEnd = currentPeriodEnd {
            return periodEnd > Date()
        }
        return true
    }

    var daysUntilExpiration: Int? {
        guard let periodEnd = currentPeriodEnd else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: periodEnd)
        return components.day
    }
}

struct MonthlyUsage: Codable {
    var creditsUsed: Int = 0
    var periodStart: Date
    var periodEnd: Date

    var isCurrentPeriod: Bool {
        let now = Date()
        return now >= periodStart && now < periodEnd
    }

    init() {
        let now = Date()
        self.periodStart = now
        self.periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now
    }

    init(creditsUsed: Int, periodStart: Date, periodEnd: Date) {
        self.creditsUsed = creditsUsed
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    mutating func resetIfNewPeriod() {
        if !isCurrentPeriod {
            let now = Date()
            self.creditsUsed = 0
            self.periodStart = now
            self.periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now
        }
    }
}
