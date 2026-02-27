import SwiftUI
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices
import os.log
import CommonCrypto

private let logger = Logger(subsystem: "com.nicevoice.app", category: "general")

extension Notification.Name {
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
}

@main
struct NiceVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Nice Voice", id: "main") {
            MainWindowView(appState: appDelegate.appState)
        }
        .defaultSize(width: 800, height: 600)
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
        initializeAuthManager()

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authDidChange),
            name: .authDidChange,
            object: nil
        )
    }

    private func initializeAuthManager() {
        Task {
            await AuthManager.shared.initialize()
            debugLog("AuthManager initialized: subscriber=\(AuthManager.shared.isSubscriber)")
        }
    }

    @objc private func authDidChange() {
        debugLog("Auth changed: subscriber=\(AuthManager.shared.isSubscriber)")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURLScheme(url)
        }
    }

    private func handleURLScheme(_ url: URL) {
        debugLog("URL scheme received: \(url)")

        guard url.scheme == "nicevoice",
              url.host == "auth",
              url.path == "/callback" else {
            debugLog("Unhandled URL scheme: \(url)")
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sessionId = components.queryItems?.first(where: { $0.name == "session_id" })?.value else {
            debugLog("Missing session_id in callback URL")
            return
        }

        debugLog("Auth callback received with session_id")
        Task {
            await AuthManager.shared.handleLoginCallback(sessionId: sessionId)
        }
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

        let openItem = NSMenuItem(title: "Nice Voice を開く", action: #selector(openMainWindowAction), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = .command
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
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
    var isReady = false
    var statusMessage = "初期化中..."
    var errorMessage: String?
    var history: [TranscriptionRecord] = []
    var audioLevels: [Float] = Array(repeating: 0, count: 20)
    var recordingStartDate: Date?

    @ObservationIgnored
    @AppStorage("shortcutKey") var shortcutKeyRaw = ShortcutKey.fn.rawValue

    var shortcutKey: ShortcutKey {
        get { ShortcutKey(rawValue: shortcutKeyRaw) ?? .fn }
        set {
            shortcutKeyRaw = newValue.rawValue
            keyMonitor?.updateShortcutKey(newValue)
        }
    }

    var usageStats: UsageStats = UsageStats()
    var dictionaryEntries: [DictionaryEntry] = []
    var fillerSettings: FillerSettings = FillerSettings()

    @ObservationIgnored
    @AppStorage("transcriptionEngine") var transcriptionEngineRaw = TranscriptionEngine.speechAnalyzer.rawValue

    var transcriptionEngine: TranscriptionEngine {
        get { TranscriptionEngine(rawValue: transcriptionEngineRaw) ?? .speechAnalyzer }
        set { transcriptionEngineRaw = newValue.rawValue }
    }

    private var speechAnalyzerService: Any?
    private var localASRService: LocalASRService?
    private var deepgramService: DeepgramService?
    private(set) var localServerManager: LocalServerManager?
    var localServerStatus: LocalServerStatus = .stopped
    private(set) var modelDownloadManager: ModelDownloadManager?
    var modelDownloadStatus: ModelDownloadStatus = .downloaded
    private(set) var keyMonitor: KeyMonitor?
    private var floatingPanel: FloatingPanel?
    private var waitingForFinalResult = false
    private var finalResultTimer: DispatchWorkItem?
    private var speakerCheckTimer: Timer?
    private var isEnrolledSpeakerActive = true
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
        setupServices()
        initializeSpeakerVerificationIfNeeded()
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
        setupTranscriptionService()

        if #available(macOS 26.0, *) {
            speechAnalyzerService = SpeechAnalyzerService(
                onTranscription: { [weak self] text, isFinal in
                    debugLog("📥 onTranscription called: isFinal=\(isFinal), len=\(text.count), text='\(text.prefix(50))'")
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.currentTranscription = self.addLocalPunctuation(text, isFinal: isFinal)
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
                    self?.statusMessage = error
                },
                onStatusChange: { [weak self] status in
                    DispatchQueue.main.async {
                        self?.statusMessage = status
                    }
                },
                onAudioLevel: { [weak self] level in
                    guard let self else { return }
                    self.audioLevels.removeFirst()
                    self.audioLevels.append(level)
                },
                onLanguageDetected: { [weak self] language in
                    DispatchQueue.main.async {
                        debugLog("🌍 Language detected: \(language.displayName)")
                        self?.statusMessage = "検出: \(language.displayName)"
                    }
                }
            )
        }

        keyMonitor = KeyMonitor(
            shortcutKey: shortcutKey,
            onKeyDown: { [weak self] in self?.startRecording() },
            onKeyUp: { [weak self] in self?.stopRecording() }
        )

        floatingPanel = FloatingPanel(appState: self)

        Task {
            await requestPermissions()
        }
    }

    func setupTranscriptionService() {
        localASRService = nil
        deepgramService = nil
        modelDownloadManager?.cancelDownload()
        modelDownloadManager = nil
        localServerManager?.stop()
        localServerManager = nil
        localServerStatus = .stopped
        modelDownloadStatus = transcriptionEngine.requiresLocalServer ? .notDownloaded : .downloaded

        if transcriptionEngine == .deepgram {
            let apiKey = Constants.Deepgram.apiKey
            guard apiKey != "DEEPGRAM_API_KEY_PLACEHOLDER", !apiKey.isEmpty else {
                statusMessage = "Deepgram API キーが未設定です"
                debugLog("Deepgram: no API key configured")
                return
            }

            deepgramService = DeepgramService(
                apiKey: apiKey,
                onTranscription: { [weak self] text, isFinal in
                    debugLog("[Deepgram] onTranscription: isFinal=\(isFinal), len=\(text.count)")
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.currentTranscription = self.addLocalPunctuation(text, isFinal: isFinal)
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
                        self?.statusMessage = error
                    }
                },
                onStatusChange: { [weak self] status in
                    DispatchQueue.main.async {
                        self?.statusMessage = status
                    }
                },
                onAudioLevel: { [weak self] level in
                    guard let self else { return }
                    self.audioLevels.removeFirst()
                    self.audioLevels.append(level)
                }
            )
            isReady = true
            statusMessage = "準備完了 (Deepgram) - \(shortcutKey.displayName) キーを押して録音"
            debugLog("Using Deepgram Nova-3")
            return
        }

        if transcriptionEngine == .voxtralLocal || transcriptionEngine == .qwen3ASR {
            let wsEndpoint: String
            let sampleRate: Double
            let serverCommand: String
            let serverPackagePath: String
            let modelName: String
            let port: Int
            let healthEndpoint: String
            let httpRequestTimeout: Double
            let startupTimeout: Double
            let healthPollInterval: Double
            let uvxSearchPaths: [String]
            let engineLabel: String

            switch transcriptionEngine {
            case .voxtralLocal:
                wsEndpoint = Constants.VoxtralLocal.wsEndpoint
                sampleRate = Constants.VoxtralLocal.sampleRate
                serverCommand = "voxmlx-serve"
                serverPackagePath = ""
                modelName = Constants.VoxtralLocal.defaultModel
                port = 8000
                healthEndpoint = Constants.VoxtralLocal.healthEndpoint
                httpRequestTimeout = Constants.VoxtralLocal.httpRequestTimeoutSeconds
                startupTimeout = Constants.VoxtralLocal.serverStartupTimeoutSeconds
                healthPollInterval = Constants.VoxtralLocal.healthPollIntervalSeconds
                uvxSearchPaths = Constants.VoxtralLocal.uvxSearchPaths
                engineLabel = "Voxtral Local"
            case .qwen3ASR:
                wsEndpoint = Constants.Qwen3ASR.wsEndpoint
                sampleRate = Constants.Qwen3ASR.sampleRate
                serverCommand = "qwen3asr-serve"
                serverPackagePath = "qwen3asr"
                modelName = Constants.Qwen3ASR.defaultModel
                port = 8001
                healthEndpoint = Constants.Qwen3ASR.healthEndpoint
                httpRequestTimeout = Constants.Qwen3ASR.httpRequestTimeoutSeconds
                startupTimeout = Constants.Qwen3ASR.serverStartupTimeoutSeconds
                healthPollInterval = Constants.Qwen3ASR.healthPollIntervalSeconds
                uvxSearchPaths = Constants.Qwen3ASR.uvxSearchPaths
                engineLabel = "Qwen3 ASR"
            default:
                return
            }

            localASRService = LocalASRService(
                wsEndpoint: wsEndpoint,
                sampleRate: sampleRate,
                onTranscription: { [weak self] text, isFinal in
                    debugLog("📥 [\(engineLabel)] onTranscription: isFinal=\(isFinal), len=\(text.count)")
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.currentTranscription = self.addLocalPunctuation(text, isFinal: isFinal)
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
                        self?.statusMessage = error
                    }
                },
                onStatusChange: { [weak self] status in
                    DispatchQueue.main.async {
                        self?.statusMessage = status
                    }
                },
                onAudioLevel: { [weak self] level in
                    guard let self else { return }
                    self.audioLevels.removeFirst()
                    self.audioLevels.append(level)
                }
            )
            localServerManager = LocalServerManager(
                serverCommand: serverCommand,
                serverPackagePath: serverPackagePath,
                modelName: modelName,
                port: port,
                healthEndpoint: healthEndpoint,
                httpRequestTimeout: httpRequestTimeout,
                startupTimeout: startupTimeout,
                healthPollInterval: healthPollInterval,
                uvxSearchPaths: uvxSearchPaths,
                onStatusChange: { [weak self] status in
                    guard let self else { return }
                    self.localServerStatus = status
                    if case .running = status {
                        self.isReady = true
                        self.statusMessage = "準備完了 (\(engineLabel)) - \(self.shortcutKey.displayName) キーを押して録音"
                    } else if case .error(let msg) = status {
                        self.statusMessage = msg
                    } else if case .starting(let msg) = status {
                        self.statusMessage = msg
                    }
                }
            )

            modelDownloadManager = ModelDownloadManager(
                modelName: modelName,
                hfSearchPaths: Constants.HuggingFace.hfSearchPaths,
                onStatusChange: { [weak self] status in
                    guard let self else { return }
                    self.modelDownloadStatus = status
                    if case .downloaded = status {
                        self.localServerManager?.start()
                    }
                }
            )
            modelDownloadManager?.checkAndReport()
        }
    }

    func downloadModel() {
        modelDownloadManager?.startDownload()
    }

    func cancelModelDownload() {
        modelDownloadManager?.cancelDownload()
    }

    func deleteModel() {
        localServerManager?.stop()
        modelDownloadManager?.deleteModel()
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
            modelDownloadManager?.deleteModel()
            return
        }
        guard let modelName = engine.hfModelName else { return }
        let sanitized = modelName.replacingOccurrences(of: "/", with: "--")
        let cacheDir = NSHomeDirectory() + "/.cache/huggingface/hub/models--" + sanitized
        guard FileManager.default.fileExists(atPath: cacheDir) else { return }
        do {
            try FileManager.default.removeItem(atPath: cacheDir)
            debugLog("[ModelCache] deleted: \(cacheDir)")
        } catch {
            debugLog("[ModelCache] failed to delete: \(error)")
        }
    }

    func reinitializeAfterEngineChange() async {
        isReady = false
        statusMessage = "エンジンを切り替え中..."
        await requestPermissions()
    }

    private func requestPermissions() async {
        statusMessage = "権限を確認中..."

        guard #available(macOS 26.0, *) else {
            await MainActor.run {
                statusMessage = "macOS 26.0 以上が必要です"
                debugLog("❌ macOS 26.0+ required")
            }
            return
        }

        let micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        guard micStatus else {
            await MainActor.run {
                statusMessage = "マイクの権限が必要です"
            }
            return
        }

        if transcriptionEngine == .voxtralLocal || transcriptionEngine == .qwen3ASR {
            let engineLabel = transcriptionEngine == .voxtralLocal ? "Voxtral Local" : "Qwen3 ASR"
            await MainActor.run {
                if case .running = self.localServerStatus {
                    isReady = true
                    statusMessage = "準備完了 (\(engineLabel)) - \(shortcutKey.displayName) キーを押して録音"
                } else if case .downloaded = self.modelDownloadStatus {
                    statusMessage = "\(engineLabel) サーバーを起動中..."
                    localServerManager?.start()
                } else if case .notDownloaded = self.modelDownloadStatus {
                    statusMessage = "モデルのダウンロードが必要です"
                } else if case .downloading = self.modelDownloadStatus {
                    statusMessage = "モデルをダウンロード中..."
                }
                debugLog("Using \(engineLabel)")
            }
            return
        }

        guard let service = speechAnalyzerService as? SpeechAnalyzerService else {
            await MainActor.run {
                statusMessage = "SpeechAnalyzer の初期化に失敗しました"
                debugLog("❌ SpeechAnalyzer not initialized")
            }
            return
        }

        await MainActor.run {
            statusMessage = "SpeechAnalyzer を初期化中..."
        }
        await service.start()
        await MainActor.run {
            isReady = true
            statusMessage = "準備完了 - \(shortcutKey.displayName) キーを押して録音"
            debugLog("✅ Using Apple SpeechAnalyzer")
        }
    }

    func startRecording() {
        guard #available(macOS 26.0, *) else { return }

        debugLog("🔍 [DEBUG] startRecording called - isReady: \(isReady), isRecording: \(isRecording)")

        guard !isRecording else {
            debugLog("🔍 [DEBUG] startRecording guard failed - already recording")
            return
        }

        if !isReady {
            debugLog("🔍 [DEBUG] startRecording - not ready, showing error")
            errorMessage = "音声認識が初期化されていません"
            floatingPanel?.show()
            return
        }

        errorMessage = nil
        captureForInlinePreview()
        isRecording = true
        currentTranscription = ""
        recordingStartDate = Date()
        debugLog("🎙️ Recording started")
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

        floatingPanel?.show()

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

        startSpeakerVerificationCheck()
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
        guard let audioData = getRecordedAudioDataFromActiveService() else { return }
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
        recordingStartDate = nil

        speakerCheckTimer?.invalidate()
        speakerCheckTimer = nil

        finalResultTimer?.cancel()
        waitingForFinalResult = true
        debugLog("🎙️ Recording stopped - waiting for SpeechAnalyzer final result")
        floatingPanel?.hide()
        switch transcriptionEngine {
        case .deepgram:
            deepgramService?.stopRecording()
        case .voxtralLocal, .qwen3ASR:
            localASRService?.stopRecording()
        case .speechAnalyzer:
            (speechAnalyzerService as? SpeechAnalyzerService)?.stopRecording()
        }
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

        finalResultTimer = DispatchWorkItem { [weak self] in
            guard let self, self.waitingForFinalResult else { return }
            debugLog("⚠️ SpeechAnalyzer timeout - no final result received")
            self.waitingForFinalResult = false
            self.resetInlinePreviewState()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: finalResultTimer!)
    }

    private func handleFinalResult(_ text: String) {
        guard waitingForFinalResult else { return }
        debugLog("✅ Final result received: \(text.count) chars")
        finalResultTimer?.cancel()
        waitingForFinalResult = false

        let processedText = addLocalPunctuation(text)
        if processedText.isEmpty {
            debugLog("⚠️ Final result empty after processing, skipping")
            floatingPanel?.hide()
            return
        }

        let audioData = getRecordedAudioDataFromActiveService()

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.simulatePaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let prev = previousContents {
                        pasteboard.clearContents()
                        pasteboard.setString(prev, forType: .string)
                        debugLog("📋 Restored previous clipboard: \(prev.count) chars")
                    }
                }
            }
        }
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

    private func captureForInlinePreview() {
        capturedTextElement = nil
        inlinePreviewLength = 0
        inlinePreviewActive = false

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else {
            debugLog("🔍 [InlinePreview] No focused element found (AX result: \(result.rawValue))")
            return
        }

        let axElement = element as! AXUIElement

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
        guard let roleStr = role as? String,
              roleStr == "AXTextField" || roleStr == "AXTextArea" || roleStr == "AXSearchField" else {
            debugLog("🔍 [InlinePreview] Focused element is not a text field (role: \(role as? String ?? "unknown"))")
            return
        }

        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard rangeResult == .success, let rangeRef = rangeValue else {
            debugLog("🔍 [InlinePreview] Could not get selected text range")
            return
        }

        var range = CFRange(location: 0, length: 0)
        AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)

        capturedTextElement = axElement
        insertionPointLocation = range.location + range.length
        inlinePreviewActive = true
        debugLog("🔍 [InlinePreview] Captured text element (role: \(roleStr), cursor: \(insertionPointLocation))")
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
        capturedTextElement = nil
        useKeyboardPreview = true
        keyboardPreviewText = ""
        updateKeyboardPreview(text)
        debugLog("🔍 [InlinePreview] Keyboard preview mode activated")
    }

    private func updateKeyboardPreview(_ text: String) {
        let oldText = keyboardPreviewText
        let commonPrefix = oldText.commonPrefix(with: text)
        let charsToDelete = oldText.count - commonPrefix.count
        let newSuffix = String(text.dropFirst(commonPrefix.count))

        let source = CGEventSource(stateID: .privateState)

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
            let source = CGEventSource(stateID: .privateState)
            for _ in 0..<keyboardPreviewText.count {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Delete), keyDown: false) {
                    keyDown.post(tap: .cgAnnotatedSessionEventTap)
                    keyUp.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
            resetInlinePreviewState()
            debugLog("✅ [InlinePreview] Finalized via clipboard paste after keyboard preview cleanup")
            performPaste(text)
            return
        }

        if inlinePreviewActive, let element = capturedTextElement {
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
                (speechAnalyzerService as? SpeechAnalyzerService)?.stopRecording()
            }
        }
        isRecording = false
        recordingStartDate = nil
        currentTranscription = ""
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
        history.removeAll()
        saveHistory()
        debugLog("🗑️ History cleared")
    }

    func removeHistoryItem(_ record: TranscriptionRecord) {
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

    private func getRecordedAudioDataFromActiveService() -> Data? {
        switch transcriptionEngine {
        case .deepgram:
            return deepgramService?.getRecordedAudioData()
        case .voxtralLocal, .qwen3ASR:
            return localASRService?.getRecordedAudioData()
        case .speechAnalyzer:
            guard #available(macOS 26.0, *) else { return nil }
            return (speechAnalyzerService as? SpeechAnalyzerService)?.getRecordedAudioData()
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
            } else {
                RecordingIndicatorView(
                    level: appState.audioLevels.last ?? 0,
                    startDate: appState.recordingStartDate
                )
            }
        }
        .glassEffect(
            isError ? .regular.tint(.orange.opacity(0.3)) : .regular.tint(.red.opacity(0.15)),
            in: .capsule
        )
        .scaleEffect(isVisible ? 1 : 0.6)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

struct RecordingIndicatorView: View {
    let level: Float
    let startDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)

            FluidGlowView(level: level)
                .frame(width: 80, height: 28)

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

struct FluidGlowView: View {
    let level: Float
    @State private var smoothedLevel: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawFluidGlow(context: context, size: size, time: time)
            }
        }
        .onChange(of: level) { _, newLevel in
            withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                let scaled = CGFloat(newLevel) * Constants.Waveform.amplificationFactor
                smoothedLevel = Constants.Waveform.minAmplitude + min(1.0 - Constants.Waveform.minAmplitude, scaled)
            }
        }
    }

    private func drawFluidGlow(context: GraphicsContext, size: CGSize, time: Double) {
        let intensity = smoothedLevel
        let speed = 1.2

        let blobs: [(color: Color, xPhase: Double, yPhase: Double, scale: Double)] = [
            (.red, 0.0, 0.5, 1.0),
            (.orange, 2.1, 1.3, 0.8),
            (.pink, 4.2, 2.6, 0.9),
        ]

        var glowContext = context
        glowContext.addFilter(.blur(radius: 12))
        glowContext.opacity = 0.7 + Double(intensity) * 0.3

        for blob in blobs {
            let baseSize = size.height * (0.5 + Double(intensity) * 0.5) * blob.scale
            let cx = size.width * (0.5 + 0.3 * sin(time * speed + blob.xPhase))
            let cy = size.height * (0.5 + 0.2 * cos(time * speed * 0.8 + blob.yPhase))
            let rect = CGRect(
                x: cx - baseSize * 0.6,
                y: cy - baseSize * 0.5,
                width: baseSize * 1.2,
                height: baseSize
            )
            let gradient = Gradient(colors: [blob.color.opacity(0.8), blob.color.opacity(0)])
            glowContext.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(gradient, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: baseSize * 0.6)
            )
        }

        var coreContext = context
        coreContext.opacity = 0.9
        for blob in blobs {
            let baseSize = size.height * (0.3 + Double(intensity) * 0.3) * blob.scale
            let cx = size.width * (0.5 + 0.25 * sin(time * speed * 1.1 + blob.xPhase + 0.5))
            let cy = size.height * (0.5 + 0.15 * cos(time * speed * 0.9 + blob.yPhase + 0.5))
            let rect = CGRect(
                x: cx - baseSize * 0.5,
                y: cy - baseSize * 0.5,
                width: baseSize,
                height: baseSize
            )
            let gradient = Gradient(colors: [blob.color.opacity(0.6), blob.color.opacity(0)])
            coreContext.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(gradient, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: baseSize * 0.5)
            )
        }
    }
}

struct ErrorIndicatorView: View {
    let message: String
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

