import AppKit
import Combine
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()

    @Published private(set) var isConfigured = false
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false
    @Published var automaticallyDownloadsUpdates = false

    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    #endif

    private init(bundle: Bundle = .main) {
        #if canImport(Sparkle)
        if AppUpdateConfiguration.isConfigured(in: bundle) {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController = controller
            isConfigured = true
            syncState(from: controller.updater)
            canCheckObservation = controller.updater.observe(
                \.canCheckForUpdates,
                options: [.initial, .new]
            ) { [weak self] updater, _ in
                Task { @MainActor in
                    self?.canCheckForUpdates = updater.canCheckForUpdates
                }
            }
            return
        }

        updaterController = nil
        #endif

        isConfigured = false
        canCheckForUpdates = false
    }

    var primaryActionTitle: String {
        "アップデートを確認…"
    }

    var statusDescription: String {
        if isConfigured {
            return "現在のバージョン \(BundleInfo.shortVersion()) (\(BundleInfo.buildNumber()))"
        }
        return "自動更新は未設定です"
    }

    var canPerformPrimaryAction: Bool {
        isConfigured && canCheckForUpdates
    }

    func performPrimaryAction() {
        #if canImport(Sparkle)
        if isConfigured, let updaterController {
            updaterController.checkForUpdates(nil)
            return
        }
        #endif
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        #if canImport(Sparkle)
        guard isConfigured, let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = value
        syncState(from: updater)
        #endif
    }

    func setAutomaticallyDownloadsUpdates(_ value: Bool) {
        #if canImport(Sparkle)
        guard isConfigured, let updater = updaterController?.updater else { return }
        updater.automaticallyDownloadsUpdates = value
        syncState(from: updater)
        #endif
    }

    #if canImport(Sparkle)
    private func syncState(from updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }
    #endif
}
