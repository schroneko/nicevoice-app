import AVFoundation
import Foundation

final class LocalASRService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var isAudioCaptureActive = false
    private var warmCaptureEnabled = false
    private var isRunning = false
    private var receiveTask: Task<Void, Never>?
    private var sessionReady = false
    private var pendingStop = false
    private var pendingStopAfterAudioCapture = false
    private var deferStreamingUntilConfirmation = false
    private var streamingConfirmed = false
    private var captureWatchdogTask: Task<Void, Never>?
    private var lastAudioCaptureAt: Date?
    private var hasCapturedAudioForCurrentRecording = false

    private let recordedAudio = RecordedAudioStore(label: "voxmlx")
    private var pendingPCMChunks: [Data] = []

    private var accumulatedText = ""

    private let wsEndpoint: String
    private let healthEndpoint: String
    private let sampleRate: Double
    private let languageMode: TranscriptionLanguageMode
    private let onTranscription: (String, Bool) -> Void
    private let onFinalCompletion: ((String) -> Void)?
    private let onError: (String) -> Void
    private let onStatusChange: ((String) -> Void)?
    private let onAudioLevel: ((Float) -> Void)?
    private let onCaptureStarted: (() -> Void)?

    private lazy var voxtralFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: self.sampleRate, channels: 1, interleaved: true)!
    }()

    init(
        wsEndpoint: String,
        healthEndpoint: String,
        sampleRate: Double,
        languageMode: TranscriptionLanguageMode = .defaultMode,
        onTranscription: @escaping (String, Bool) -> Void,
        onFinalCompletion: ((String) -> Void)? = nil,
        onError: @escaping (String) -> Void,
        onStatusChange: ((String) -> Void)? = nil,
        onAudioLevel: ((Float) -> Void)? = nil,
        onCaptureStarted: (() -> Void)? = nil
    ) {
        self.wsEndpoint = wsEndpoint
        self.healthEndpoint = healthEndpoint
        self.sampleRate = sampleRate
        self.languageMode = languageMode
        self.onTranscription = onTranscription
        self.onFinalCompletion = onFinalCompletion
        self.onError = onError
        self.onStatusChange = onStatusChange
        self.onAudioLevel = onAudioLevel
        self.onCaptureStarted = onCaptureStarted
    }

    func startRecording(deferStreamingUntilConfirmation: Bool = false) {
        guard !isRunning else { return }
        guard MicrophonePermission.hasAvailableInputDevice else {
            debugLog("❌ voxmlx recording blocked: no available input device")
            onError(String(localized: "マイクが接続されていません"))
            onStatusChange?(String(localized: "マイクが接続されていません"))
            return
        }

        isRunning = true
        sessionReady = false
        pendingStop = false
        pendingStopAfterAudioCapture = false
        self.deferStreamingUntilConfirmation = deferStreamingUntilConfirmation
        streamingConfirmed = !deferStreamingUntilConfirmation
        accumulatedText = ""
        recordedAudio.clear()
        pendingPCMChunks = []
        hasCapturedAudioForCurrentRecording = false

        ensureAudioCaptureRunning(notifyCaptureStarted: true)
        startCaptureWatchdog()
        if streamingConfirmed {
            connectWebSocket()
        } else {
            debugLog("⏳ voxmlx capture started in preflight mode")
        }
    }

    func confirmRecordingStart() {
        guard isRunning else { return }
        guard deferStreamingUntilConfirmation else { return }
        guard !streamingConfirmed else { return }

        deferStreamingUntilConfirmation = false
        streamingConfirmed = true
        debugLog("✅ voxmlx preflight confirmed, connecting WebSocket")
        connectWebSocket()
    }

    func stopRecording() {
        guard isRunning else { return }
        guard !waitForFirstAudioBufferBeforeStopping() else { return }
        finishStopRecording()
    }

    private func waitForFirstAudioBufferBeforeStopping() -> Bool {
        guard isAudioCaptureActive else { return false }
        guard !hasCapturedAudioForCurrentRecording else { return false }
        guard !pendingStopAfterAudioCapture else { return true }

        pendingStopAfterAudioCapture = true
        debugLog("⏳ voxmlx: waiting for first microphone buffer before stopping")
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Audio.stopDelayUntilFirstBufferSeconds) { [weak self] in
            guard let self else { return }
            guard self.pendingStopAfterAudioCapture else { return }
            self.pendingStopAfterAudioCapture = false
            self.finishStopRecording()
        }
        return true
    }

    private func finishStopRecording() {
        guard isRunning else { return }
        isRunning = false
        pendingStopAfterAudioCapture = false
        cancelCaptureWatchdog()

        if !warmCaptureEnabled {
            stopAudioCapture()
        }

        if sessionReady {
            sendEndAudio()
        } else {
            pendingStop = true
            debugLog("⏳ voxmlx: session not ready yet, deferring input_audio_buffer.commit")
        }

        debugLog("🎙️ voxmlx recording stopped")
    }

    func stop() {
        isRunning = false
        pendingStop = false
        pendingStopAfterAudioCapture = false
        deferStreamingUntilConfirmation = false
        streamingConfirmed = false
        cancelCaptureWatchdog()
        pendingPCMChunks = []
        recordedAudio.clear()
        hasCapturedAudioForCurrentRecording = false
        if !warmCaptureEnabled {
            stopAudioCapture()
        }
        disconnectWebSocket()
    }

    func setWarmCaptureEnabled(_ enabled: Bool) {
        if warmCaptureEnabled == enabled {
            if enabled {
                ensureAudioCaptureRunning(notifyCaptureStarted: false)
            }
            return
        }

        warmCaptureEnabled = enabled
        if enabled {
            debugLog("🔥 voxmlx warm capture enabled")
            ensureAudioCaptureRunning(notifyCaptureStarted: false)
        } else {
            debugLog("🧊 voxmlx warm capture disabled")
            if !isRunning {
                stopAudioCapture()
            }
        }
    }

    func getRecordedAudioData(consuming: Bool = true) -> Data? {
        recordedAudio.wavData(consuming: consuming)
    }

    func clearAudioBuffers() {
        recordedAudio.clear()
    }

    func checkServerHealth() async -> Bool {
        guard let url = URL(string: healthEndpoint) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.LocalASR.httpRequestTimeoutSeconds
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func connectWebSocket() {
        guard let url = URL(string: wsEndpoint) else {
            onError("Invalid voxmlx-serve WebSocket URL")
            return
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        debugLog("🔌 voxmlx WebSocket connecting to \(url)")
        onStatusChange?(String(localized: "voxmlx に接続中..."))

        startReceiving()
    }

    private func disconnectWebSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        sessionReady = false
        deferStreamingUntilConfirmation = false
        streamingConfirmed = false
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let webSocketTask = self.webSocketTask else { break }

                do {
                    let message = try await webSocketTask.receive()
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        debugLog("❌ voxmlx WebSocket receive error: \(error)")
                        await MainActor.run {
                            self.onError(String(localized: "WebSocket エラー: \(error.localizedDescription)"))
                        }
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            debugLog("⚠️ voxmlx: Failed to parse message: \(text.prefix(100))")
            return
        }

        switch type {
        case "session.created":
            debugLog("✅ voxmlx session created")
            sessionReady = true
            sendSessionUpdate()
            flushPendingChunks()
            DispatchQueue.main.async {
                self.onStatusChange?(String(localized: "voxmlx 接続完了"))
            }

        case "session.updated":
            debugLog("✅ voxmlx session updated")

        case "response.audio_transcript.delta":
            if let deltaText = json["delta"] as? String {
                accumulatedText += deltaText
                let currentText = accumulatedText
                DispatchQueue.main.async {
                    self.onTranscription(currentText, false)
                }
            }

        case "response.audio_transcript.done":
            let finalText = (json["text"] as? String) ?? accumulatedText
            debugLog("✅ voxmlx transcription done: \(finalText.count) chars")
            DispatchQueue.main.async {
                self.onTranscription(finalText, true)
                self.onFinalCompletion?(finalText)
            }
            disconnectWebSocket()

        case "error":
            let errorMessage = (json["message"] as? String) ?? String(localized: "voxmlx エラー")
            debugLog("❌ voxmlx error: \(errorMessage)")
            DispatchQueue.main.async {
                self.onError(errorMessage)
            }
            disconnectWebSocket()

        default:
            debugLog("⚠️ voxmlx unknown message type: \(type)")
        }
    }

    private func flushPendingChunks() {
        debugLog("📤 voxmlx: flushing \(pendingPCMChunks.count) buffered chunks")
        for chunk in pendingPCMChunks {
            let base64 = chunk.base64EncodedString()
            let message: [String: Any] = [
                "type": "input_audio_buffer.append",
                "audio": base64
            ]
            sendJSON(message)
        }
        pendingPCMChunks = []

        if pendingStop {
            pendingStop = false
            sendEndAudio()
        }
    }

    private func sendSessionUpdate() {
        var transcription: [String: Any] = [
            "allowed_languages": languageMode.allowedLanguageCodes
        ]
        if let language = languageMode.singleLanguageCode {
            transcription["language"] = language
        }
        let message: [String: Any] = [
            "type": "session.update",
            "session": [
                "input_audio_transcription": transcription
            ]
        ]
        sendJSON(message)
    }

    private func sendAudioChunk(_ pcmData: Data) {
        if sessionReady {
            let base64 = pcmData.base64EncodedString()
            let message: [String: Any] = [
                "type": "input_audio_buffer.append",
                "audio": base64
            ]
            sendJSON(message)
        } else {
            pendingPCMChunks.append(pcmData)
        }
    }

    private func sendEndAudio() {
        let message: [String: Any] = [
            "type": "input_audio_buffer.commit",
            "final": true
        ]
        sendJSON(message)
        debugLog("📤 voxmlx: sent input_audio_buffer.commit")
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask?.send(.string(text)) { error in
            if let error {
                debugLog("❌ voxmlx WebSocket send error: \(error)")
            }
        }
    }

    private func ensureAudioCaptureRunning(notifyCaptureStarted: Bool) {
        if isAudioCaptureHealthy {
            if notifyCaptureStarted {
                DispatchQueue.main.async {
                    self.onCaptureStarted?()
                }
            }
            return
        }

        stopAudioCapture()
        startAudioCapture(notifyCaptureStarted: notifyCaptureStarted)
    }

    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        isAudioCaptureActive = false
        lastAudioCaptureAt = nil
    }

    private func startAudioCapture(notifyCaptureStarted: Bool) {
        guard MicrophonePermission.hasAvailableInputDevice else {
            debugLog("❌ voxmlx audio capture blocked: no available input device")
            onError(String(localized: "マイクが接続されていません"))
            isAudioCaptureActive = false
            isRunning = false
            return
        }

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordedAudio.setFormat(inputFormat)
        debugLog("🔊 voxmlx input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        audioConverter = AVAudioConverter(from: inputFormat, to: voxtralFormat)

        inputNode.installTap(onBus: 0, bufferSize: Constants.Audio.realtimeBufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            self.lastAudioCaptureAt = Date()
            let stillRecording = self.isRunning

            if stillRecording {
                self.hasCapturedAudioForCurrentRecording = true
                self.recordedAudio.append(copyOf: buffer)
                if let converted = self.audioConverter?.convertBuffer(buffer, to: self.voxtralFormat) {
                    self.sendAudioChunk(converted.int16PCMData)
                }
                if self.pendingStopAfterAudioCapture {
                    self.pendingStopAfterAudioCapture = false
                    DispatchQueue.main.async {
                        self.finishStopRecording()
                    }
                }
            }

            if let level = buffer.meterLevel {
                DispatchQueue.main.async {
                    self.onAudioLevel?(level)
                }
            }
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isAudioCaptureActive = true
            lastAudioCaptureAt = nil
            debugLog("🎙️ voxmlx audio capture started")
            if notifyCaptureStarted {
                DispatchQueue.main.async {
                    self.onCaptureStarted?()
                }
            }
        } catch {
            debugLog("❌ voxmlx audio engine failed to start: \(error)")
            onError(String(localized: "オーディオエンジンの起動に失敗しました"))
            isAudioCaptureActive = false
            isRunning = false
        }
    }

    private var isAudioCaptureHealthy: Bool {
        guard isAudioCaptureActive else { return false }
        guard audioEngine?.isRunning == true else { return false }
        guard let lastAudioCaptureAt else { return false }
        return Date().timeIntervalSince(lastAudioCaptureAt) <= Constants.Audio.captureFreshnessThresholdSeconds
    }

    private func startCaptureWatchdog() {
        cancelCaptureWatchdog()
        captureWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.Audio.captureStartupTimeoutSeconds))
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.isRunning else { return }
            guard !self.hasCapturedAudioForCurrentRecording else { return }
            self.handleMissingAudioCapture()
        }
    }

    private func cancelCaptureWatchdog() {
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
    }

    private func handleMissingAudioCapture() {
        debugLog("❌ voxmlx audio capture stalled before receiving microphone input")
        let shouldResumeWarmCapture = warmCaptureEnabled
        isRunning = false
        pendingStop = false
        pendingStopAfterAudioCapture = false
        deferStreamingUntilConfirmation = false
        streamingConfirmed = false
        pendingPCMChunks = []
        recordedAudio.clear()
        hasCapturedAudioForCurrentRecording = false
        cancelCaptureWatchdog()
        disconnectWebSocket()
        stopAudioCapture()
        if shouldResumeWarmCapture {
            ensureAudioCaptureRunning(notifyCaptureStarted: false)
        }
        DispatchQueue.main.async {
            self.onError(String(localized: "マイク入力を取得できませんでした。マイク権限と入力デバイスを確認してから、もう一度試してください"))
        }
    }

}
