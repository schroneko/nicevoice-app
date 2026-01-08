import Foundation

@Observable
final class UsageTracker {
    static let shared = UsageTracker()

    private(set) var currentUsage: MonthlyUsage

    private let usageKey = "monthlyUsage"

    var creditsRemaining: Int {
        let limit = LicenseManager.shared.monthlyCredits
        if limit == Int.max { return Int.max }
        return max(0, limit - currentUsage.creditsUsed)
    }

    var creditsUsed: Int {
        currentUsage.creditsUsed
    }

    var hasCreditsRemaining: Bool {
        let plan = LicenseManager.shared.effectivePlan
        if plan != .free { return true }
        return creditsRemaining > 0
    }

    var usagePercentage: Double {
        let limit = LicenseManager.shared.monthlyCredits
        if limit == Int.max { return 0 }
        return min(1.0, Double(currentUsage.creditsUsed) / Double(limit))
    }

    var periodEndDate: Date {
        currentUsage.periodEnd
    }

    var daysUntilReset: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: currentUsage.periodEnd)
        return max(0, components.day ?? 0)
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: usageKey),
           var usage = try? JSONDecoder().decode(MonthlyUsage.self, from: data) {
            usage.resetIfNewPeriod()
            self.currentUsage = usage
        } else {
            self.currentUsage = MonthlyUsage()
        }
    }

    func recordUsage(characters: Int) {
        currentUsage.resetIfNewPeriod()
        currentUsage.creditsUsed += characters
        saveUsage()

        debugLog("📊 Usage: \(currentUsage.creditsUsed) credits used")
    }

    func checkAndRecordUsage(characters: Int) -> Bool {
        let plan = LicenseManager.shared.effectivePlan
        if plan != .free {
            recordUsage(characters: characters)
            return true
        }

        let limit = LicenseManager.shared.monthlyCredits
        let projectedUsage = currentUsage.creditsUsed + characters

        if projectedUsage > limit {
            return false
        }

        recordUsage(characters: characters)
        return true
    }

    func resetUsage() {
        currentUsage = MonthlyUsage()
        saveUsage()
    }

    private func saveUsage() {
        if let data = try? JSONEncoder().encode(currentUsage) {
            UserDefaults.standard.set(data, forKey: usageKey)
        }
    }
}
