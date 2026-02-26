import Foundation

@Observable
final class UsageTracker {
    static let shared = UsageTracker()

    private(set) var stats: UsageStats

    private let statsKey = "usageStats"

    var creditsRemaining: Int {
        Int.max
    }

    var creditsUsed: Int {
        stats.totalCharacters
    }

    var hasCreditsRemaining: Bool {
        true
    }

    var usagePercentage: Double {
        0
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: statsKey),
           var stats = try? JSONDecoder().decode(UsageStats.self, from: data) {
            stats.resetTodayIfNeeded()
            self.stats = stats
        } else {
            self.stats = UsageStats()
        }
    }

    func recordUsage(characters: Int) {
        stats.recordConversion(characters: characters, tokens: 0)
        saveStats()

        debugLog("Usage: \(stats.totalCharacters) total characters")
    }

    func checkAndRecordUsage(characters: Int) -> Bool {
        recordUsage(characters: characters)
        return true
    }

    func resetUsage() {
        stats = UsageStats()
        saveStats()
    }

    private func saveStats() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
    }
}
