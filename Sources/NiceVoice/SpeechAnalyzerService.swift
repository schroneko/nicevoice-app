import AVFoundation
import Speech

enum SupportedLanguage: String, CaseIterable {
    case japanese = "ja-JP"
    case english = "en-US"

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayName: String {
        switch self {
        case .japanese: return String(localized: "日本語")
        case .english: return "English"
        }
    }
}

@available(macOS 26.0, *)
final class SpeechAnalyzerService {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var isRunning = false
    private var transcriptionTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Error>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    private let recordedAudio = RecordedAudioStore(label: "SpeechAnalyzer")

    private var languageMode: TranscriptionLanguageMode

    private let onTranscription: (String, Bool) -> Void
    private let onFinalCompletion: ((String) -> Void)?
    private let onError: (String) -> Void
    private let onStatusChange: ((String) -> Void)?
    private let onAudioLevel: ((Float) -> Void)?
    private let onCaptureStarted: (() -> Void)?

    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    init(
        languageMode: TranscriptionLanguageMode = .defaultMode,
        onTranscription: @escaping (String, Bool) -> Void,
        onFinalCompletion: ((String) -> Void)? = nil,
        onError: @escaping (String) -> Void,
        onStatusChange: ((String) -> Void)? = nil,
        onAudioLevel: ((Float) -> Void)? = nil,
        onCaptureStarted: (() -> Void)? = nil
    ) {
        self.languageMode = languageMode
        self.onTranscription = onTranscription
        self.onFinalCompletion = onFinalCompletion
        self.onError = onError
        self.onStatusChange = onStatusChange
        self.onAudioLevel = onAudioLevel
        self.onCaptureStarted = onCaptureStarted
    }

    func setLanguageMode(_ mode: TranscriptionLanguageMode) {
        languageMode = mode
    }

    func start() async {
        var transcribers: [SpeechTranscriber] = []
        for language in languageMode.speechAnalyzerLanguages {
            let transcriber = SpeechTranscriber(
                locale: language.locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            transcribers.append(transcriber)
        }

        do {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: transcribers) {
                onStatusChange?(String(localized: "音声認識モデルをダウンロード中..."))
                try await downloader.downloadAndInstall()
            }
        } catch {
            debugLog("❌ Model download failed: \(error)")
            onError(String(localized: "モデルのダウンロードに失敗: \(error.localizedDescription)"))
            return
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: transcribers)
        onStatusChange?(String(localized: "準備完了"))
        debugLog("✅ SpeechAnalyzer initialized with language mode \(languageMode.rawValue)")
        if let format = analyzerFormat {
            debugLog("🔊 Analyzer format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        }
    }

    func startRecording() {
        guard !isRunning else { return }
        guard let analyzerFormat else {
            onError(String(localized: "SpeechAnalyzer が初期化されていません"))
            return
        }
        guard MicrophonePermission.hasAvailableInputDevice else {
            debugLog("SpeechAnalyzer recording blocked: no available input device")
            onError(String(localized: "マイクが接続されていません"))
            onStatusChange?(String(localized: "マイクが接続されていません"))
            return
        }

        isRunning = true
        recordedAudio.clear()

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordedAudio.setFormat(inputFormat)
        debugLog("🔊 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        if inputFormat.sampleRate != analyzerFormat.sampleRate || inputFormat.channelCount != analyzerFormat.channelCount {
            audioConverter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
            debugLog("🔄 Audio converter created (format mismatch)")
        } else {
            debugLog("✅ No audio conversion needed")
        }

        startMainTranscription(language: languageMode.defaultSpeechAnalyzerLanguage, initialBuffers: [])

        inputNode.installTap(onBus: 0, bufferSize: Constants.Audio.bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRunning else { return }

            if let copy = self.recordedAudio.append(copyOf: buffer) {
                self.feedBufferToAnalyzer(copy)
            }

            if let level = buffer.meterLevel {
                DispatchQueue.main.async {
                    self.onAudioLevel?(level)
                }
            }
        }

        do {
            try audioEngine.start()
            debugLog("🎙️ SpeechAnalyzer recording started (immediate transcription)")
            DispatchQueue.main.async {
                self.onCaptureStarted?()
            }
        } catch {
            debugLog("❌ Audio engine failed to start: \(error)")
            onError(String(localized: "オーディオエンジンの起動に失敗しました"))
            isRunning = false
        }
    }

    func stopRecording() {
        debugLog("🔍 [STOP] stopRecording called - isRunning=\(isRunning)")
        guard isRunning else {
            debugLog("🔍 [STOP] Early return - isRunning is false")
            return
        }
        isRunning = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        inputContinuation?.finish()
        inputContinuation = nil

        let taskToCancel = transcriptionTask
        let analyzerToCancel = analyzerTask
        let analyzerToFinalize = analyzer

        Task {
            debugLog("🔍 [DEBUG] Calling finalizeAndFinishThroughEndOfInput...")
            try? await analyzerToFinalize?.finalizeAndFinishThroughEndOfInput()
            debugLog("🔍 [DEBUG] finalizeAndFinishThroughEndOfInput completed")

            try? await Task.sleep(for: .seconds(5))

            if taskToCancel != nil {
                debugLog("⚠️ Transcription task did not finish naturally, cancelling")
                taskToCancel?.cancel()
            }
            if analyzerToCancel != nil {
                analyzerToCancel?.cancel()
            }
        }

        debugLog("🎙️ SpeechAnalyzer recording stopped")
    }

    func stop() {
        isRunning = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputContinuation?.finish()
        inputContinuation = nil
        transcriptionTask?.cancel()
        analyzerTask?.cancel()
        transcriptionTask = nil
        analyzerTask = nil
        analyzer = nil
        transcriber = nil
        audioConverter = nil
    }

    private func startMainTranscription(language: SupportedLanguage, initialBuffers: [AVAudioPCMBuffer]) {
        debugLog("🔍 startMainTranscription - initialBuffers=\(initialBuffers.count)")

        transcriber = SpeechTranscriber(
            locale: language.locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        guard let transcriber else {
            onError(String(localized: "SpeechTranscriber の作成に失敗しました"))
            return
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzer else {
            onError(String(localized: "SpeechAnalyzer の作成に失敗しました"))
            return
        }

        debugLog("🔍 Started main transcription with \(language.displayName)")

        let inputStream = AsyncStream<AnalyzerInput> { continuation in
            self.inputContinuation = continuation

            for buffer in initialBuffers {
                if let converted = self.convertBufferForAnalyzer(buffer) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }

            if !self.isRunning {
                continuation.finish()
                self.inputContinuation = nil
            }
        }

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            var finalText = ""
            var lastVolatileText = ""

            do {
                var resultIndex = 0
                for try await result in transcriber.results {
                    resultIndex += 1
                    var text = String(result.text.characters)
                    let isFinal = result.isFinal
                    debugLog("📝 [RESULT #\(resultIndex)] isFinal=\(isFinal), len=\(text.count), text='\(text.prefix(80))'")

                    if language == .english {
                        text = self.convertToEnglishPunctuation(text)
                    }

                    if isFinal {
                        finalText += text
                        debugLog("🔴 [FINAL] Received final result: '\(text.prefix(50))...' (len=\(text.count), totalLen=\(finalText.count))")
                        let textToSend = finalText
                        await MainActor.run {
                            self.onTranscription(textToSend, true)
                        }
                    } else {
                        let fullText = finalText + text
                        if fullText != lastVolatileText {
                            lastVolatileText = fullText
                            let textToSend = fullText
                            await MainActor.run {
                                self.onTranscription(textToSend, false)
                            }
                        }
                    }
                }

                let textToSend = finalText
                await MainActor.run {
                    self.onFinalCompletion?(textToSend)
                }
            } catch {
                if error is CancellationError {
                    debugLog("🔍 Transcription task cancelled")
                    return
                }
                await MainActor.run {
                    debugLog("❌ Transcription error: \(error)")
                    self.onError(String(localized: "音声認識エラー: \(error.localizedDescription)"))
                }
            }
        }

        analyzerTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }

        if !isRunning {
            Task {
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
        }
    }

    private func convertBufferForAnalyzer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let analyzerFormat, let converter = audioConverter else {
            return buffer
        }
        return converter.convertBuffer(buffer, to: analyzerFormat)
    }

    private func convertToEnglishPunctuation(_ text: String) -> String {
        text.replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "！", with: "!")
            .replacingOccurrences(of: "？", with: "?")
    }

    private func feedBufferToAnalyzer(_ buffer: AVAudioPCMBuffer) {
        guard let inputContinuation else { return }

        if let converted = convertBufferForAnalyzer(buffer) {
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func getRecordedAudioData(consuming: Bool = true) -> Data? {
        recordedAudio.wavData(consuming: consuming)
    }

    func clearAudioBuffers() {
        recordedAudio.clear()
    }
}
