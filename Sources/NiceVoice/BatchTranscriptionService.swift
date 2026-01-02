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
    case pending = "待機中"
    case processing = "処理中"
    case completed = "完了"
    case failed = "失敗"
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
        onProgress: @escaping (Double) -> Void,
        onStatusChange: @escaping (String) -> Void
    ) async throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        onStatusChange("ファイルを読み込み中...")
        onProgress(0.05)

        let audioFile = try AVAudioFile(forReading: url)
        let processingFormat = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)

        debugLog("Audio file: \(url.lastPathComponent), format: \(processingFormat.sampleRate)Hz, \(processingFormat.channelCount)ch, frames: \(totalFrames)")

        onStatusChange("音声認識モデルを準備中...")
        onProgress(0.1)

        let locale = Locale(identifier: "ja-JP")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatusChange("音声認識モデルをダウンロード中...")
            try await downloader.downloadAndInstall()
        }

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        guard let targetFormat = analyzerFormat else {
            throw BatchTranscriptionError.formatNotAvailable
        }

        debugLog("Analyzer format: \(targetFormat.sampleRate)Hz, \(targetFormat.channelCount)ch")

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        debugLog("SpeechAnalyzer created")

        onStatusChange("音声を処理中...")
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
            debugLog("Waiting for transcriber.results...")
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                debugLog("Received result: \(text.count) chars, final: \(result.isFinal)")
                if result.isFinal {
                    transcriptionResult += text
                    debugLog("Batch transcription segment: \(text.count) chars")
                }
            }
            debugLog("transcriber.results loop ended")
        }

        let analyzerTask = Task {
            debugLog("analyzer.start() called")
            try await analyzer.start(inputSequence: inputStream)
            debugLog("analyzer.start() completed")
        }

        onStatusChange("文字起こし中...")

        try await analyzerTask.value
        debugLog("analyzerTask completed, calling finalize...")

        onProgress(0.9)
        onStatusChange("完了処理中...")

        try await analyzer.finalizeAndFinishThroughEndOfInput()
        debugLog("finalizeAndFinishThroughEndOfInput completed")

        try await resultsTask.value
        debugLog("resultsTask completed")

        onProgress(1.0)
        onStatusChange("完了")

        debugLog("Batch transcription completed: \(transcriptionResult.count) chars")

        return transcriptionResult
    }

    func sendCompletionNotification(fileName: String, success: Bool, charCount: Int = 0) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = success ? "文字起こし完了" : "文字起こし失敗"
        content.body = success
            ? "\(fileName) の文字起こしが完了しました（\(charCount)文字）"
            : "\(fileName) の処理中にエラーが発生しました"
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
}

enum BatchTranscriptionError: LocalizedError {
    case formatNotAvailable
    case analyzerInitFailed
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .formatNotAvailable:
            return "音声形式が利用できません"
        case .analyzerInitFailed:
            return "音声認識エンジンの初期化に失敗しました"
        case .fileReadFailed:
            return "ファイルの読み込みに失敗しました"
        }
    }
}
