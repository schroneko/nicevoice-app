import AVFoundation
import Speech

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

    private let onTranscription: (String, Bool) -> Void
    private let onFinalCompletion: ((String) -> Void)?
    private let onError: (String) -> Void
    private let onStatusChange: ((String) -> Void)?
    private let onAudioLevel: ((Float) -> Void)?

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
        onAudioLevel: ((Float) -> Void)? = nil
    ) {
        self.onTranscription = onTranscription
        self.onFinalCompletion = onFinalCompletion
        self.onError = onError
        self.onStatusChange = onStatusChange
        self.onAudioLevel = onAudioLevel
    }

    func start() async {
        let locale = Locale(identifier: "ja-JP")
        let tempTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        do {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [tempTranscriber]) {
                onStatusChange?("音声認識モデルをダウンロード中...")
                try await downloader.downloadAndInstall()
            }
        } catch {
            debugLog("❌ Model download failed: \(error)")
            onError("モデルのダウンロードに失敗: \(error.localizedDescription)")
            return
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [tempTranscriber])
        onStatusChange?("準備完了")
        debugLog("✅ SpeechAnalyzer initialized with Japanese locale")
        if let format = analyzerFormat {
            debugLog("🔊 Analyzer format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        }
    }

    func startRecording() {
        guard !isRunning else { return }
        guard let analyzerFormat else {
            onError("SpeechAnalyzer が初期化されていません")
            return
        }

        isRunning = true
        audioBuffers = []

        let locale = Locale(identifier: "ja-JP")
        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        guard let transcriber else {
            onError("SpeechTranscriber の作成に失敗しました")
            isRunning = false
            return
        }
        analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzer else {
            onError("SpeechAnalyzer の作成に失敗しました")
            isRunning = false
            return
        }
        debugLog("🔍 [DEBUG] Created new SpeechTranscriber and SpeechAnalyzer")

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

        let inputStream = AsyncStream<AnalyzerInput> { continuation in
            self.inputContinuation = continuation
        }

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            var accumulated = ""
            debugLog("🔍 [DEBUG] Transcription task started, waiting for results...")

            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    debugLog("🔍 [DEBUG] SpeechAnalyzer result: \(text.count) chars (final: \(isFinal))")
                    if isFinal {
                        debugLog("🔍 [DEBUG] SpeechAnalyzer raw text: \(text)")
                    }

                    if isFinal {
                        accumulated += text
                    }

                    let outputText = isFinal ? accumulated : text
                    await MainActor.run {
                        self.onTranscription(outputText, isFinal)
                    }
                }
                let finalText = accumulated
                debugLog("🔍 [DEBUG] Transcription loop ended normally, accumulated: \(finalText.count) chars")
                if !finalText.isEmpty {
                    await MainActor.run {
                        self.onFinalCompletion?(finalText)
                    }
                }
            } catch {
                await MainActor.run {
                    debugLog("❌ Transcription error: \(error)")
                    self.onError("音声認識エラー: \(error.localizedDescription)")
                }
            }
        }

        analyzerTask = Task {
            try await analyzer.start(inputSequence: inputStream)
        }

        var bufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRunning else { return }
            bufferCount += 1
            if bufferCount % 50 == 1 {
                debugLog("🔊 [DEBUG] Audio buffer #\(bufferCount), frames: \(buffer.frameLength)")
            }

            if let copy = self.copyBuffer(buffer) {
                self.audioBuffers.append(copy)
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

            if let converter = self.audioConverter, let targetFormat = self.analyzerFormat {
                let ratio = targetFormat.sampleRate / inputFormat.sampleRate
                let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                    if bufferCount == 1 {
                        debugLog("❌ [DEBUG] Failed to create output buffer")
                    }
                    return
                }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .error {
                    if bufferCount == 1 {
                        debugLog("❌ [DEBUG] Conversion error: \(error?.localizedDescription ?? "unknown")")
                    }
                    return
                }

                if bufferCount == 1 {
                    debugLog("🔊 [DEBUG] Converted buffer: \(convertedBuffer.frameLength) frames, format: \(convertedBuffer.format)")
                }
                self.inputContinuation?.yield(AnalyzerInput(buffer: convertedBuffer))
            } else {
                self.inputContinuation?.yield(AnalyzerInput(buffer: buffer))
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
        guard isRunning else { return }
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
