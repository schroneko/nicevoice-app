import SwiftUI
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices
import Speech
import os.log

private let logger = Logger(subsystem: "com.nicevoice.app", category: "general")

func isDebuggerAttached() -> Bool {
    #if DEBUG
    return false
    #else
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride
    let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    guard result == 0 else { return false }
    return (info.kp_proc.p_flag & P_TRACED) != 0
    #endif
}

extension Notification.Name {
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
}

@main
struct NiceVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @StateObject private var updateManager = AppUpdateManager.shared

    private var resolvedLocale: Locale {
        let lang = AppLanguage(rawValue: appLanguageRaw) ?? .system
        return lang.locale ?? Locale.current
    }

    var body: some Scene {
        Window("Nice Voice", id: "main") {
            MainWindowView(appState: appDelegate.appState)
                .environment(\.locale, resolvedLocale)
                .id(appLanguageRaw)
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(updateManager.primaryActionTitle) {
                    updateManager.performPrimaryAction()
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
            }
        }
    }
}

private let logDirectory: URL = {
    let logsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NiceVoice")
    try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    return logsDir
}()

private let logFilePath: String = {
    logDirectory.appendingPathComponent("debug.log").path
}()

private let maxLogFileSize: UInt64 = 5 * 1024 * 1024
private let maxLogBackups = 3

private func rotateLogIfNeeded() {
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: logFilePath),
          let fileSize = attrs[.size] as? UInt64,
          fileSize >= maxLogFileSize else {
        return
    }

    for i in stride(from: maxLogBackups - 1, through: 0, by: -1) {
        let oldPath = i == 0 ? logFilePath : "\(logFilePath).\(i)"
        let newPath = "\(logFilePath).\(i + 1)"

        if i == maxLogBackups - 1 {
            try? fm.removeItem(atPath: newPath)
        }
        if fm.fileExists(atPath: oldPath) {
            try? fm.moveItem(atPath: oldPath, toPath: newPath)
        }
    }
}

func debugLog(_ message: String) {
    #if DEBUG
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    print(logMessage, terminator: "")
    logger.debug("\(message, privacy: .private)")

    rotateLogIfNeeded()

    guard let logData = logMessage.data(using: .utf8) else { return }
    if let handle = FileHandle(forWritingAtPath: logFilePath) {
        handle.seekToEndOfFile()
        handle.write(logData)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFilePath, contents: logData)
    }
    #endif
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem?

    @AppStorage("showInMenuBar") var showInMenuBar = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("✅ NiceVoice started")
        checkAccessibilityPermission()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarSettingChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordingStateChanged),
            name: .recordingStateChanged,
            object: nil
        )
    }

    @objc private func recordingStateChanged() {
        updateStatusItemIcon()
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        debugLog("🔐 Accessibility permission: \(trusted)")
    }

    private func setupStatusItem() {
        guard showInMenuBar else {
            statusItem = nil
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Nice Voice")
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        updateStatusItemIcon()
    }

    func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let iconName = appState.isRecording ? "mic.fill" : "mic"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Nice Voice")
        button.contentTintColor = appState.isRecording ? .systemRed : nil
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            openMainWindow()
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Nice Voice" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            if let url = URL(string: "nicevoice://main") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: appState.statusMessage, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: String(localized: "Nice Voice を開く"), action: #selector(openMainWindowAction), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = .command
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: String(localized: "終了"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindowAction() {
        openMainWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func menuBarSettingChanged() {
        let newValue = UserDefaults.standard.bool(forKey: "showInMenuBar")
        if newValue && statusItem == nil {
            setupStatusItem()
        } else if !newValue && statusItem != nil {
            NSStatusBar.system.removeStatusItem(statusItem!)
            statusItem = nil
        }
    }
}

@Observable
final class AppState {
    var isRecording = false
    var currentTranscription = ""
    private var latestRawTranscription = ""
    var isReady = false
    var statusMessage = String(localized: "初期化中...")
    var errorMessage: String?
    var history: [TranscriptionRecord] = []
    var audioLevels: [Float] = Array(repeating: 0, count: 20)
    var recordingStartDate: Date?
    var isShowingFinalizationPanel: Bool {
        waitingForFinalResult && errorMessage == nil && shouldShowFloatingPanelForCurrentRecording
    }
    var floatingPanelPreviewText: String {
        let preview = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty {
            return preview
        }
        return latestRawTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var usesExpandedFloatingPanel: Bool {
        errorMessage != nil || isShowingFinalizationPanel
    }

    @ObservationIgnored
    @AppStorage("shortcutKey") var shortcutKeyRaw = ShortcutKey.fn.rawValue

    @ObservationIgnored
    @AppStorage("customShortcut") var customShortcutRaw = CustomShortcut.defaultValue.rawValue

    var shortcutKey: ShortcutKey {
        get { ShortcutKey(rawValue: shortcutKeyRaw) ?? .fn }
        set {
            updateShortcutSelection(newValue)
        }
    }

    var customShortcut: CustomShortcut {
        get { CustomShortcut(rawValue: customShortcutRaw) ?? .defaultValue }
        set {
            customShortcutRaw = newValue.rawValue
            keyMonitor?.updateShortcut(shortcutKey: shortcutKey, customShortcut: newValue)
        }
    }

    var shortcutDisplayName: String {
        shortcutKey == .custom ? customShortcut.displayName : shortcutKey.displayName
    }

    var shortcutUsageDescription: String {
        shortcutKey.usageDescription(customShortcut: customShortcut)
    }

    var usageStats: UsageStats = UsageStats()
    var dictionaryEntries: [DictionaryEntry] = []
    var fillerSettings: FillerSettings = FillerSettings()
    var shortcutMonitoringIssue: ShortcutMonitoringIssue?

    @ObservationIgnored
    @AppStorage("transcriptionEngine") var transcriptionEngineRaw = TranscriptionEngine.defaultEngine.rawValue

    var transcriptionEngine: TranscriptionEngine {
        get { TranscriptionEngine.normalized(rawValue: transcriptionEngineRaw) }
        set {
            transcriptionEngineRaw = TranscriptionEngine.normalized(rawValue: newValue.rawValue).rawValue
        }
    }

    private var speechAnalyzerService: Any?
    private var localASRService: LocalASRService?
    private var deepgramService: DeepgramService?
    private(set) var localServerManager: LocalServerManager?
    var localServerStatus: LocalServerStatus = .stopped
    private(set) var modelDownloadManagers: [TranscriptionEngine: ModelDownloadManager] = [:]
    var modelDownloadStatuses: [TranscriptionEngine: ModelDownloadStatus] = [:]
    var modelDownloadStatus: ModelDownloadStatus {
        modelDownloadStatuses[transcriptionEngine] ?? .downloaded
    }
    private(set) var keyMonitor: KeyMonitor?
    private var floatingPanel: FloatingPanel?
    private var waitingForFinalResult = false
    private var finalResultTimer: DispatchWorkItem?
    private var provisionalFinalizationTimer: DispatchWorkItem?
    private var speakerCheckTimer: Timer?
    private var isEnrolledSpeakerActive = true
    private var isAwaitingLongPressConfirmation = false
    private var hasDeferredLocalCapture = false
    private var shouldShowFloatingPanelForCurrentRecording = false
    private var capturedTextElement: AXUIElement?
    private var insertionPointLocation: Int = 0
    private var inlinePreviewLength: Int = 0
    private var inlinePreviewActive: Bool = false

    private enum UserDefaultsKey {
        static let usageStats = "usageStats"
        static let dictionary = "dictionaryEntries"
        static let fillerSettings = "fillerSettings"
        static let history = "transcriptionHistory"
    }

    init() {
        loadUsageStats()
        loadDictionary()
        loadFillerSettings()
        loadHistory()
        normalizeTranscriptionEngineSelection()
        setupServices()
        initializeSpeakerVerificationIfNeeded()
    }

    private func normalizeTranscriptionEngineSelection() {
        let normalizedEngine = TranscriptionEngine.normalized(rawValue: transcriptionEngineRaw)
        guard normalizedEngine.rawValue != transcriptionEngineRaw else { return }
        debugLog("Switching transcription engine from \(transcriptionEngineRaw) to \(normalizedEngine.rawValue)")
        transcriptionEngineRaw = normalizedEngine.rawValue
    }

    private func initializeSpeakerVerificationIfNeeded() {
        guard SpeakerVerificationService.shared.isEnrolled else { return }
        Task {
            do {
                try await SpeakerVerificationService.shared.initialize()
                debugLog("SpeakerVerification: auto-initialized at startup")
            } catch {
                debugLog("SpeakerVerification: auto-init failed: \(error)")
            }
        }
    }

    private func setupServices() {
        normalizeTranscriptionEngineSelection()
        setupTranscriptionService()

        if #available(macOS 26.0, *) {
            speechAnalyzerService = SpeechAnalyzerService(
                onTranscription: { [weak self] text, isFinal in
                    debugLog("📥 onTranscription called: isFinal=\(isFinal), len=\(text.count), text='\(text.prefix(50))'")
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.latestRawTranscription = text
                        self.currentTranscription = self.displayTextForPreview(text, isFinal: isFinal)
                        if self.isEnrolledSpeakerActive {
                            self.updateInlinePreview(self.currentTranscription)
                        }
                    }
                },
                onFinalCompletion: { [weak self] text in
                    debugLog("📥 onFinalCompletion called: len=\(text.count), text='\(text.prefix(50))'")
                    self?.handleFinalResult(text)
                },
                onError: { [weak self] error in
                    debugLog("❌ SpeechAnalyzer error: \(error)")
                    DispatchQueue.main.async {
                        self?.handleServiceError(error)
                    }
                },
                onStatusChange: { [weak self] status in
                    DispatchQueue.main.async {
                        self?.statusMessage = status
                    }
                },
                onAudioLevel: { [weak self] level in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.audioLevels.removeFirst()
                        self.audioLevels.append(level)
                    }
                },
                onLanguageDetected: { [weak self] language in
                    DispatchQueue.main.async {
                        debugLog("🌍 Language detected: \(language.displayName)")
                        self?.statusMessage = String(localized: "検出: \(language.displayName)")
                    }
                },
                onCaptureStarted: { [weak self] in
                    self?.handleCaptureStarted()
                }
            )
        }

        keyMonitor = KeyMonitor(
            shortcutKey: shortcutKey,
            customShortcut: customShortcut,
            onPressBegan: { [weak self] in self?.beginLongPressRecordingPreflight() },
            onPressCancelled: { [weak self] in self?.cancelPendingLongPressRecording() },
            onMonitoringIssueChanged: { [weak self] issue in self?.handleShortcutMonitoringIssue(issue) },
            onKeyDown: { [weak self] in self?.startRecording() },
            onKeyUp: { [weak self] in self?.stopRecording() }
        )

        floatingPanel = FloatingPanel(appState: self)

        Task {
            await requestPermissions()
        }
    }

    func setupTranscriptionService() {
        normalizeTranscriptionEngineSelection()
        debugLog("setupTranscriptionService: engine=\(transcriptionEngine.rawValue)")
        localASRService?.setWarmCaptureEnabled(false)
        localASRService?.stop()
        localASRService = nil
        deepgramService = nil
        localServerManager?.stop()
        localServerManager = nil
        localServerStatus = .stopped
        for engine in TranscriptionEngine.allCases where engine.requiresLocalServer {
            if modelDownloadStatuses[engine] == nil {
                modelDownloadStatuses[engine] = engine.requiresExternalModelDownload ? .notDownloaded : .downloaded
            }
        }

        if transcriptionEngine == .deepgram {
            guard let apiKey = KeychainStorage.shared.loadString(account: StorageKey.deepgramApiKey.rawValue),
                  !apiKey.isEmpty else {
                statusMessage = String(localized: "Deepgram API キーが未設定です")
                debugLog("Deepgram: no API key configured")
                return
            }

            deepgramService = DeepgramService(
                apiKey: apiKey,
                onTranscription: { [weak self] text, isFinal in
                    debugLog("[Deepgram] onTranscription: isFinal=\(isFinal), len=\(text.count)")
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.latestRawTranscription = text
                        self.currentTranscription = self.displayTextForPreview(text, isFinal: isFinal)
                        if self.isEnrolledSpeakerActive {
                            self.updateInlinePreview(self.currentTranscription)
                        }
                    }
                },
                onFinalCompletion: { [weak self] text in
                    debugLog("[Deepgram] onFinalCompletion: len=\(text.count)")
                    self?.handleFinalResult(text)
                },
                onError: { [weak self] error in
                    debugLog("Deepgram error: \(error)")
                    DispatchQueue.main.async {
                        self?.handleServiceError(error)
                    }
                },
                onStatusChange: { [weak self] status in
                    DispatchQueue.main.async {
                        self?.statusMessage = status
                    }
                },
                onAudioLevel: { [weak self] level in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.audioLevels.removeFirst()
                        self.audioLevels.append(level)
                    }
                },
                onCaptureStarted: { [weak self] in
                    self?.handleCaptureStarted()
                }
            )
            isReady = true
            statusMessage = String(localized: "準備完了 (Deepgram) - \(shortcutUsageDescription)")
            debugLog("Using Deepgram Nova-3")
            return
        }

        if transcriptionEngine == .voxtralLocal || transcriptionEngine == .qwen3ASR {
            let sampleRate: Double
            let serverCommand: String
            let serverModule: String
            let serverPackagePath: String
            let modelName: String
            let httpRequestTimeout: Double
            let startupTimeout: Double
            let healthPollInterval: Double
            let uvxSearchPaths: [String]
            let engineLabel: String
            let endpointFactory: (Int) -> LocalServerEndpoint

            switch transcriptionEngine {
            case .voxtralLocal:
                sampleRate = Constants.VoxtralLocal.sampleRate
                serverCommand = "voxmlx-serve"
                serverModule = "voxmlx.server"
                serverPackagePath = ""
                modelName = Constants.VoxtralLocal.defaultModel
                httpRequestTimeout = Constants.VoxtralLocal.httpRequestTimeoutSeconds
                startupTimeout = Constants.VoxtralLocal.serverStartupTimeoutSeconds
                healthPollInterval = Constants.VoxtralLocal.healthPollIntervalSeconds
                uvxSearchPaths = Constants.VoxtralLocal.uvxSearchPaths
                engineLabel = "Voxtral Local"
                endpointFactory = { port in
                    LocalServerEndpoint(
                        port: port,
                        wsEndpoint: Constants.VoxtralLocal.wsEndpoint(port: port),
                        healthEndpoint: Constants.VoxtralLocal.healthEndpoint(port: port)
                    )
                }
            case .qwen3ASR:
                sampleRate = Constants.Qwen3ASR.sampleRate
                serverCommand = "qwen3asr-serve"
                serverModule = "qwen3asr.server"
                serverPackagePath = "qwen3asr"
                modelName = Constants.Qwen3ASR.defaultModel
                httpRequestTimeout = Constants.Qwen3ASR.httpRequestTimeoutSeconds
                startupTimeout = Constants.Qwen3ASR.serverStartupTimeoutSeconds
                healthPollInterval = Constants.Qwen3ASR.healthPollIntervalSeconds
                uvxSearchPaths = Constants.Qwen3ASR.uvxSearchPaths
                engineLabel = "Qwen3 ASR"
                endpointFactory = { port in
                    LocalServerEndpoint(
                        port: port,
                        wsEndpoint: Constants.Qwen3ASR.wsEndpoint(port: port),
                        healthEndpoint: Constants.Qwen3ASR.healthEndpoint(port: port)
                    )
                }
            default:
                return
            }

            let makeLocalASRService: (LocalServerEndpoint) -> LocalASRService = { endpoint in
                LocalASRService(
                    wsEndpoint: endpoint.wsEndpoint,
                    healthEndpoint: endpoint.healthEndpoint,
                    sampleRate: sampleRate,
                    onTranscription: { [weak self] text, isFinal in
                        debugLog("📥 [\(engineLabel)] onTranscription: isFinal=\(isFinal), len=\(text.count)")
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.latestRawTranscription = text
                            self.currentTranscription = self.displayTextForPreview(text, isFinal: isFinal)
                            if self.isEnrolledSpeakerActive {
                                self.updateInlinePreview(self.currentTranscription)
                            }
                        }
                    },
                    onFinalCompletion: { [weak self] text in
                        debugLog("📥 [\(engineLabel)] onFinalCompletion: len=\(text.count)")
                        self?.handleFinalResult(text)
                    },
                    onError: { [weak self] error in
                        debugLog("❌ \(engineLabel) error: \(error)")
                        DispatchQueue.main.async {
                            self?.handleServiceError(error)
                        }
                    },
                    onStatusChange: { [weak self] status in
                        DispatchQueue.main.async {
                            self?.statusMessage = status
                        }
                    },
                    onAudioLevel: { [weak self] level in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.audioLevels.removeFirst()
                            self.audioLevels.append(level)
                        }
                    },
                    onCaptureStarted: { [weak self] in
                        self?.handleCaptureStarted()
                    }
                )
            }

            localServerManager = LocalServerManager(
                serverCommand: serverCommand,
                serverModule: serverModule,
                serverPackagePath: serverPackagePath,
                modelName: modelName,
                requestedPort: 0,
                endpointFactory: endpointFactory,
                httpRequestTimeout: httpRequestTimeout,
                startupTimeout: startupTimeout,
                healthPollInterval: healthPollInterval,
                uvxSearchPaths: uvxSearchPaths,
                onEndpointResolved: { [weak self] endpoint in
                    guard let self else { return }
                    self.localASRService = makeLocalASRService(endpoint)
                    self.updateWarmCaptureConfiguration()
                    self.transcriptionEngine.persistLocalServerPort(endpoint.port)
                    if case .running = self.localServerStatus {
                        self.isReady = true
                        self.statusMessage = String(localized: "準備完了 (\(engineLabel)) - \(self.shortcutUsageDescription)")
                    }
                },
                onStatusChange: { [weak self] status in
                    guard let self else { return }
                    self.localServerStatus = status
                    if case .running = status {
                        if self.localASRService != nil {
                            self.isReady = true
                            self.statusMessage = String(localized: "準備完了 (\(engineLabel)) - \(self.shortcutUsageDescription)")
                        } else {
                            self.statusMessage = String(localized: "\(engineLabel) の接続先を確定中...")
                        }
                    } else if case .error(let msg) = status {
                        self.statusMessage = msg
                    } else if case .starting(let msg) = status {
                        self.statusMessage = msg
                    }
                }
            )

            let currentEngine = transcriptionEngine
            if currentEngine.requiresExternalModelDownload {
                let manager = ModelDownloadManager(
                    modelName: modelName,
                    hfSearchPaths: Constants.HuggingFace.hfSearchPaths,
                    onStatusChange: { [weak self] status in
                        guard let self else { return }
                        self.modelDownloadStatuses[currentEngine] = status
                        if case .downloaded = status, currentEngine == self.transcriptionEngine {
                            self.localServerManager?.start()
                        }
                    }
                )
                modelDownloadManagers[currentEngine] = manager
                manager.checkAndReport()
            } else {
                modelDownloadManagers[currentEngine] = nil
                modelDownloadStatuses[currentEngine] = .downloaded
            }
        }
    }

    private func updateWarmCaptureConfiguration() {
        let shouldWarmCapture =
            shortcutKey.usesLongPressBehavior &&
            (transcriptionEngine == .voxtralLocal || transcriptionEngine == .qwen3ASR)
        localASRService?.setWarmCaptureEnabled(shouldWarmCapture)
    }

    func downloadModel() {
        downloadModel(for: transcriptionEngine)
    }

    func downloadModel(for engine: TranscriptionEngine) {
        if !engine.requiresExternalModelDownload {
            modelDownloadStatuses[engine] = .downloaded
            if engine == transcriptionEngine {
                localServerManager?.start()
            }
            return
        }
        if let manager = modelDownloadManagers[engine] {
            manager.startDownload()
            return
        }
        guard let modelName = engine.hfModelName else { return }
        let manager = ModelDownloadManager(
            modelName: modelName,
            hfSearchPaths: Constants.HuggingFace.hfSearchPaths,
            onStatusChange: { [weak self] status in
                guard let self else { return }
                self.modelDownloadStatuses[engine] = status
                if case .downloaded = status, engine == self.transcriptionEngine {
                    self.localServerManager?.start()
                }
            }
        )
        modelDownloadManagers[engine] = manager
        manager.startDownload()
    }

    func cancelModelDownload() {
        cancelModelDownload(for: transcriptionEngine)
    }

    func cancelModelDownload(for engine: TranscriptionEngine) {
        guard engine.requiresExternalModelDownload else { return }
        modelDownloadManagers[engine]?.cancelDownload()
    }

    func deleteModel() {
        localServerManager?.stop()
        guard transcriptionEngine.requiresExternalModelDownload else { return }
        modelDownloadManagers[transcriptionEngine]?.deleteModel()
    }

    func isModelCached(for engine: TranscriptionEngine) -> Bool {
        guard let modelName = engine.hfModelName else { return false }
        let sanitized = modelName.replacingOccurrences(of: "/", with: "--")
        let snapshotsDir = NSHomeDirectory() + "/.cache/huggingface/hub/models--" + sanitized + "/snapshots"
        guard FileManager.default.fileExists(atPath: snapshotsDir) else { return false }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir) else { return false }
        return !contents.filter({ !$0.hasPrefix(".") }).isEmpty
    }

    func deleteModelCache(for engine: TranscriptionEngine) {
        if engine == transcriptionEngine {
            localServerManager?.stop()
            if engine.requiresExternalModelDownload {
                modelDownloadManagers[transcriptionEngine]?.deleteModel()
                return
            }
        }
        if engine.requiresExternalModelDownload, let manager = modelDownloadManagers[engine] {
            manager.deleteModel()
            return
        }
        guard let modelName = engine.hfModelName else { return }
        let sanitized = modelName.replacingOccurrences(of: "/", with: "--")
        let cacheDir = NSHomeDirectory() + "/.cache/huggingface/hub/models--" + sanitized
        guard FileManager.default.fileExists(atPath: cacheDir) else {
            modelDownloadStatuses[engine] = engine.requiresExternalModelDownload ? .notDownloaded : .downloaded
            return
        }
        do {
            try FileManager.default.removeItem(atPath: cacheDir)
            debugLog("[ModelCache] deleted: \(cacheDir)")
            modelDownloadStatuses[engine] = engine.requiresExternalModelDownload ? .notDownloaded : .downloaded
        } catch {
            debugLog("[ModelCache] failed to delete: \(error)")
        }
    }

    func reinitializeAfterEngineChange() async {
        normalizeTranscriptionEngineSelection()
        isReady = false
        statusMessage = String(localized: "エンジンを切り替え中...")
        await requestPermissions()
    }

    private func requestPermissions() async {
        debugLog("requestPermissions: begin (engine=\(transcriptionEngine.rawValue))")
        statusMessage = String(localized: "権限を確認中...")

        guard #available(macOS 26.0, *) else {
            await MainActor.run {
                statusMessage = String(localized: "macOS 26.0 以上が必要です")
                debugLog("❌ macOS 26.0+ required")
            }
            return
        }

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        debugLog("requestPermissions: microphone authorization status=\(authorizationStatus.rawValue)")

        let micStatus: Bool
        switch authorizationStatus {
        case .authorized:
            micStatus = true
        case .notDetermined:
            micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            micStatus = false
        @unknown default:
            micStatus = false
        }
        guard micStatus else {
            await MainActor.run {
                isReady = false
                statusMessage = String(localized: "マイクの権限が必要です")
            }
            return
        }

        if transcriptionEngine == .voxtralLocal || transcriptionEngine == .qwen3ASR {
            let engineLabel = transcriptionEngine == .voxtralLocal ? "Voxtral Local" : "Qwen3 ASR"
            let modelStatus = modelDownloadStatus
            let shouldStartServer = !transcriptionEngine.requiresExternalModelDownload || {
                if case .downloaded = modelStatus {
                    return true
                }
                return false
            }()

            debugLog("requestPermissions: local engine=\(engineLabel), modelStatus=\(String(describing: modelStatus)), shouldStartServer=\(shouldStartServer)")

            await MainActor.run {
                if case .running = self.localServerStatus {
                    isReady = true
                    statusMessage = String(localized: "準備完了 (\(engineLabel)) - \(shortcutUsageDescription)")
                } else if shouldStartServer {
                    statusMessage = String(localized: "\(engineLabel) サーバーを起動中...")
                } else if case .notDownloaded = modelStatus {
                    statusMessage = String(localized: "モデルのダウンロードが必要です")
                } else if case .downloading = modelStatus {
                    statusMessage = String(localized: "モデルをダウンロード中...")
                } else if case .error(let message) = modelStatus {
                    statusMessage = message
                }
            }

            if shouldStartServer {
                let manager = localServerManager
                Task.detached(priority: .userInitiated) {
                    debugLog("requestPermissions: detached server start for \(engineLabel)")
                    manager?.start()
                }
            }

            debugLog("Using \(engineLabel)")
            return
        }

        let speechRecognitionAuthorized = await requestSpeechRecognitionAuthorization()
        guard speechRecognitionAuthorized else {
            await MainActor.run {
                isReady = false
                statusMessage = String(localized: "音声認識の権限が必要です")
            }
            return
        }

        guard let service = speechAnalyzerService as? SpeechAnalyzerService else {
            await MainActor.run {
                isReady = false
                statusMessage = String(localized: "SpeechAnalyzer の初期化に失敗しました")
                debugLog("❌ SpeechAnalyzer not initialized")
            }
            return
        }

        await MainActor.run {
            statusMessage = String(localized: "SpeechAnalyzer を初期化中...")
        }
        await service.start()
        await MainActor.run {
            isReady = true
            statusMessage = String(localized: "準備完了 - \(shortcutUsageDescription)")
            debugLog("✅ Using Apple SpeechAnalyzer")
        }
    }

    func updateShortcutSelection(_ newValue: ShortcutKey) {
        shortcutKeyRaw = newValue.rawValue
        keyMonitor?.updateShortcut(shortcutKey: newValue, customShortcut: customShortcut)
        updateWarmCaptureConfiguration()
    }

    func updateCustomShortcut(_ newValue: CustomShortcut) {
        customShortcutRaw = newValue.rawValue
        keyMonitor?.updateShortcut(shortcutKey: shortcutKey, customShortcut: newValue)
    }

    private func handleShortcutMonitoringIssue(_ issue: ShortcutMonitoringIssue?) {
        shortcutMonitoringIssue = issue
        if let issue {
            statusMessage = issue.title
        }
    }

    private func requestSpeechRecognitionAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording() {
        if isAwaitingLongPressConfirmation {
            isAwaitingLongPressConfirmation = false
            if hasDeferredLocalCapture {
                localASRService?.confirmRecordingStart()
                activateRecordingUIIfNeeded()
                startSpeakerVerificationCheck()
                return
            }
        }

        guard #available(macOS 26.0, *) else { return }

        if isDebuggerAttached() {
            debugLog("startRecording blocked: debugger detected")
            errorMessage = String(localized: "不正な環境が検出されました")
            floatingPanel?.show()
            return
        }

        debugLog("🔍 [DEBUG] startRecording called - isReady: \(isReady), isRecording: \(isRecording)")

        guard !isRecording else {
            debugLog("🔍 [DEBUG] startRecording guard failed - already recording")
            return
        }

        if !isReady {
            debugLog("🔍 [DEBUG] startRecording - not ready, showing error")
            errorMessage = unavailableRecordingMessage()
            floatingPanel?.show()
            return
        }

        errorMessage = nil
        isRecording = true
        currentTranscription = ""
        latestRawTranscription = ""
        hasDeferredLocalCapture = false
        debugLog("🎙️ Recording started")

        switch transcriptionEngine {
        case .deepgram:
            deepgramService?.startRecording()
            debugLog("[DEBUG] deepgramService.startRecording() called")
        case .voxtralLocal, .qwen3ASR:
            localASRService?.startRecording()
            debugLog("[DEBUG] localASRService.startRecording() called")
        case .speechAnalyzer:
            (speechAnalyzerService as? SpeechAnalyzerService)?.startRecording()
            debugLog("[DEBUG] speechAnalyzerService.startRecording() called")
        }

        shouldShowFloatingPanelForCurrentRecording = captureForInlinePreview()
        startSpeakerVerificationCheck()
    }

    private func beginLongPressRecordingPreflight() {
        guard shortcutKey.usesLongPressBehavior else { return }
        guard !isRecording else { return }
        guard transcriptionEngine == .voxtralLocal || transcriptionEngine == .qwen3ASR else { return }
        guard #available(macOS 26.0, *) else { return }
        guard !isDebuggerAttached() else { return }
        guard isReady else { return }

        errorMessage = nil
        isRecording = true
        currentTranscription = ""
        latestRawTranscription = ""
        isAwaitingLongPressConfirmation = true
        hasDeferredLocalCapture = true
        debugLog("🎙️ Recording preflight started for long-press shortcut")
        localASRService?.startRecording(deferStreamingUntilConfirmation: true)
        shouldShowFloatingPanelForCurrentRecording = captureForInlinePreview()
    }

    private func handleCaptureStarted() {
        guard isRecording else { return }
        guard !isAwaitingLongPressConfirmation else {
            debugLog("🎙️ Capture confirmed - waiting for long-press confirmation")
            return
        }
        activateRecordingUIIfNeeded()
    }

    private func activateRecordingUIIfNeeded() {
        guard isRecording else { return }
        guard !isAwaitingLongPressConfirmation else { return }
        guard recordingStartDate == nil else { return }

        recordingStartDate = Date()
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)
        guard shouldShowFloatingPanelForCurrentRecording else {
            debugLog("🎙️ Capture confirmed - recording UI suppressed (no text input target)")
            return
        }
        debugLog("🎙️ Capture confirmed - recording UI activated")
        floatingPanel?.show()
    }

    private func cancelPendingLongPressRecording() {
        guard isAwaitingLongPressConfirmation else { return }
        debugLog("🚫 Pending long-press recording cancelled before confirmation")
        cancelRecording()
    }

    private func startSpeakerVerificationCheck() {
        guard SpeakerVerificationService.shared.isEnrolled,
              SpeakerVerificationService.shared.isReady else { return }
        isEnrolledSpeakerActive = true
        speakerCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.performSpeakerCheck()
        }
    }

    private func performSpeakerCheck() {
        guard let audioData = getRecordedAudioDataFromActiveService(consuming: false) else { return }
        Task.detached(priority: .utility) {
            do {
                let isMatch = try await SpeakerVerificationService.shared.quickVerify(wavData: audioData)
                await MainActor.run {
                    let wasActive = self.isEnrolledSpeakerActive
                    self.isEnrolledSpeakerActive = isMatch
                    if !isMatch && wasActive {
                        debugLog("SpeakerCheck: enrolled speaker lost, suppressing preview")
                        self.cancelInlinePreview()
                    }
                }
            } catch {
                debugLog("SpeakerCheck: error \(error)")
            }
        }
    }

    func stopRecording() {
        guard #available(macOS 26.0, *) else { return }

        debugLog("🔍 [DEBUG] stopRecording called - isRecording: \(isRecording), errorMessage: \(errorMessage ?? "nil")")

        if errorMessage != nil {
            debugLog("🔍 [DEBUG] stopRecording - hiding error panel")
            errorMessage = nil
            floatingPanel?.hide()
            return
        }

        guard isRecording else {
            debugLog("🔍 [DEBUG] stopRecording guard failed - not recording")
            return
        }
        isRecording = false
        isAwaitingLongPressConfirmation = false
        hasDeferredLocalCapture = false
        recordingStartDate = nil

        speakerCheckTimer?.invalidate()
        speakerCheckTimer = nil

        finalResultTimer?.cancel()
        provisionalFinalizationTimer?.cancel()
        waitingForFinalResult = true
        debugLog("🎙️ Recording stopped - waiting for final result (\(transcriptionEngine.displayName))")
        if shouldShowFloatingPanelForCurrentRecording {
            floatingPanel?.show()
        } else {
            floatingPanel?.hide()
        }
        switch transcriptionEngine {
        case .deepgram:
            deepgramService?.stopRecording()
        case .voxtralLocal, .qwen3ASR:
            localASRService?.stopRecording()
        case .speechAnalyzer:
            (speechAnalyzerService as? SpeechAnalyzerService)?.stopRecording()
        }
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

        scheduleProvisionalFinalizationIfNeeded()

        finalResultTimer = DispatchWorkItem { [weak self] in
            guard let self, self.waitingForFinalResult else { return }
            debugLog("⚠️ SpeechAnalyzer timeout - no final result received")
            self.handleServiceError(String(localized: "音声認識がタイムアウトしました。もう一度試してください"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: finalResultTimer!)
    }

    private func unavailableRecordingMessage() -> String {
        let trimmed = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != String(localized: "初期化中...") else {
            return String(localized: "音声認識が初期化されていません")
        }
        return trimmed
    }

    private func handleServiceError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isActiveRecordingContext = isRecording || isAwaitingLongPressConfirmation || waitingForFinalResult
        let shouldPresentErrorPanel = Self.shouldPresentErrorPanelForRecordingContext(
            isActiveRecordingContext: isActiveRecordingContext,
            hasVisibleInputTarget: shouldShowFloatingPanelForCurrentRecording
        )

        statusMessage = trimmed
        if isActiveRecordingContext {
            cancelRecording()
        } else {
            cancelInlinePreview()
            currentTranscription = ""
        }
        errorMessage = trimmed
        if shouldPresentErrorPanel {
            floatingPanel?.show()
        } else {
            debugLog("🔕 Suppressed error panel without visible input target: \(trimmed)")
        }
    }

    private func handleFinalResult(_ text: String) {
        guard waitingForFinalResult else { return }
        debugLog("✅ Final result received: \(text.count) chars")
        finalResultTimer?.cancel()
        provisionalFinalizationTimer?.cancel()
        waitingForFinalResult = false

        let audioData = getRecordedAudioDataFromActiveService(consuming: true)
        let processedText = addLocalPunctuation(text)
        if processedText.isEmpty {
            if audioData == nil {
                debugLog("⚠️ Final result empty because no recorded audio was available")
                handleServiceError(String(localized: "マイク入力を取得できませんでした。マイク権限と入力デバイスを確認してから、もう一度試してください"))
            } else {
                debugLog("⚠️ Final result empty after processing")
                handleServiceError(String(localized: "音声を認識できませんでした。もう一度はっきり話して試してください"))
            }
            return
        }
        currentTranscription = processedText

        if SpeakerVerificationService.shared.isEnrolled && SpeakerVerificationService.shared.isReady,
           let audioData {
            applySpeakerFilter(processedText: processedText, audioData: audioData)
        } else {
            completeFinalResult(processedText, audioData: audioData)
        }
    }

    private func completeFinalResult(_ text: String, audioData: Data?) {
        addToHistory(text, audioData: audioData)
        finalizeInlinePreview(text)
    }

    private func applySpeakerFilter(processedText: String, audioData: Data) {
        Task.detached(priority: .userInitiated) {
            do {
                let filterResult = try await SpeakerVerificationService.shared.filterByEnrolledSpeaker(wavData: audioData)

                await MainActor.run {
                    if filterResult.totalSpeechDuration == 0 {
                        debugLog("SpeakerFilter: no segments detected, keeping original (audio too short for diarization)")
                        self.completeFinalResult(processedText, audioData: audioData)
                        return
                    }

                    if filterResult.enrolledRatio == 0 {
                        debugLog("SpeakerFilter: discarded (enrolled speaker not detected)")
                        self.cancelInlinePreview()
                        self.floatingPanel?.hide()
                        return
                    }

                    if filterResult.isSingleSpeaker || filterResult.enrolledRatio > 0.8 {
                        debugLog("SpeakerFilter: keeping original (ratio=\(filterResult.enrolledRatio), single=\(filterResult.isSingleSpeaker))")
                        self.completeFinalResult(processedText, audioData: audioData)
                        return
                    }

                    if let filteredSamples = filterResult.filteredAudioSamples {
                        debugLog("SpeakerFilter: re-transcribing filtered audio (\(filteredSamples.count) samples)")
                        self.retranscribeFilteredAudio(filteredSamples, originalAudioData: audioData)
                    } else {
                        self.completeFinalResult(processedText, audioData: audioData)
                    }
                }
            } catch {
                debugLog("SpeakerFilter: error \(error), keeping original")
                await MainActor.run {
                    self.completeFinalResult(processedText, audioData: audioData)
                }
            }
        }
    }

    private func retranscribeFilteredAudio(_ samples: [Float], originalAudioData: Data) {
        let wavData = SpeakerVerificationService.shared.createWAV(from: samples)
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString).wav")

        do {
            try wavData.write(to: tempURL)
        } catch {
            debugLog("SpeakerFilter: failed to write temp file: \(error)")
            cancelInlinePreview()
            floatingPanel?.hide()
            return
        }

        let engine = transcriptionEngine
        Task {
            defer { try? FileManager.default.removeItem(at: tempURL) }

            do {
                var result: String
                if #available(macOS 26.0, *) {
                    result = try await BatchTranscriptionService.shared.transcribeFile(
                        at: tempURL,
                        engine: engine,
                        onProgress: { _ in },
                        onStatusChange: { _ in }
                    )
                } else {
                    result = ""
                }

                let processedResult = addLocalPunctuation(result)
                if !processedResult.isEmpty {
                    debugLog("SpeakerFilter: re-transcription result: \(processedResult.count) chars")
                    completeFinalResult(processedResult, audioData: originalAudioData)
                } else {
                    debugLog("SpeakerFilter: re-transcription empty, discarding")
                    cancelInlinePreview()
                    floatingPanel?.hide()
                }
            } catch {
                debugLog("SpeakerFilter: re-transcription failed: \(error)")
                cancelInlinePreview()
                floatingPanel?.hide()
            }
        }
    }

    private func cleanupOrphanedParticles(_ text: String) -> String {
        var result = text
        let orphanedParticlePatterns = [
            "^ね、", "^よ、", "^さ、", "^な、",
            "^ね。", "^よ。", "^さ。", "^な。"
        ]
        for pattern in orphanedParticlePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addLocalPunctuation(_ text: String, isFinal: Bool = true) -> String {
        let processor = TextProcessor(fillerSettings: fillerSettings, dictionaryEntries: dictionaryEntries)
        return processor.process(text, isFinal: isFinal)
    }

    private func displayTextForPreview(_ text: String, isFinal: Bool) -> String {
        guard isFinal else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return addLocalPunctuation(text, isFinal: true)
    }

    private func scheduleProvisionalFinalizationIfNeeded() {
        guard transcriptionEngine == .voxtralLocal || transcriptionEngine == .qwen3ASR else { return }
        guard !(SpeakerVerificationService.shared.isEnrolled && SpeakerVerificationService.shared.isReady) else { return }

        let fallbackText = latestRawTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackText.isEmpty else { return }

        let delay = DispatchTimeInterval.milliseconds(Int(Constants.Audio.finalizationWaitMilliseconds))
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.waitingForFinalResult else { return }
            debugLog("⏱️ Using provisional finalization for \(self.transcriptionEngine.displayName)")
            self.handleFinalResult(fallbackText)
        }
        provisionalFinalizationTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performPaste(_ text: String) {
        waitingForFinalResult = false
        floatingPanel?.hide()
        guard !text.isEmpty else {
            debugLog("⚠️ No text to paste - text is empty")
            return
        }
        debugLog("🔍 [DEBUG] About to copy and paste: \(text.count) chars")
        pasteWithClipboardRestore(text)
    }

    private func pasteWithClipboardRestore(_ text: String) {
        let pasteboard = NSPasteboard.general

        let previousContents = pasteboard.string(forType: .string)
        debugLog("📋 Saving previous clipboard: \(previousContents?.count ?? 0) chars")

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        debugLog("📋 Set clipboard to: \(text.count) chars")

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.pastePreDelaySeconds) { [weak self] in
            self?.simulatePaste {
                let restoreDelay = Self.clipboardRestoreDelay()
                DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                    let currentContents = pasteboard.string(forType: .string)
                    guard Self.shouldRestoreClipboard(
                        previousContents: previousContents,
                        currentContents: currentContents,
                        pastedText: text
                    ) else {
                        debugLog("📋 Skipped clipboard restore: current clipboard changed before restore window elapsed")
                        return
                    }

                    if let prev = previousContents {
                        pasteboard.clearContents()
                        pasteboard.setString(prev, forType: .string)
                        debugLog("📋 Restored previous clipboard: \(prev.count) chars")
                    }
                }
            }
        }
    }

    static func clipboardRestoreDelay() -> TimeInterval {
        Constants.Timing.pastePostDelaySeconds
    }

    static func shouldRestoreClipboard(
        previousContents: String?,
        currentContents: String?,
        pastedText: String
    ) -> Bool {
        guard previousContents != nil else { return false }
        return currentContents == pastedText
    }

    static func shouldShowFloatingPanelForRecording(hasTextInputTarget: Bool, spotlightOpen: Bool) -> Bool {
        hasTextInputTarget || spotlightOpen
    }

    static func shouldPresentErrorPanelForRecordingContext(
        isActiveRecordingContext: Bool,
        hasVisibleInputTarget: Bool
    ) -> Bool {
        guard isActiveRecordingContext else { return true }
        return hasVisibleInputTarget
    }

    private func simulatePaste(completion: @escaping () -> Void) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            debugLog("❌ No text in clipboard")
            completion()
            return
        }

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            debugLog("📱 Frontmost app: \(frontApp.localizedName ?? "unknown") (bundle: \(frontApp.bundleIdentifier ?? "unknown"), PID: \(frontApp.processIdentifier))")
        } else {
            debugLog("📱 Frontmost app: nil")
        }

        if isSpotlightOpen() {
            debugLog("🔍 Spotlight detected - using AXUIElement API")
            setTextToSpotlight(text)
            completion()
            return
        }

        debugLog("🎯 Sending Cmd+V paste via CGEvent")

        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            debugLog("❌ Failed to create CGEvent")
            completion()
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(50000)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        debugLog("✅ Paste command sent via CGEvent")
        completion()
    }

    private func isSpotlightOpen() -> Bool {
        guard let spotlightApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first else {
            return false
        }

        let axApp = AXUIElementCreateApplication(spotlightApp.processIdentifier)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows) == .success,
              let windowArray = windows as? [AXUIElement],
              !windowArray.isEmpty else {
            return false
        }

        debugLog("🔍 Spotlight windows found: \(windowArray.count)")
        return true
    }

    private func setTextToSpotlight(_ text: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight")
        guard let spotlightApp = apps.first else {
            debugLog("❌ Spotlight app not found")
            return
        }

        let axApp = AXUIElementCreateApplication(spotlightApp.processIdentifier)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows)

        guard let windowArray = windows as? [AXUIElement], let window = windowArray.first else {
            debugLog("❌ No Spotlight windows found")
            return
        }

        if let searchField = findSearchField(in: window) {
            let setResult = AXUIElementSetAttributeValue(searchField, kAXValueAttribute as CFString, text as CFTypeRef)
            if setResult == .success {
                debugLog("✅ Text set to Spotlight via AXUIElement")
            } else {
                debugLog("❌ AXUIElement failed (\(setResult.rawValue)), trying CGEvent postToPid")
                sendPasteToSpotlight(pid: spotlightApp.processIdentifier)
            }
        } else {
            debugLog("⚠️ No search field found, trying CGEvent postToPid")
            sendPasteToSpotlight(pid: spotlightApp.processIdentifier)
        }
    }

    private func findSearchField(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 10 { return nil }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        if let roleStr = role as? String {
            debugLog("🔍 [AX] depth=\(depth) role=\(roleStr)")
            if roleStr == "AXTextField" || roleStr == "AXSearchField" || roleStr == "AXTextArea" {
                return element
            }
        }

        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        if let childArray = children as? [AXUIElement] {
            for child in childArray {
                if let found = findSearchField(in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private func sendPasteToSpotlight(pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            debugLog("❌ Failed to create CGEvent for Spotlight")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.postToPid(pid)
        usleep(50000)
        keyUp.postToPid(pid)

        debugLog("✅ Paste sent to Spotlight PID \(pid) via postToPid")
    }

    @discardableResult
    private func captureForInlinePreview() -> Bool {
        capturedTextElement = nil
        inlinePreviewLength = 0
        inlinePreviewActive = false
        let spotlightOpen = isSpotlightOpen()

        guard let context = FocusedElementInspector.focusedTextInputContext() else {
            if FocusedElementInspector.focusedElementUsesKeyboardPreviewFallback() {
                switchToKeyboardPreview("")
                debugLog("🔍 [InlinePreview] Using keyboard preview fallback")
            } else {
                debugLog("🔍 [InlinePreview] Focused element does not accept text input")
            }
            return Self.shouldShowFloatingPanelForRecording(hasTextInputTarget: useKeyboardPreview, spotlightOpen: spotlightOpen)
        }

        guard let rangeRef = context.selectedTextRange else {
            debugLog("🔍 [InlinePreview] Could not get selected text range")
            return Self.shouldShowFloatingPanelForRecording(hasTextInputTarget: false, spotlightOpen: spotlightOpen)
        }

        var range = CFRange(location: 0, length: 0)
        AXValueGetValue(rangeRef, .cfRange, &range)

        capturedTextElement = context.element
        insertionPointLocation = range.location + range.length
        inlinePreviewActive = true
        debugLog("🔍 [InlinePreview] Captured text element (role: \(context.snapshot.role ?? "unknown"), cursor: \(insertionPointLocation))")
        return Self.shouldShowFloatingPanelForRecording(hasTextInputTarget: true, spotlightOpen: spotlightOpen)
    }

    private var inlinePreviewVerified = false
    private var useKeyboardPreview = false
    private var keyboardPreviewText = ""
    private var currentAXPreviewText = ""

    @discardableResult
    private func updateInlinePreview(_ text: String) -> Bool {
        if useKeyboardPreview {
            updateKeyboardPreview(text)
            return true
        }

        guard inlinePreviewActive, let element = capturedTextElement else { return false }

        let nsText = text as NSString
        let newLength = nsText.length
        let oldNSText = currentAXPreviewText as NSString
        let commonPrefixStr = currentAXPreviewText.commonPrefix(with: text)
        let commonPrefixLen = (commonPrefixStr as NSString).length

        if commonPrefixLen == oldNSText.length && newLength > oldNSText.length {
            let suffix = nsText.substring(from: commonPrefixLen)
            var cursorRange = CFRange(location: insertionPointLocation + inlinePreviewLength, length: 0)
            guard let cursorRangeValue = AXValueCreate(.cfRange, &cursorRange) else { return false }

            let setRangeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, cursorRangeValue)
            guard setRangeResult == .success else {
                debugLog("🔍 [InlinePreview] AX append cursor failed, switching to keyboard mode")
                switchToKeyboardPreview(text)
                return true
            }

            let setTextResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, suffix as CFTypeRef)
            guard setTextResult == .success else {
                debugLog("🔍 [InlinePreview] AX append text failed, switching to keyboard mode")
                switchToKeyboardPreview(text)
                return true
            }

            inlinePreviewLength = newLength
            currentAXPreviewText = text
        } else if text != currentAXPreviewText {
            var range = CFRange(location: insertionPointLocation, length: inlinePreviewLength)
            guard let rangeValue = AXValueCreate(.cfRange, &range) else { return false }

            let setRangeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            guard setRangeResult == .success else {
                debugLog("🔍 [InlinePreview] AX set range failed, switching to keyboard mode")
                switchToKeyboardPreview(text)
                return true
            }

            let setTextResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            guard setTextResult == .success else {
                debugLog("🔍 [InlinePreview] AX set text failed, switching to keyboard mode")
                switchToKeyboardPreview(text)
                return true
            }

            inlinePreviewLength = newLength
            currentAXPreviewText = text
        }

        if !inlinePreviewVerified && newLength > 0 {
            var verifyRange = CFRange(location: insertionPointLocation, length: newLength)
            if let verifyRangeValue = AXValueCreate(.cfRange, &verifyRange) {
                var readText: CFTypeRef?
                let readResult = AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    verifyRangeValue,
                    &readText
                )
                if readResult == .success, let readBack = readText as? String, readBack == text {
                    inlinePreviewVerified = true
                    debugLog("🔍 [InlinePreview] Verified: AX text insertion confirmed")
                } else {
                    debugLog("🔍 [InlinePreview] AX verification failed, switching to keyboard mode")
                    undoAXInsert(element: element, length: newLength)
                    switchToKeyboardPreview(text)
                    return true
                }
            }
        }

        return true
    }

    private func undoAXInsert(element: AXUIElement, length: Int) {
        var range = CFRange(location: insertionPointLocation, length: length)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "" as CFTypeRef)
        }
        inlinePreviewLength = 0
        inlinePreviewActive = false
        capturedTextElement = nil
    }

    private func switchToKeyboardPreview(_ text: String) {
        inlinePreviewActive = false
        useKeyboardPreview = true
        keyboardPreviewText = ""
        updateKeyboardPreview(text)
        debugLog("🔍 [InlinePreview] Keyboard preview mode activated")
    }

    private func selectPreviewRange(length: Int) -> Bool {
        guard length > 0, let element = capturedTextElement else { return false }
        var range = CFRange(location: insertionPointLocation, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success
    }

    private func updateKeyboardPreview(_ text: String) {
        let oldText = keyboardPreviewText
        let commonPrefix = oldText.commonPrefix(with: text)
        let charsToDelete = oldText.count - commonPrefix.count
        let newSuffix = String(text.dropFirst(commonPrefix.count))
        let oldLength = (oldText as NSString).length

        let source = CGEventSource(stateID: .privateState)

        if charsToDelete > 0, selectPreviewRange(length: oldLength) {
            if text.isEmpty {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: false) {
                    keyDown.post(tap: .cgAnnotatedSessionEventTap)
                    keyUp.post(tap: .cgAnnotatedSessionEventTap)
                }
            } else {
                typeUnicodeString(text, source: source)
            }
            keyboardPreviewText = text
            return
        }

        for _ in 0..<charsToDelete {
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: false) {
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }
        }

        if !newSuffix.isEmpty {
            typeUnicodeString(newSuffix, source: source)
        }

        keyboardPreviewText = text
    }

    private func typeUnicodeString(_ text: String, source: CGEventSource?) {
        let utf16 = Array(text.utf16)
        let chunkSize = 20

        var start = 0
        while start < utf16.count {
            var end = min(start + chunkSize, utf16.count)
            if end < utf16.count && UTF16.isLeadSurrogate(utf16[end - 1]) {
                end -= 1
            }
            if end <= start { break }
            var chunk = Array(utf16[start..<end])
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
            }
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }
            start = end
        }
    }

    private func finalizeInlinePreview(_ text: String) {
        floatingPanel?.hide()
        guard !text.isEmpty else {
            debugLog("⚠️ No text to paste - text is empty")
            cancelInlinePreview()
            return
        }

        if useKeyboardPreview {
            if keyboardPreviewText != text {
                updateKeyboardPreview(text)
            }
            resetInlinePreviewState()
            debugLog("✅ [InlinePreview] Finalized in place via keyboard preview")
            return
        }

        if inlinePreviewActive, let element = capturedTextElement {
            if currentAXPreviewText != text {
                _ = updateInlinePreview(text)
            }

            if useKeyboardPreview {
                if keyboardPreviewText != text {
                    updateKeyboardPreview(text)
                }
                resetInlinePreviewState()
                debugLog("✅ [InlinePreview] Finalized in place after keyboard fallback")
                return
            }

            if currentAXPreviewText == text {
                debugLog("✅ [InlinePreview] Finalized in place via AX: \(text.count) chars")
                resetInlinePreviewState()
                return
            }

            var range = CFRange(location: insertionPointLocation, length: inlinePreviewLength)
            if let rangeValue = AXValueCreate(.cfRange, &range) {
                let setRangeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
                if setRangeResult == .success {
                    let setTextResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
                    if setTextResult == .success {
                        debugLog("✅ [InlinePreview] Finalized via AX (full replace): \(text.count) chars")
                        resetInlinePreviewState()
                        return
                    }
                }
            }
        }

        debugLog("🔍 [InlinePreview] Fallback to clipboard paste")
        resetInlinePreviewState()
        performPaste(text)
    }

    private func cancelInlinePreview() {
        if useKeyboardPreview {
            updateKeyboardPreview("")
            debugLog("🚫 [InlinePreview] Keyboard preview cancelled")
            resetInlinePreviewState()
            return
        }
        guard inlinePreviewActive, capturedTextElement != nil else {
            resetInlinePreviewState()
            return
        }
        updateInlinePreview("")
        debugLog("🚫 [InlinePreview] AX preview cancelled")
        resetInlinePreviewState()
    }

    private func resetInlinePreviewState() {
        capturedTextElement = nil
        insertionPointLocation = 0
        inlinePreviewLength = 0
        inlinePreviewActive = false
        inlinePreviewVerified = false
        useKeyboardPreview = false
        keyboardPreviewText = ""
        currentAXPreviewText = ""
    }

    func cancelRecording() {
        cancelInlinePreview()
        switch transcriptionEngine {
        case .deepgram:
            deepgramService?.stop()
        case .voxtralLocal, .qwen3ASR:
            localASRService?.stop()
        case .speechAnalyzer:
            if #available(macOS 26.0, *) {
                (speechAnalyzerService as? SpeechAnalyzerService)?.stop()
            }
        }
        isRecording = false
        isAwaitingLongPressConfirmation = false
        hasDeferredLocalCapture = false
        shouldShowFloatingPanelForCurrentRecording = false
        waitingForFinalResult = false
        finalResultTimer?.cancel()
        provisionalFinalizationTimer?.cancel()
        recordingStartDate = nil
        currentTranscription = ""
        latestRawTranscription = ""
        floatingPanel?.hide()
        debugLog("🚫 Recording cancelled")
    }

    @discardableResult
    private func addToHistory(_ text: String, audioData: Data? = nil) -> UUID {
        var audioPath: String? = nil

        if let data = audioData {
            let recordingsDir = getRecordingsDirectory()
            let fileName = "\(UUID().uuidString).wav"
            let filePath = recordingsDir.appendingPathComponent(fileName)

            do {
                try data.write(to: filePath)
                audioPath = filePath.path
                debugLog("🎵 Audio saved: \(filePath.path)")
            } catch {
                debugLog("❌ Failed to save audio: \(error)")
            }
        }

        let record = TranscriptionRecord(text: text, timestamp: Date(), audioPath: audioPath)
        history.insert(record, at: 0)
        if history.count > 20 {
            if let removed = history.last, let path = removed.audioPath {
                try? FileManager.default.removeItem(atPath: path)
                debugLog("🗑️ Old audio removed: \(path)")
            }
            history.removeLast()
        }
        saveHistory()
        debugLog("📚 Added to history: \(text.count) chars (id: \(record.id))")
        return record.id
    }

    private func getRecordingsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = appSupport.appendingPathComponent("NiceVoice/recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        return recordingsDir
    }

    func copyHistoryItem(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        debugLog("📋 Copied from history: \(text.count) chars")
    }

    func clearHistory() {
        for record in history {
            if let path = record.audioPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        history.removeAll()
        saveHistory()
        debugLog("🗑️ History cleared")
    }

    func removeHistoryItem(_ record: TranscriptionRecord) {
        if let path = record.audioPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        history.removeAll { $0.id == record.id }
        saveHistory()
        debugLog("🗑️ Removed from history: \(record.text.count) chars")
    }

    func addToBenchmark(_ record: TranscriptionRecord, expectedText: String) -> Bool {
        guard let audioPath = record.audioPath,
              FileManager.default.fileExists(atPath: audioPath) else {
            debugLog("❌ No audio file for benchmark")
            return false
        }

        let projectRoot = getProjectRoot()
        let benchmarkDir = projectRoot.appendingPathComponent("benchmark-audio")
        let manifestPath = benchmarkDir.appendingPathComponent("manifest.json")

        let id = "user_\(record.id.uuidString.prefix(8).lowercased())"
        let destFileName = "\(id).wav"
        let destPath = benchmarkDir.appendingPathComponent(destFileName)

        do {
            try FileManager.default.copyItem(atPath: audioPath, toPath: destPath.path)
            debugLog("🎵 Audio copied to benchmark: \(destPath.path)")
        } catch {
            debugLog("❌ Failed to copy audio: \(error)")
            return false
        }

        struct TestCase: Codable {
            let id: String
            let text: String
            let audioPath: String
        }

        var testCases: [TestCase] = []
        if let data = try? Data(contentsOf: manifestPath),
           let existing = try? JSONDecoder().decode([TestCase].self, from: data) {
            testCases = existing
        }

        let newCase = TestCase(id: id, text: expectedText, audioPath: "benchmark-audio/\(destFileName)")
        testCases.append(newCase)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(testCases)
            try data.write(to: manifestPath)
            debugLog("✅ Added to benchmark: \(id)")
            return true
        } catch {
            debugLog("❌ Failed to update manifest: \(error)")
            return false
        }
    }

    private func getProjectRoot() -> URL {
        var url = URL(fileURLWithPath: #file)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func getRecordedAudioDataFromActiveService(consuming: Bool) -> Data? {
        switch transcriptionEngine {
        case .deepgram:
            return deepgramService?.getRecordedAudioData(consuming: consuming)
        case .voxtralLocal, .qwen3ASR:
            return localASRService?.getRecordedAudioData(consuming: consuming)
        case .speechAnalyzer:
            guard #available(macOS 26.0, *) else { return nil }
            return (speechAnalyzerService as? SpeechAnalyzerService)?.getRecordedAudioData(consuming: consuming)
        }
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func saveUsageStats() {
        save(usageStats, forKey: UserDefaultsKey.usageStats)
    }

    private func loadUsageStats() {
        if let stats: UsageStats = load(forKey: UserDefaultsKey.usageStats) {
            usageStats = stats
            usageStats.resetTodayIfNeeded()
        }
    }

    private func saveDictionary() {
        save(dictionaryEntries, forKey: UserDefaultsKey.dictionary)
    }

    private func loadDictionary() {
        if let entries: [DictionaryEntry] = load(forKey: UserDefaultsKey.dictionary) {
            dictionaryEntries = entries
            deduplicateDictionary()
            sortDictionary()
        }
    }

    private func saveFillerSettings() {
        save(fillerSettings, forKey: UserDefaultsKey.fillerSettings)
    }

    private func loadFillerSettings() {
        if let settings: FillerSettings = load(forKey: UserDefaultsKey.fillerSettings) {
            fillerSettings = settings
        }
    }

    private func saveHistory() {
        save(history, forKey: UserDefaultsKey.history)
        debugLog("💾 History saved (\(history.count) items)")
    }

    private func loadHistory() {
        if let records: [TranscriptionRecord] = load(forKey: UserDefaultsKey.history) {
            history = records
            debugLog("📂 History loaded (\(records.count) items)")
        }
    }

    func addDictionaryEntry(_ entry: DictionaryEntry) {
        guard !dictionaryEntries.contains(where: { $0.reading == entry.reading }) else {
            debugLog("⚠️ Duplicate dictionary entry ignored: \(entry.reading)")
            return
        }
        dictionaryEntries.append(entry)
        sortDictionary()
        saveDictionary()
    }

    func removeDictionaryEntry(_ entry: DictionaryEntry) {
        dictionaryEntries.removeAll { $0.id == entry.id }
        saveDictionary()
    }

    func updateDictionaryEntry(_ entry: DictionaryEntry) {
        if let index = dictionaryEntries.firstIndex(where: { $0.id == entry.id }) {
            dictionaryEntries[index] = entry
            sortDictionary()
            saveDictionary()
        }
    }

    func deduplicateDictionary() {
        var seen = Set<String>()
        var unique: [DictionaryEntry] = []
        for entry in dictionaryEntries {
            if !seen.contains(entry.reading) {
                seen.insert(entry.reading)
                unique.append(entry)
            }
        }
        if unique.count != dictionaryEntries.count {
            debugLog("🧹 Removed \(dictionaryEntries.count - unique.count) duplicate entries")
            dictionaryEntries = unique
            sortDictionary()
            saveDictionary()
        }
    }

    private func sortDictionary() {
        dictionaryEntries.sort { $0.reading.localizedCompare($1.reading) == .orderedAscending }
    }

    func recordConversion(characters: Int, tokens: Int) {
        usageStats.recordConversion(characters: characters, tokens: tokens)
        saveUsageStats()
    }

    func updateFillerSettings(_ settings: FillerSettings) {
        fillerSettings = settings
        saveFillerSettings()
    }
}

struct SpinningIcon: View {
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "arrow.trianglehead.2.clockwise")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.blue)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct FloatingPanelView: View {
    var appState: AppState
    @State private var isVisible = false

    private var isError: Bool {
        appState.errorMessage != nil
    }

    var body: some View {
        Group {
            if isError {
                ErrorIndicatorView(message: appState.errorMessage ?? "")
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if appState.isShowingFinalizationPanel {
                FinalizingIndicatorView(previewText: appState.floatingPanelPreviewText)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                RecordingIndicatorView(
                    currentLevel: { appState.audioLevels.last ?? 0 },
                    startDate: appState.recordingStartDate
                )
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .scaleEffect(isVisible ? 1 : 0.6)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

struct FinalizingIndicatorView: View {
    let previewText: String
    @State private var animateHighlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.18), .cyan.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .scaleEffect(animateHighlight ? 1.08 : 0.92)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("文章を整え中")
                        .font(.system(size: 13, weight: .semibold))
                    Text("句読点と話し言葉をなめらかに整えています")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ProgressView()
                    .controlSize(.small)
                    .tint(.blue)
            }

            if !previewText.isEmpty {
                Text(previewText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
        }
        .frame(maxWidth: Constants.UI.floatingPanelExpandedWidth, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                animateHighlight = true
            }
        }
    }
}

struct RecordingIndicatorView: View {
    let currentLevel: () -> Float
    let startDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)

            BrailleMeterView(currentLevel: currentLevel)

            if let startDate {
                RecordingTimerView(startDate: startDate)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct RecordingTimerView: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { timeline in
            let elapsed = Int(timeline.date.timeIntervalSince(startDate))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            Text(String(format: "%d:%02d", minutes, seconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

final class BrailleMeterState {
    private var history: [Character]
    private var noiseEma: Double = 0.02
    private var env: Double = 0.0

    init() {
        history = Array(
            repeating: Constants.BrailleMeter.symbols[0],
            count: Constants.BrailleMeter.historyLength
        )
    }

    func nextText(level: Float) -> String {
        let symbols = Constants.BrailleMeter.symbols
        let latestPeak = Double(level)

        if latestPeak > env {
            env = Constants.BrailleMeter.attack * latestPeak
                + (1.0 - Constants.BrailleMeter.attack) * env
        } else {
            env = Constants.BrailleMeter.release * latestPeak
                + (1.0 - Constants.BrailleMeter.release) * env
        }

        let rmsApprox = env * 0.7
        noiseEma = (1.0 - Constants.BrailleMeter.alphaNoiseFloor) * noiseEma
            + Constants.BrailleMeter.alphaNoiseFloor * rmsApprox
        let refLevel = max(noiseEma, 0.01)
        let fastSignal = 0.8 * latestPeak + 0.2 * env
        let raw = max(fastSignal / (refLevel * 2.0), 0.0)
        let k = 1.6
        let compressed = min(log1p(raw) / log1p(k), 1.0)
        let maxIdx = Double(symbols.count - 1)
        let idx = Int(min(max((compressed * maxIdx).rounded(), 0), maxIdx))

        history.removeFirst()
        history.append(symbols[idx])

        return String(history)
    }
}

struct BrailleMeterView: View {
    let currentLevel: () -> Float
    @State private var state = BrailleMeterState()

    var body: some View {
        TimelineView(.periodic(from: .now, by: Constants.BrailleMeter.updateInterval)) { _ in
            Text(state.nextText(level: currentLevel()))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(.red.opacity(0.85))
        }
    }
}

struct ErrorIndicatorView: View {
    let message: String
    @State private var isPulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14, weight: .semibold))
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("文字起こしできません")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: Constants.UI.floatingPanelExpandedWidth, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            isPulsing = true
        }
    }
}

struct MenuBarView: View {
    var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                    .foregroundStyle(appState.isRecording ? .red : .primary)
                Text("Nice Voice")
                    .font(.headline)
            }

            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Nice Voice を開く...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 200)
    }
}
