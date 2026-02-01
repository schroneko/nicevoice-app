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
        case .japanese: return "日本語"
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

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var recordingFormat: AVAudioFormat?

    private var detectedLanguage: SupportedLanguage = .japanese
    private var isDetectingLanguage = false
    private var languageDetectionBuffers: [AVAudioPCMBuffer] = []
    private let languageDetectionDuration: TimeInterval = 1.0

    private let onTranscription: (String, Bool) -> Void
    private let onFinalCompletion: ((String) -> Void)?
    private let onError: (String) -> Void
    private let onStatusChange: ((String) -> Void)?
    private let onAudioLevel: ((Float) -> Void)?
    private let onLanguageDetected: ((SupportedLanguage) -> Void)?

    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    init(
        onTranscription: @escaping (String, Bool) -> Void,
        onFinalCompletion: ((String) -> Void)? = nil,
        onError: @escaping (String) -> Void,
        onStatusChange: ((String) -> Void)? = nil,
        onAudioLevel: ((Float) -> Void)? = nil,
        onLanguageDetected: ((SupportedLanguage) -> Void)? = nil
    ) {
        self.onTranscription = onTranscription
        self.onFinalCompletion = onFinalCompletion
        self.onError = onError
        self.onStatusChange = onStatusChange
        self.onAudioLevel = onAudioLevel
        self.onLanguageDetected = onLanguageDetected
    }

    func start() async {
        var transcribers: [SpeechTranscriber] = []
        for language in SupportedLanguage.allCases {
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
        debugLog("✅ SpeechAnalyzer initialized with Japanese and English locales")
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

        isRunning = true
        isDetectingLanguage = true
        audioBuffers = []
        languageDetectionBuffers = []
        detectedLanguage = .japanese

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordingFormat = inputFormat
        debugLog("🔊 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        if inputFormat.sampleRate != analyzerFormat.sampleRate || inputFormat.channelCount != analyzerFormat.channelCount {
            audioConverter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
            debugLog("🔄 Audio converter created (format mismatch)")
        } else {
            debugLog("✅ No audio conversion needed")
        }

        var detectionStartTime: Date?

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRunning else { return }

            if detectionStartTime == nil {
                detectionStartTime = Date()
                debugLog("🎤 [TAP] First buffer received, starting detection timer")
            }

            if let copy = self.copyBuffer(buffer) {
                self.audioBuffers.append(copy)

                if self.isDetectingLanguage {
                    self.languageDetectionBuffers.append(copy)
                    if self.languageDetectionBuffers.count % 10 == 1 {
                        debugLog("🎤 [TAP] Detection buffers: \(self.languageDetectionBuffers.count)")
                    }

                    if let startTime = detectionStartTime,
                       Date().timeIntervalSince(startTime) >= self.languageDetectionDuration
                    {
                        self.isDetectingLanguage = false
                        let buffersForDetection = self.languageDetectionBuffers
                        Task {
                            await self.detectLanguageAndStartTranscription(buffers: buffersForDetection)
                        }
                    }
                } else {
                    self.feedBufferToAnalyzer(copy)
                }
            }

            if let channelData = buffer.floatChannelData {
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength {
                    let sample = channelData[0][i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frameLength))
                let level = min(1.0, rms * 5)
                DispatchQueue.main.async {
                    self.onAudioLevel?(level)
                }
            }
        }

        usleep(100000)

        do {
            try audioEngine.start()
            debugLog("🎙️ SpeechAnalyzer recording started")
        } catch {
            debugLog("❌ Audio engine failed to start: \(error)")
            onError("オーディオエンジンの起動に失敗しました")
            isRunning = false
        }
    }

    func stopRecording() {
        debugLog("🔍 [STOP] stopRecording called - isRunning=\(isRunning), isDetectingLanguage=\(isDetectingLanguage), bufferCount=\(languageDetectionBuffers.count)")
        guard isRunning else {
            debugLog("🔍 [STOP] Early return - isRunning is false")
            return
        }
        isRunning = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        debugLog("🔍 [STOP] After engine stop - isDetectingLanguage=\(isDetectingLanguage), bufferCount=\(languageDetectionBuffers.count)")
        if isDetectingLanguage && !languageDetectionBuffers.isEmpty {
            isDetectingLanguage = false
            let buffersForDetection = languageDetectionBuffers
            debugLog("🔍 [DEBUG] Short recording - starting immediate transcription with \(buffersForDetection.count) buffers")
            Task {
                await detectLanguageAndStartTranscription(buffers: buffersForDetection)
            }
        }

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
        stopRecording()
        analyzer = nil
        transcriber = nil
        audioConverter = nil
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        if let srcFloatData = buffer.floatChannelData, let dstFloatData = copy.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memcpy(dstFloatData[channel], srcFloatData[channel], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    private func detectLanguageAndStartTranscription(buffers: [AVAudioPCMBuffer]) async {
        let language: SupportedLanguage = .japanese
        debugLog("🌍 Using fixed language: \(language.displayName)")

        detectedLanguage = language

        await MainActor.run {
            self.onLanguageDetected?(language)
        }

        startMainTranscription(language: language, initialBuffers: buffers)
    }

    private func detectBestLanguage(japaneseResult: String?, englishResult: String?) -> SupportedLanguage {
        let jaText = japaneseResult ?? ""
        let enText = englishResult ?? ""

        let jaClean = removePunctuation(jaText)
        let enClean = removePunctuation(enText)

        let (jaHiraganaKanji, jaKatakana, _) = calculateCharacterRatios(jaClean)
        let (_, _, enAscii) = calculateCharacterRatios(enClean)

        let jaHasParticles = containsJapaneseParticles(jaClean)
        let jaLength = jaClean.count
        let enLength = enClean.count

        debugLog("🌍 JA: '\(jaClean.prefix(20))' len=\(jaLength), HiraganaKanji=\(jaHiraganaKanji), Katakana=\(jaKatakana), hasParticles=\(jaHasParticles)")
        debugLog("🌍 EN: '\(enClean.prefix(20))' len=\(enLength), ASCII=\(enAscii)")

        if jaClean.isEmpty && enClean.isEmpty {
            return .japanese
        }

        if jaHasParticles && jaHiraganaKanji >= 0.8 {
            debugLog("🌍 Japanese has particles/greeting and high hiragana/kanji -> Japanese")
            return .japanese
        }

        if jaKatakana >= 0.7 && enAscii >= 0.7 {
            debugLog("🌍 High katakana in JA + high ASCII in EN -> English")
            return .english
        }

        if enAscii >= 0.9 && enLength > jaLength * 3 && enLength >= 10 && !jaHasParticles {
            debugLog("🌍 EN is much longer (\(enLength) vs \(jaLength)) with high ASCII (no JA particles) -> English")
            return .english
        }

        if enAscii >= 0.9 && jaHiraganaKanji < 0.3 {
            debugLog("🌍 Very high ASCII in EN + low hiragana/kanji in JA -> English")
            return .english
        }

        if jaHiraganaKanji >= 0.5 && jaKatakana < 0.3 && jaLength >= 2 {
            debugLog("🌍 High hiragana/kanji with low katakana -> Japanese")
            return .japanese
        }

        if enAscii >= 0.7 && enLength >= 3 && jaHiraganaKanji < 0.5 {
            debugLog("🌍 High ASCII ratio in English result with low JA hiragana -> English")
            return .english
        }

        if jaHiraganaKanji >= 0.3 {
            return .japanese
        }

        return .english
    }

    private func containsJapaneseParticles(_ text: String) -> Bool {
        let particles = ["は", "が", "を", "に", "で", "と", "も", "の", "へ", "から", "まで", "より", "など", "か", "ね", "よ", "わ", "さ", "ぞ", "ぜ", "な", "って", "って", "けど", "けれど", "ので", "のに", "ても", "ながら", "たら", "れば", "なら", "ます", "です", "でした", "ました", "ている", "てる", "ください", "ありがとう", "すみません", "こんにちは", "おはよう", "こんばんは"]
        for particle in particles {
            if text.contains(particle) {
                return true
            }
        }
        return false
    }

    private func transcribeBuffersWithLanguage(_ buffers: [AVAudioPCMBuffer], language: SupportedLanguage) async -> String? {
        let transcriber = SpeechTranscriber(
            locale: language.locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        var continuation: AsyncStream<AnalyzerInput>.Continuation?
        let inputStream = AsyncStream<AnalyzerInput> { c in
            continuation = c
        }

        let analyzerTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }

        let resultTask = Task { () -> String? in
            var result: String?
            do {
                for try await transcriptionResult in transcriber.results {
                    result = String(transcriptionResult.text.characters)
                    debugLog("🔍 Detection result (\(language.displayName)): '\(result ?? "")'")
                }
            } catch {
                debugLog("❌ Detection transcription error: \(error)")
            }
            return result
        }

        for buffer in buffers {
            if let converted = convertBufferForAnalyzer(buffer) {
                continuation?.yield(AnalyzerInput(buffer: converted))
            }
        }
        continuation?.finish()

        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        analyzerTask.cancel()

        let result = await resultTask.value
        return result
    }

    private func startMainTranscription(language: SupportedLanguage, initialBuffers: [AVAudioPCMBuffer]) {
        let isShortRecording = !isRunning
        debugLog("🔍 startMainTranscription - isShortRecording=\(isShortRecording), initialBuffers=\(initialBuffers.count)")

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

            if isShortRecording {
                debugLog("🔍 Short recording: finishing input stream immediately after initial buffers")
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

                if !finalText.isEmpty {
                    let textToSend = finalText
                    await MainActor.run {
                        self.onFinalCompletion?(textToSend)
                    }
                }
            } catch {
                await MainActor.run {
                    debugLog("❌ Transcription error: \(error)")
                    self.onError(String(localized: "音声認識エラー: \(error.localizedDescription)"))
                }
            }
        }

        analyzerTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }

        if isShortRecording {
            Task {
                debugLog("🔍 Short recording: calling finalizeAndFinishThroughEndOfInput")
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
                debugLog("🔍 Short recording: finalizeAndFinishThroughEndOfInput completed")
            }
        }
    }

    private func convertBufferForAnalyzer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let analyzerFormat, let converter = audioConverter else {
            return buffer
        }

        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: outputFrameCapacity) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        return status == .error ? nil : convertedBuffer
    }

    private func convertToEnglishPunctuation(_ text: String) -> String {
        text.replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "！", with: "!")
            .replacingOccurrences(of: "？", with: "?")
    }

    private func removePunctuation(_ text: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters
            .union(CharacterSet(charactersIn: "。、！？「」『』（）・"))
        return text.unicodeScalars
            .filter { !punctuation.contains($0) }
            .map { String($0) }
            .joined()
    }

    private func calculateCharacterRatios(_ text: String) -> (hiraganaKanji: Double, katakana: Double, ascii: Double) {
        var hiraganaKanjiCount = 0
        var katakanaCount = 0
        var asciiCount = 0
        var totalCount = 0

        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace { continue }
            totalCount += 1

            let value = scalar.value
            let isHiragana = value >= 0x3040 && value <= 0x309F
            let isKatakana = (value >= 0x30A0 && value <= 0x30FF) || value == 0x30FC
            let isKanji = value >= 0x4E00 && value <= 0x9FFF
            let isAsciiLetter = (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A)

            if isHiragana || isKanji {
                hiraganaKanjiCount += 1
            }
            if isKatakana {
                katakanaCount += 1
            }
            if isAsciiLetter {
                asciiCount += 1
            }
        }

        let hiraganaKanjiRatio = totalCount > 0 ? Double(hiraganaKanjiCount) / Double(totalCount) : 0
        let katakanaRatio = totalCount > 0 ? Double(katakanaCount) / Double(totalCount) : 0
        let asciiRatio = totalCount > 0 ? Double(asciiCount) / Double(totalCount) : 0
        return (hiraganaKanjiRatio, katakanaRatio, asciiRatio)
    }

    private func feedBufferToAnalyzer(_ buffer: AVAudioPCMBuffer) {
        guard let inputContinuation else { return }

        if let converted = convertBufferForAnalyzer(buffer) {
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func getRecordedAudioData() -> Data? {
        guard let format = recordingFormat, !audioBuffers.isEmpty else {
            debugLog("❌ No audio buffers to convert (SpeechAnalyzer)")
            return nil
        }

        let totalFrames = audioBuffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else {
            debugLog("❌ Audio buffers are empty (SpeechAnalyzer)")
            return nil
        }

        debugLog("🎵 Converting \(audioBuffers.count) buffers (\(totalFrames) frames) to WAV (SpeechAnalyzer)")

        let wavHeader = createWAVHeader(
            sampleRate: UInt32(format.sampleRate),
            channels: UInt16(format.channelCount),
            totalFrames: UInt32(totalFrames)
        )

        var audioData = Data()
        audioData.append(wavHeader)

        for buffer in audioBuffers {
            if let floatData = buffer.floatChannelData {
                for frame in 0..<Int(buffer.frameLength) {
                    for channel in 0..<Int(format.channelCount) {
                        let sample = floatData[channel][frame]
                        let clipped = max(-1.0, min(1.0, sample))
                        var intSample = Int16(clipped * Float(Int16.max))
                        audioData.append(Data(bytes: &intSample, count: 2))
                    }
                }
            }
        }

        debugLog("🎵 WAV data created: \(audioData.count) bytes (SpeechAnalyzer)")
        audioBuffers = []
        return audioData
    }

    private func createWAVHeader(sampleRate: UInt32, channels: UInt16, totalFrames: UInt32) -> Data {
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = totalFrames * UInt32(channels) * UInt32(bitsPerSample / 8)
        let fileSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append(contentsOf: "data".utf8)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        return header
    }

    func clearAudioBuffers() {
        audioBuffers = []
    }
}
