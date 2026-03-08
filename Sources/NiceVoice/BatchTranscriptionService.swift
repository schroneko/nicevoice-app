import AVFoundation
import Speech
import UserNotifications

struct BatchTranscriptionItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: BatchTranscriptionStatus = .pending
    var progress: Double = 0
    var result: String = ""
    var error: String?

    var fileName: String {
        url.lastPathComponent
    }
}

enum BatchTranscriptionStatus: String {
    case pending
    case processing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .pending: return String(localized: "待機中")
        case .processing: return String(localized: "処理中")
        case .completed: return String(localized: "完了")
        case .failed: return String(localized: "失敗")
        }
    }
}

@available(macOS 26.0, *)
final class BatchTranscriptionService: @unchecked Sendable {
    static let shared = BatchTranscriptionService()

    private var processingTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "com.nicevoice.batch", qos: .userInitiated)

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .sound])
            debugLog("Notification permission granted")
        } catch {
            debugLog("Notification permission denied: \(error)")
        }
    }

    func transcribeFile(
        at url: URL,
        engine: TranscriptionEngine = .speechAnalyzer,
        onProgress: @escaping (Double) -> Void,
        onStatusChange: @escaping (String) -> Void
    ) async throws -> String {
        guard AuthManager.shared.verifyAuthIntegrity() else {
            throw NSError(domain: "NiceVoice", code: 401, userInfo: [NSLocalizedDescriptionKey: String(localized: "サブスクリプションが必要です")])
        }
        switch engine {
        case .speechAnalyzer:
            return try await transcribeWithSpeechAnalyzer(
                at: url,
                onProgress: onProgress,
                onStatusChange: onStatusChange
            )
        case .voxtralLocal:
            return try await transcribeWithLocalASR(
                at: url,
                wsEndpoint: Constants.VoxtralLocal.wsEndpoint,
                sampleRate: Constants.VoxtralLocal.sampleRate,
                onProgress: onProgress,
                onStatusChange: onStatusChange
            )
        case .qwen3ASR:
            return try await transcribeWithLocalASR(
                at: url,
                wsEndpoint: Constants.Qwen3ASR.wsEndpoint,
                sampleRate: Constants.Qwen3ASR.sampleRate,
                onProgress: onProgress,
                onStatusChange: onStatusChange
            )
        case .deepgram:
            guard let apiKey = KeychainStorage.shared.loadString(account: StorageKey.deepgramApiKey.rawValue),
                  !apiKey.isEmpty else {
                throw DeepgramError.noApiKey
            }
            return try await DeepgramService.transcribeBatch(
                fileURL: url,
                apiKey: apiKey,
                onProgress: onProgress,
                onStatusChange: onStatusChange
            )
        }
    }

    func transcribeWithSpeechAnalyzer(
        at url: URL,
        onProgress: @escaping (Double) -> Void,
        onStatusChange: @escaping (String) -> Void
    ) async throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        onStatusChange(String(localized: "ファイルを読み込み中..."))
        onProgress(0.05)

        let audioFile = try AVAudioFile(forReading: url)
        let processingFormat = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)

        debugLog("Audio file: \(url.lastPathComponent), format: \(processingFormat.sampleRate)Hz, \(processingFormat.channelCount)ch, frames: \(totalFrames)")

        onStatusChange(String(localized: "音声認識モデルを準備中..."))
        onProgress(0.1)

        var transcribers: [SpeechTranscriber] = []
        for language in SupportedLanguage.allCases {
            let transcriber = SpeechTranscriber(
                locale: language.locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            transcribers.append(transcriber)
        }

        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: transcribers) {
            onStatusChange(String(localized: "音声認識モデルをダウンロード中..."))
            try await downloader.downloadAndInstall()
        }

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: transcribers)
        guard let targetFormat = analyzerFormat else {
            throw BatchTranscriptionError.formatNotAvailable
        }

        debugLog("Analyzer format: \(targetFormat.sampleRate)Hz, \(targetFormat.channelCount)ch")

        let analyzer = SpeechAnalyzer(modules: transcribers)
        debugLog("SpeechAnalyzer created")

        onStatusChange(String(localized: "音声を処理中..."))
        onProgress(0.2)

        let bufferSize: AVAudioFrameCount = 4096
        var converter: AVAudioConverter?

        if processingFormat.sampleRate != targetFormat.sampleRate || processingFormat.channelCount != targetFormat.channelCount {
            converter = AVAudioConverter(from: processingFormat, to: targetFormat)
            debugLog("Audio converter created for format conversion")
        }

        let inputStream = AsyncStream<AnalyzerInput> { continuation in
            queue.async { [weak self] in
                guard self != nil else {
                    continuation.finish()
                    return
                }

                var framesRead: AVAudioFrameCount = 0

                while framesRead < totalFrames {
                    let framesToRead = min(bufferSize, totalFrames - framesRead)

                    guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: framesToRead) else {
                        debugLog("Failed to create read buffer")
                        break
                    }

                    do {
                        try audioFile.read(into: buffer)
                    } catch {
                        debugLog("Failed to read audio file: \(error)")
                        break
                    }

                    if buffer.frameLength == 0 {
                        break
                    }

                    var outputBuffer: AVAudioPCMBuffer

                    if let conv = converter {
                        let ratio = targetFormat.sampleRate / processingFormat.sampleRate
                        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

                        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
                            debugLog("Failed to create conversion buffer")
                            break
                        }

                        var error: NSError?
                        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }

                        let status = conv.convert(to: converted, error: &error, withInputFrom: inputBlock)

                        if status == .error {
                            debugLog("Conversion error: \(error?.localizedDescription ?? "unknown")")
                            break
                        }

                        outputBuffer = converted
                    } else {
                        outputBuffer = buffer
                    }

                    continuation.yield(AnalyzerInput(buffer: outputBuffer))

                    framesRead += buffer.frameLength

                    let progress = Double(framesRead) / Double(totalFrames)
                    DispatchQueue.main.async {
                        onProgress(0.2 + progress * 0.6)
                    }
                }

                continuation.finish()
                debugLog("Finished reading audio file (\(framesRead) frames)")
            }
        }

        debugLog("Starting analyzer task...")

        var transcriptionResult = ""

        let resultsTask = Task {
            debugLog("Waiting for transcriber results...")
            await withTaskGroup(of: String.self) { group in
                for transcriber in transcribers {
                    group.addTask {
                        var segmentResult = ""
                        do {
                            for try await result in transcriber.results {
                                let text = String(result.text.characters)
                                debugLog("Received result: \(text.count) chars, final: \(result.isFinal), text: \(text)")
                                if result.isFinal {
                                    segmentResult += text
                                    debugLog("Batch transcription segment: \(text.count) chars")
                                }
                            }
                        } catch {
                            debugLog("Transcriber results error: \(error)")
                        }
                        return segmentResult
                    }
                }
                for await result in group {
                    transcriptionResult += result
                }
            }
            debugLog("All transcriber results loops ended")
        }

        let analyzerTask = Task {
            debugLog("analyzer.start() called")
            try await analyzer.start(inputSequence: inputStream)
            debugLog("analyzer.start() completed")
        }

        onStatusChange(String(localized: "文字起こし中..."))

        try await analyzerTask.value
        debugLog("analyzerTask completed, calling finalize...")

        onProgress(0.9)
        onStatusChange(String(localized: "完了処理中..."))

        try await analyzer.finalizeAndFinishThroughEndOfInput()
        debugLog("finalizeAndFinishThroughEndOfInput completed")

        await resultsTask.value
        debugLog("resultsTask completed")

        onProgress(1.0)
        onStatusChange(String(localized: "完了"))

        debugLog("Batch transcription completed: \(transcriptionResult.count) chars, text: \(transcriptionResult)")

        return transcriptionResult
    }

    func sendCompletionNotification(fileName: String, success: Bool, charCount: Int = 0) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = success ? String(localized: "文字起こし完了") : String(localized: "文字起こし失敗")
        content.body = success
            ? String(localized: "\(fileName) の文字起こしが完了しました（\(charCount)文字）")
            : String(localized: "\(fileName) の処理中にエラーが発生しました")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            debugLog("Notification sent: \(content.title)")
        } catch {
            debugLog("Failed to send notification: \(error)")
        }
    }

    private func transcribeWithLocalASR(
        at url: URL,
        wsEndpoint: String,
        sampleRate: Double,
        onProgress: @escaping (Double) -> Void,
        onStatusChange: @escaping (String) -> Void
    ) async throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        onStatusChange(String(localized: "ファイルを読み込み中..."))
        onProgress(0.05)

        let audioFile = try AVAudioFile(forReading: url)
        let processingFormat = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)

        debugLog("Audio file: \(url.lastPathComponent), format: \(processingFormat.sampleRate)Hz, \(processingFormat.channelCount)ch, frames: \(totalFrames)")

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw BatchTranscriptionError.formatNotAvailable
        }

        var converter: AVAudioConverter?
        if processingFormat.sampleRate != sampleRate || processingFormat.channelCount != 1 {
            converter = AVAudioConverter(from: processingFormat, to: targetFormat)
            debugLog("Audio converter created: \(processingFormat.sampleRate)Hz \(processingFormat.channelCount)ch -> \(sampleRate)Hz 1ch")
        }

        onStatusChange(String(localized: "サーバーに接続中..."))
        onProgress(0.1)

        guard let wsURL = URL(string: wsEndpoint) else {
            throw BatchTranscriptionError.analyzerInitFailed
        }

        let wsTask = URLSession.shared.webSocketTask(with: wsURL)
        wsTask.resume()

        let createdMsg = try await wsTask.receive()
        debugLog("WebSocket connected: \(createdMsg)")

        onStatusChange(String(localized: "音声を送信中..."))
        onProgress(0.15)

        let bufferSize: AVAudioFrameCount = 4096
        var framesRead: AVAudioFrameCount = 0

        while framesRead < totalFrames {
            let framesToRead = min(bufferSize, totalFrames - framesRead)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: framesToRead) else {
                debugLog("Failed to create read buffer")
                break
            }

            do {
                try audioFile.read(into: buffer)
            } catch {
                debugLog("Failed to read audio file: \(error)")
                break
            }

            if buffer.frameLength == 0 {
                break
            }

            var outputBuffer: AVAudioPCMBuffer

            if let conv = converter {
                let ratio = sampleRate / processingFormat.sampleRate
                let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
                    debugLog("Failed to create conversion buffer")
                    break
                }

                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                let status = conv.convert(to: converted, error: &error, withInputFrom: inputBlock)

                if status == .error {
                    debugLog("Conversion error: \(error?.localizedDescription ?? "unknown")")
                    break
                }

                outputBuffer = converted
            } else {
                outputBuffer = buffer
            }

            let floatData = outputBuffer.floatChannelData![0]
            let frameCount = Int(outputBuffer.frameLength)
            var pcm16Data = Data(count: frameCount * 2)
            pcm16Data.withUnsafeMutableBytes { rawBuffer in
                let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                for i in 0..<frameCount {
                    let sample = max(-1.0, min(1.0, floatData[i]))
                    int16Buffer[i] = Int16(sample * 32767)
                }
            }

            let base64Audio = pcm16Data.base64EncodedString()
            let appendMsg = "{\"type\":\"input_audio_buffer.append\",\"audio\":\"\(base64Audio)\"}"
            try await wsTask.send(.string(appendMsg))

            framesRead += buffer.frameLength

            let progress = Double(framesRead) / Double(totalFrames)
            onProgress(0.15 + progress * 0.7)
        }

        debugLog("Finished sending audio (\(framesRead) frames), sending commit...")
        onStatusChange(String(localized: "文字起こし中..."))

        let commitMsg = "{\"type\":\"input_audio_buffer.commit\",\"final\":true}"
        try await wsTask.send(.string(commitMsg))

        var fullText = ""
        var isDone = false
        while !isDone {
            let message = try await wsTask.receive()
            switch message {
            case .string(let text):
                if let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String {
                    if type == "response.audio_transcript.delta",
                       let delta = json["delta"] as? String {
                        fullText += delta
                    } else if type == "response.audio_transcript.done" {
                        if let doneText = json["text"] as? String {
                            fullText = doneText
                        }
                        isDone = true
                    }
                }
            default:
                break
            }
        }

        wsTask.cancel(with: .normalClosure, reason: nil)

        onProgress(1.0)
        onStatusChange(String(localized: "完了"))

        debugLog("Local ASR batch transcription completed: \(fullText.count) chars, text: \(fullText)")

        return fullText
    }
}

enum BatchTranscriptionError: LocalizedError {
    case formatNotAvailable
    case analyzerInitFailed
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .formatNotAvailable:
            return String(localized: "音声形式が利用できません")
        case .analyzerInitFailed:
            return String(localized: "音声認識エンジンの初期化に失敗しました")
        case .fileReadFailed:
            return String(localized: "ファイルの読み込みに失敗しました")
        }
    }
}
