import AVFoundation
import Foundation

final class DeepgramService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var isRunning = false
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var recordingFormat: AVAudioFormat?

    private var accumulatedText = ""

    private let apiKey: String
    private let sampleRate: Double
    private let onTranscription: (String, Bool) -> Void
    private let onFinalCompletion: ((String) -> Void)?
    private let onError: (String) -> Void
    private let onStatusChange: ((String) -> Void)?
    private let onAudioLevel: ((Float) -> Void)?
    private let onCaptureStarted: (() -> Void)?

    private lazy var targetFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: self.sampleRate, channels: 1, interleaved: true)!
    }()

    init(
        apiKey: String,
        sampleRate: Double = Constants.Deepgram.sampleRate,
        onTranscription: @escaping (String, Bool) -> Void,
        onFinalCompletion: ((String) -> Void)? = nil,
        onError: @escaping (String) -> Void,
        onStatusChange: ((String) -> Void)? = nil,
        onAudioLevel: ((Float) -> Void)? = nil,
        onCaptureStarted: (() -> Void)? = nil
    ) {
        self.apiKey = apiKey
        self.sampleRate = sampleRate
        self.onTranscription = onTranscription
        self.onFinalCompletion = onFinalCompletion
        self.onError = onError
        self.onStatusChange = onStatusChange
        self.onAudioLevel = onAudioLevel
        self.onCaptureStarted = onCaptureStarted
    }

    func startRecording() {
        guard !isRunning else { return }

        isRunning = true
        accumulatedText = ""
        audioBuffers = []

        startAudioCapture()
        connectWebSocket()
    }

    func stopRecording() {
        guard isRunning else { return }
        isRunning = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        sendCloseStream()
        debugLog("Deepgram recording stopped")
    }

    func stop() {
        isRunning = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        disconnectWebSocket()
    }

    func getRecordedAudioData(consuming: Bool = true) -> Data? {
        guard let format = recordingFormat, !audioBuffers.isEmpty else {
            debugLog("No audio buffers to convert (Deepgram)")
            return nil
        }

        let totalFrames = audioBuffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else {
            debugLog("Audio buffers are empty (Deepgram)")
            return nil
        }

        debugLog("Converting \(audioBuffers.count) buffers (\(totalFrames) frames) to WAV (Deepgram)")

        let bitsPerSample: UInt16 = 16
        let channels = UInt16(format.channelCount)
        let sampleRateInt = UInt32(format.sampleRate)
        let byteRate = sampleRateInt * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(totalFrames) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let fileSize: UInt32 = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRateInt.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append(contentsOf: "data".utf8)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        var audioData = header
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

        debugLog("WAV data created: \(audioData.count) bytes (Deepgram)")
        if consuming {
            audioBuffers = []
        }
        return audioData
    }

    func clearAudioBuffers() {
        audioBuffers = []
    }

    private func connectWebSocket() {
        var components = URLComponents(string: Constants.Deepgram.wsEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "model", value: Constants.Deepgram.defaultModel),
            URLQueryItem(name: "language", value: Constants.Deepgram.defaultLanguage),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(Int(sampleRate))),
            URLQueryItem(name: "channels", value: "1"),
        ]

        guard let url = components.url else {
            onError("Invalid Deepgram WebSocket URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        debugLog("Deepgram WebSocket connecting...")
        onStatusChange?(String(localized: "Deepgram に接続中..."))

        startReceiving()
        startKeepAlive()
    }

    private func disconnectWebSocket() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }

            var connected = false

            while !Task.isCancelled {
                guard let webSocketTask = self.webSocketTask else { break }

                do {
                    let message = try await webSocketTask.receive()
                    if !connected {
                        connected = true
                        await MainActor.run {
                            self.onStatusChange?(String(localized: "Deepgram 接続完了"))
                        }
                        debugLog("Deepgram WebSocket connected")
                    }
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
                        debugLog("Deepgram WebSocket receive error: \(error)")
                        await MainActor.run {
                            self.onError(String(localized: "Deepgram WebSocket エラー: \(error.localizedDescription)"))
                        }
                    }
                    break
                }
            }
        }
    }

    private func startKeepAlive() {
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.Deepgram.keepAliveIntervalSeconds))
                guard !Task.isCancelled, let self, self.webSocketTask != nil else { break }
                let msg = "{\"type\":\"KeepAlive\"}"
                self.webSocketTask?.send(.string(msg)) { error in
                    if let error {
                        debugLog("Deepgram KeepAlive error: \(error)")
                    }
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            debugLog("Deepgram: Failed to parse message: \(text.prefix(200))")
            return
        }

        switch type {
        case "Results":
            handleResults(json)
        case "Metadata":
            debugLog("Deepgram metadata received")
        case "error", "Error":
            let errorMessage = (json["message"] as? String) ?? String(localized: "Deepgram エラー")
            debugLog("Deepgram error: \(errorMessage)")
            DispatchQueue.main.async {
                self.onError(errorMessage)
            }
        default:
            debugLog("Deepgram unknown message type: \(type)")
        }
    }

    private func handleResults(_ json: [String: Any]) {
        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            return
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let speechFinal = json["speech_final"] as? Bool ?? false

        if transcript.isEmpty { return }

        if isFinal {
            if !accumulatedText.isEmpty && !accumulatedText.hasSuffix(" ") {
                accumulatedText += " "
            }
            accumulatedText += transcript
        }

        let currentText = isFinal ? accumulatedText : accumulatedText + transcript
        DispatchQueue.main.async {
            self.onTranscription(currentText, speechFinal)
        }

        if speechFinal {
            let finalText = accumulatedText
            debugLog("Deepgram speech_final: \(finalText.count) chars")
        }
    }

    func finalize() {
        let finalText = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        debugLog("Deepgram finalize: \(finalText.count) chars")
        DispatchQueue.main.async {
            self.onTranscription(finalText, true)
            self.onFinalCompletion?(finalText)
        }
        disconnectWebSocket()
    }

    private func sendCloseStream() {
        let msg = "{\"type\":\"CloseStream\"}"
        webSocketTask?.send(.string(msg)) { [weak self] error in
            if let error {
                debugLog("Deepgram CloseStream error: \(error)")
            }
            debugLog("Deepgram: sent CloseStream")

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.finalize()
            }
        }
    }

    private func sendAudioData(_ pcmData: Data) {
        webSocketTask?.send(.data(pcmData)) { error in
            if let error {
                debugLog("Deepgram send error: \(error)")
            }
        }
    }

    private func startAudioCapture() {
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordingFormat = inputFormat
        debugLog("Deepgram input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: Constants.Audio.bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let stillRecording = self.isRunning

            if let copy = self.copyBuffer(buffer) {
                self.audioBuffers.append(copy)
            }

            if stillRecording {
                if let converted = self.convertToTargetFormat(buffer) {
                    let pcmData = self.extractPCMData(from: converted)
                    self.sendAudioData(pcmData)
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
                let level = min(1.0, rms * Constants.Audio.levelMultiplier)
                DispatchQueue.main.async {
                    self.onAudioLevel?(level)
                }
            }
        }

        do {
            try audioEngine.start()
            debugLog("Deepgram audio capture started")
            DispatchQueue.main.async {
                self.onCaptureStarted?()
            }
        } catch {
            debugLog("Deepgram audio engine failed to start: \(error)")
            onError(String(localized: "オーディオエンジンの起動に失敗しました"))
            isRunning = false
        }
    }

    private func convertToTargetFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = audioConverter else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        return status == .error ? nil : convertedBuffer
    }

    private func extractPCMData(from buffer: AVAudioPCMBuffer) -> Data {
        let frameLength = Int(buffer.frameLength)
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let totalBytes = frameLength * bytesPerFrame

        guard let int16Data = buffer.int16ChannelData else {
            return Data()
        }

        return Data(bytes: int16Data[0], count: totalBytes)
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

    static func transcribeBatch(
        fileURL: URL,
        apiKey: String,
        onProgress: @escaping (Double) -> Void,
        onStatusChange: @escaping (String) -> Void
    ) async throws -> String {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        onStatusChange(String(localized: "ファイルを読み込み中..."))
        onProgress(0.05)

        let audioData = try Data(contentsOf: fileURL)

        onStatusChange(String(localized: "Deepgram に送信中..."))
        onProgress(0.2)

        var components = URLComponents(string: Constants.Deepgram.restEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "model", value: Constants.Deepgram.defaultModel),
            URLQueryItem(name: "language", value: Constants.Deepgram.defaultLanguage),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]

        guard let url = components.url else {
            throw DeepgramError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let ext = fileURL.pathExtension.lowercased()
        let contentType: String
        switch ext {
        case "wav": contentType = "audio/wav"
        case "mp3": contentType = "audio/mpeg"
        case "m4a": contentType = "audio/mp4"
        case "aiff", "aif": contentType = "audio/aiff"
        case "ogg": contentType = "audio/ogg"
        case "flac": contentType = "audio/flac"
        default: contentType = "audio/wav"
        }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        onStatusChange(String(localized: "文字起こし中..."))
        onProgress(0.5)

        let (responseData, response) = try await URLSession.shared.upload(for: request, from: audioData)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: responseData, encoding: .utf8) ?? "unknown"
            debugLog("Deepgram batch error \(httpResponse.statusCode): \(errorBody)")
            throw DeepgramError.apiError(httpResponse.statusCode, errorBody)
        }

        onProgress(0.9)

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            throw DeepgramError.parseError
        }

        onProgress(1.0)
        onStatusChange(String(localized: "完了"))

        debugLog("Deepgram batch transcription completed: \(transcript.count) chars")
        return transcript
    }
}

enum DeepgramError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int, String)
    case parseError
    case noApiKey

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Deepgram の URL が無効です")
        case .invalidResponse:
            return String(localized: "Deepgram からの応答が無効です")
        case .apiError(let code, let message):
            return String(localized: "Deepgram API エラー (\(code)): \(message)")
        case .parseError:
            return String(localized: "Deepgram の応答を解析できませんでした")
        case .noApiKey:
            return String(localized: "Deepgram API キーが設定されていません。設定画面から入力してください")
        }
    }
}
