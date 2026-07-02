import SwiftUI
import AVFoundation
import AppKit
import Speech

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
    var fillerSettings: FillerSettings = FillerSettings()
    var shortcutMonitoringIssue: ShortcutMonitoringIssue?

    @ObservationIgnored
    @AppStorage("transcriptionEngine") var transcriptionEngineRaw = TranscriptionEngine.defaultEngine.rawValue

    @ObservationIgnored
    @AppStorage("transcriptionLanguageMode") var transcriptionLanguageModeRaw = TranscriptionLanguageMode.defaultMode.rawValue

    var transcriptionEngine: TranscriptionEngine {
        get { TranscriptionEngine.normalized(rawValue: transcriptionEngineRaw) }
        set {
            transcriptionEngineRaw = TranscriptionEngine.normalized(rawValue: newValue.rawValue).rawValue
        }
    }

    var transcriptionLanguageMode: TranscriptionLanguageMode {
        get { TranscriptionLanguageMode(rawValue: transcriptionLanguageModeRaw) ?? .defaultMode }
        set {
            transcriptionLanguageModeRaw = newValue.rawValue
        }
    }

    private var speechAnalyzerService: Any?
    private var localASRService: LocalASRService?
    private(set) var localServerManager: LocalServerManager?
    var localServerStatus: LocalServerStatus = .stopped
    private var localServerRecoveryTask: Task<Void, Never>?
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
    private let textInsertion = TextInsertionController()

    private enum UserDefaultsKey {
        static let usageStats = "usageStats"
        static let fillerSettings = "fillerSettings"
        static let history = "transcriptionHistory"
    }

    init() {
        loadUsageStats()
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

    private func makeOnTranscription(engineLabel: String) -> (String, Bool) -> Void {
        { [weak self] text, isFinal in
            debugLog("📥 [\(engineLabel)] onTranscription: isFinal=\(isFinal), len=\(text.count)")
            DispatchQueue.main.async {
                guard let self else { return }
                self.latestRawTranscription = text
                self.currentTranscription = self.displayTextForPreview(text, isFinal: isFinal)
                if self.isEnrolledSpeakerActive {
                    self.updateInlinePreview(self.currentTranscription)
                }
            }
        }
    }

    private func makeOnFinalCompletion(engineLabel: String) -> (String) -> Void {
        { [weak self] text in
            debugLog("📥 [\(engineLabel)] onFinalCompletion: len=\(text.count)")
            self?.handleFinalResult(text)
        }
    }

    private func makeOnError(engineLabel: String) -> (String) -> Void {
        { [weak self] error in
            debugLog("❌ [\(engineLabel)] error: \(error)")
            DispatchQueue.main.async {
                self?.handleServiceError(error)
            }
        }
    }

    private func makeOnStatusChange() -> (String) -> Void {
        { [weak self] status in
            DispatchQueue.main.async {
                self?.statusMessage = status
            }
        }
    }

    private func makeOnAudioLevel() -> (Float) -> Void {
        { [weak self] level in
            DispatchQueue.main.async {
                guard let self else { return }
                self.audioLevels.removeFirst()
                self.audioLevels.append(level)
            }
        }
    }

    private func makeOnCaptureStarted() -> () -> Void {
        { [weak self] in
            self?.handleCaptureStarted()
        }
    }

    private func setupServices() {
        normalizeTranscriptionEngineSelection()
        setupTranscriptionService()

        if #available(macOS 26.0, *) {
            speechAnalyzerService = SpeechAnalyzerService(
                languageMode: transcriptionLanguageMode,
                onTranscription: makeOnTranscription(engineLabel: "SpeechAnalyzer"),
                onFinalCompletion: makeOnFinalCompletion(engineLabel: "SpeechAnalyzer"),
                onError: makeOnError(engineLabel: "SpeechAnalyzer"),
                onStatusChange: makeOnStatusChange(),
                onAudioLevel: makeOnAudioLevel(),
                onCaptureStarted: makeOnCaptureStarted()
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
            try? await Task.sleep(for: .seconds(1))
            await requestPermissions()
        }
    }

    func setupTranscriptionService() {
        normalizeTranscriptionEngineSelection()
        let languageMode = transcriptionLanguageMode
        if #available(macOS 26.0, *) {
            (speechAnalyzerService as? SpeechAnalyzerService)?.setLanguageMode(languageMode)
        }
        debugLog("setupTranscriptionService: engine=\(transcriptionEngine.rawValue), languageMode=\(languageMode.rawValue)")
        isReady = false
        localServerRecoveryTask?.cancel()
        localServerRecoveryTask = nil
        localASRService?.setWarmCaptureEnabled(false)
        localASRService?.stop()
        localASRService = nil
        localServerManager?.stop()
        localServerManager = nil
        localServerStatus = .stopped
        for engine in TranscriptionEngine.allCases where engine.requiresLocalServer {
            if modelDownloadStatuses[engine] == nil {
                modelDownloadStatuses[engine] = engine.requiresExternalModelDownload ? .notDownloaded : .downloaded
            }
        }

        if transcriptionEngine.requiresLocalServer {
            guard let serverCommand = transcriptionEngine.serverCommandName,
                  let serverModule = transcriptionEngine.localServerModule,
                  let serverPackagePath = transcriptionEngine.localServerPackagePath,
                  let modelName = transcriptionEngine.hfModelName else {
                return
            }
            let engineLabel = transcriptionEngine.displayName
            let endpointFactory: (Int) -> LocalServerEndpoint = { port in
                LocalServerEndpoint(
                    port: port,
                    wsEndpoint: Constants.LocalASR.wsEndpoint(port: port),
                    healthEndpoint: Constants.LocalASR.healthEndpoint(port: port)
                )
            }

            let onTranscription = makeOnTranscription(engineLabel: engineLabel)
            let onFinalCompletion = makeOnFinalCompletion(engineLabel: engineLabel)
            let onStatusChange = makeOnStatusChange()
            let onAudioLevel = makeOnAudioLevel()
            let onCaptureStarted = makeOnCaptureStarted()
            let makeLocalASRService: (LocalServerEndpoint) -> LocalASRService = { endpoint in
                LocalASRService(
                    wsEndpoint: endpoint.wsEndpoint,
                    healthEndpoint: endpoint.healthEndpoint,
                    sampleRate: Constants.LocalASR.sampleRate,
                    languageMode: languageMode,
                    onTranscription: onTranscription,
                    onFinalCompletion: onFinalCompletion,
                    onError: { [weak self] error in
                        debugLog("❌ \(engineLabel) error: \(error)")
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.restartLocalServerAfterLocalASRFailure(engineLabel: engineLabel, reason: error)
                            self.handleServiceError(error)
                        }
                    },
                    onStatusChange: onStatusChange,
                    onAudioLevel: onAudioLevel,
                    onCaptureStarted: onCaptureStarted
                )
            }

            localServerManager = LocalServerManager(
                serverCommand: serverCommand,
                serverModule: serverModule,
                serverPackagePath: serverPackagePath,
                modelName: modelName,
                requestedPort: 0,
                endpointFactory: endpointFactory,
                httpRequestTimeout: Constants.LocalASR.httpRequestTimeoutSeconds,
                startupTimeout: Constants.LocalASR.serverStartupTimeoutSeconds,
                healthPollInterval: Constants.LocalASR.healthPollIntervalSeconds,
                uvxSearchPaths: Constants.LocalASR.uvxSearchPaths,
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
                            self.isReady = false
                            self.statusMessage = String(localized: "\(engineLabel) の接続先を確定中...")
                        }
                    } else if case .error(let msg) = status {
                        self.isReady = false
                        self.localASRService?.setWarmCaptureEnabled(false)
                        self.localASRService?.stop()
                        self.localASRService = nil
                        self.statusMessage = msg
                    } else if case .starting(let msg) = status {
                        self.isReady = false
                        self.localASRService?.setWarmCaptureEnabled(false)
                        self.localASRService?.stop()
                        self.localASRService = nil
                        self.statusMessage = msg
                    } else if case .stopped = status {
                        self.isReady = false
                        self.localASRService?.setWarmCaptureEnabled(false)
                        self.localASRService?.stop()
                        self.localASRService = nil
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
            shortcutKey.usesLongPressBehavior && transcriptionEngine.requiresLocalServer
        localASRService?.setWarmCaptureEnabled(shouldWarmCapture)
    }

    private func restartLocalServerAfterLocalASRFailure(engineLabel: String, reason: String) {
        guard transcriptionEngine.requiresLocalServer else { return }
        guard let manager = localServerManager else { return }
        guard localServerRecoveryTask == nil else {
            debugLog("♻️ \(engineLabel) recovery already in progress")
            return
        }

        debugLog("♻️ Restarting \(engineLabel) server after local ASR failure: \(reason)")
        isReady = false
        statusMessage = String(localized: "\(engineLabel) サーバーを再起動中...")
        localASRService?.setWarmCaptureEnabled(false)
        localASRService?.stop()
        localASRService = nil

        let recoveryTask = Task.detached(priority: .userInitiated) {
            manager.restart()
        }
        localServerRecoveryTask = recoveryTask
        Task { @MainActor [weak self] in
            await recoveryTask.value
            self?.localServerRecoveryTask = nil
        }
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
            await MainActor.run {
                statusMessage = String(localized: "マイク権限を確認中...")
            }
            micStatus = await MicrophonePermission.request()
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
        guard MicrophonePermission.hasAvailableInputDevice else {
            await MainActor.run {
                isReady = false
                statusMessage = String(localized: "マイクが接続されていません")
                debugLog("requestPermissions: no available input device")
            }
            return
        }

        if transcriptionEngine.requiresLocalServer {
            let engineLabel = transcriptionEngine.displayName
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
            let microphoneAuthorized = MicrophonePermission.isGranted
            if microphoneAuthorized || isReady {
                statusMessage = issue.title
            }
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

        guard !MicrophonePermission.isDenied else {
            debugLog("🔍 [DEBUG] startRecording blocked: microphone permission is not authorized")
            isReady = false
            statusMessage = String(localized: "マイクの権限が必要です")
            errorMessage = statusMessage
            floatingPanel?.show()
            Task {
                await requestPermissions()
            }
            return
        }

        guard MicrophonePermission.hasAvailableInputDevice else {
            debugLog("🔍 [DEBUG] startRecording blocked: no available input device")
            isReady = false
            statusMessage = String(localized: "マイクが接続されていません")
            errorMessage = statusMessage
            floatingPanel?.show()
            Task {
                await requestPermissions()
            }
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
        guard transcriptionEngine.requiresLocalServer else { return }
        guard #available(macOS 26.0, *) else { return }
        guard !isDebuggerAttached() else { return }
        guard MicrophonePermission.hasAvailableInputDevice else {
            isReady = false
            statusMessage = String(localized: "マイクが接続されていません")
            errorMessage = statusMessage
            floatingPanel?.show()
            Task {
                await requestPermissions()
            }
            return
        }
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
        case .voxtralLocal, .qwen3ASR:
            localASRService?.stopRecording()
        case .speechAnalyzer:
            (speechAnalyzerService as? SpeechAnalyzerService)?.stopRecording()
        }
        NotificationCenter.default.post(name: .recordingStateChanged, object: nil)

        scheduleProvisionalFinalizationIfNeeded()

        let timeoutSeconds = transcriptionEngine.finalResultTimeoutSeconds
        let timeoutMessage = transcriptionEngine.finalResultTimeoutMessage
        let timeoutEngineName = transcriptionEngine.displayName
        finalResultTimer = DispatchWorkItem { [weak self] in
            guard let self, self.waitingForFinalResult else { return }
            debugLog("⚠️ Final result timeout for \(timeoutEngineName) after \(timeoutSeconds)s")
            self.restartLocalServerAfterLocalASRFailure(engineLabel: timeoutEngineName, reason: "final result timeout after \(timeoutSeconds)s")
            self.handleServiceError(timeoutMessage)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: finalResultTimer!)
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
        let wavData = WAVEncoder.data(samples: samples)
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
                        languageMode: self.transcriptionLanguageMode,
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

    private func addLocalPunctuation(_ text: String, isFinal: Bool = true) -> String {
        let processor = TextProcessor(fillerSettings: fillerSettings)
        return processor.process(text, isFinal: isFinal)
    }

    private func displayTextForPreview(_ text: String, isFinal: Bool) -> String {
        guard isFinal else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return addLocalPunctuation(text, isFinal: true)
    }

    private func scheduleProvisionalFinalizationIfNeeded() {
        guard transcriptionEngine.requiresLocalServer else { return }
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
        textInsertion.paste(text)
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

    @discardableResult
    private func captureForInlinePreview() -> Bool {
        let target = textInsertion.captureFocusedTarget()
        return Self.shouldShowFloatingPanelForRecording(
            hasTextInputTarget: target.hasTextInputTarget,
            spotlightOpen: target.spotlightOpen
        )
    }

    private func updateInlinePreview(_ text: String) {
        textInsertion.updatePreview(text)
    }

    private func finalizeInlinePreview(_ text: String) {
        floatingPanel?.hide()
        guard !text.isEmpty else {
            debugLog("⚠️ No text to paste - text is empty")
            cancelInlinePreview()
            return
        }

        if textInsertion.finalizePreview(text) {
            return
        }

        debugLog("🔍 [InlinePreview] Fallback to clipboard paste")
        performPaste(text)
    }

    private func cancelInlinePreview() {
        textInsertion.cancelPreview()
    }

    func dismissFloatingPanelError() {
        errorMessage = nil
        floatingPanel?.hide()
    }

    func cancelRecording() {
        cancelInlinePreview()
        switch transcriptionEngine {
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
        speakerCheckTimer?.invalidate()
        speakerCheckTimer = nil
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
        if history.count > Constants.History.maxCount {
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

    func recordConversion(characters: Int, tokens: Int) {
        usageStats.recordConversion(characters: characters, tokens: tokens)
        saveUsageStats()
    }

    func updateFillerSettings(_ settings: FillerSettings) {
        fillerSettings = settings
        saveFillerSettings()
    }
}

