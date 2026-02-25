import Foundation

@Observable
final class LicenseManager {
    static let shared = LicenseManager()

    private(set) var currentPlan: Plan = .free
    private(set) var subscriptionStatus: SubscriptionStatus = .none
    private(set) var licenseInfo: LicenseInfo?
    private(set) var isInitialized = false

    private let trialDurationDays = 7
    private let offlineGracePeriodDays = 7

    private var trialEndDate: Date {
        let firstLaunch = LocalStorage.shared.getFirstLaunchDate()
        return Calendar.current.date(byAdding: .day, value: trialDurationDays, to: firstLaunch) ?? firstLaunch
    }

    var isTrialActive: Bool {
        Date() < trialEndDate && !hasEverSubscribed
    }

    var trialDaysRemaining: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: trialEndDate)
        return max(0, components.day ?? 0)
    }

    var effectivePlan: Plan {
        if subscriptionStatus.isActive {
            return currentPlan
        }
        if isTrialActive {
            return .plus
        }
        return .free
    }

    var canUseBatchTranscription: Bool {
        effectivePlan == .pro
    }

    var dictionaryLimit: Int? {
        effectivePlan == .free ? 10 : nil
    }

    var historyRetentionDays: Int? {
        effectivePlan == .free ? 7 : nil
    }

    var monthlyCredits: Int {
        effectivePlan == .free ? 300 : Int.max
    }

    private var hasEverSubscribed: Bool {
        licenseInfo?.subscriptionId != nil
    }

    private init() {}

    func initialize() async {
        loadFromStorage()

        if shouldVerifyOnline() {
            do {
                try await verifyLicense()
            } catch {
                debugLog("⚠️ License verification failed: \(error)")
            }
        }

        isInitialized = true
        debugLog("✅ LicenseManager initialized: plan=\(effectivePlan), trial=\(isTrialActive)")
    }

    private func loadFromStorage() {
        if let info: LicenseInfo = try? LocalStorage.shared.loadCodable(for: .licenseInfo) {
            licenseInfo = info
            currentPlan = info.plan
            subscriptionStatus = info.status

            if !isLicenseWithinGracePeriod(info) {
                currentPlan = .free
                subscriptionStatus = .none
                debugLog("⚠️ License expired (offline grace period exceeded)")
            }
        }
    }

    private func isLicenseWithinGracePeriod(_ info: LicenseInfo) -> Bool {
        let gracePeriodEnd = Calendar.current.date(
            byAdding: .day,
            value: offlineGracePeriodDays,
            to: info.lastVerified
        ) ?? info.lastVerified

        return Date() < gracePeriodEnd
    }

    private func shouldVerifyOnline() -> Bool {
        guard let info = licenseInfo else { return false }

        let lastVerified = info.lastVerified
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        return lastVerified < oneDayAgo
    }

    func verifyLicense() async throws {
        let response = try await StripeService.shared.verifyLicense()

        let plan = Plan(rawValue: response.plan) ?? .free
        let status = SubscriptionStatus(rawValue: response.status) ?? .none

        let newInfo = LicenseInfo(
            customerId: response.customerId ?? licenseInfo?.customerId ?? "",
            subscriptionId: response.subscriptionId,
            plan: plan,
            status: status,
            currentPeriodEnd: response.currentPeriodEnd,
            trialEnd: response.trialEnd,
            lastVerified: Date()
        )

        try LocalStorage.shared.saveCodable(newInfo, for: .licenseInfo)

        await MainActor.run {
            self.licenseInfo = newInfo
            self.currentPlan = plan
            self.subscriptionStatus = status
        }

        debugLog("✅ License verified: plan=\(plan), status=\(status)")
    }

    func handleCheckoutSuccess(sessionId: String) async throws {
        try await refreshLicenseAndNotify()
    }

    func handlePortalReturn() async throws {
        try await refreshLicenseAndNotify()
    }

    private func refreshLicenseAndNotify() async throws {
        try await verifyLicense()

        await MainActor.run {
            NotificationCenter.default.post(name: .licenseDidChange, object: nil)
        }
    }

    func openPricingPage() {
        StripeService.shared.openPricingPage()
    }

    func manageSubscription() async throws {
        try await StripeService.shared.openCustomerPortal()
    }

    func checkTrialEligibility() -> Bool {
        !hasEverSubscribed && trialDaysRemaining > 0
    }
}

extension Notification.Name {
    static let licenseDidChange = Notification.Name("licenseDidChange")
}
