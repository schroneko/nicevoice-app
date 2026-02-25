import AVFoundation
import Foundation

final class VoxtralLocalService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var isRunning = false
    private var receiveTask: Task<Void, Never>?
    private var sessionReady = false
    private var pendingStop = false

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var recordingFormat: AVAudioFormat?
    private var pendingPCMChunks: [Data] = []

    private var accumulatedText = ""

    private let serverURL: String
    private let onTranscription: (String, Bool) -> Void
    private let onFinalCompletion: ((String) -> Void)?
    private let onError: (String) -> Void
    private let onStatusChange: ((String) -> Void)?
    private let onAudioLevel: ((Float) -> Void)?

    private lazy var voxtralFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Constants.VoxtralLocal.sampleRate, channels: 1, interleaved: true)!
    }()

    init(
        serverURL: String = Constants.VoxtralLocal.wsEndpoint,
        onTranscription: @escaping (String, Bool) -> Void,
        onFinalCompletion: ((String) -> Void)? = nil,
        onError: @escaping (String) -> Void,
        onStatusChange: ((String) -> Void)? = nil,
        onAudioLevel: ((Float) -> Void)? = nil
    ) {
        self.serverURL = serverURL
        self.onTranscription = onTranscription
        self.onFinalCompletion = onFinalCompletion
        self.onError = onError
        self.onStatusChange = onStatusChange
        self.onAudioLevel = onAudioLevel
    }

    func startRecording() {
        guard !isRunning else { return }

        isRunning = true
        sessionReady = false
        pendingStop = false
        accumulatedText = ""
        audioBuffers = []
        pendingPCMChunks = []

        startAudioCapture()
        connectWebSocket()
    }

    func stopRecording() {
        guard isRunning else { return }
        isRunning = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

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
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        disconnectWebSocket()
    }

    func getRecordedAudioData() -> Data? {
        guard let format = recordingFormat, !audioBuffers.isEmpty else {
            debugLog("❌ No audio buffers to convert (voxmlx)")
            return nil
        }

        let totalFrames = audioBuffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else {
            debugLog("❌ Audio buffers are empty (voxmlx)")
            return nil
        }

        debugLog("🎵 Converting \(audioBuffers.count) buffers (\(totalFrames) frames) to WAV (voxmlx)")

        let bitsPerSample: UInt16 = 16
        let channels = UInt16(format.channelCount)
        let sampleRate = UInt32(format.sampleRate)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
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
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
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

        debugLog("🎵 WAV data created: \(audioData.count) bytes (voxmlx)")
        audioBuffers = []
        return audioData
    }

    func clearAudioBuffers() {
        audioBuffers = []
    }

    func checkServerHealth() async -> Bool {
        guard let url = URL(string: Constants.VoxtralLocal.healthEndpoint) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.VoxtralLocal.healthCheckTimeoutSeconds
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func connectWebSocket() {
        guard let url = URL(string: serverURL) else {
            onError("Invalid voxmlx-serve WebSocket URL")
            return
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        debugLog("🔌 voxmlx WebSocket connecting to \(url)")
        onStatusChange?("voxmlx に接続中...")

        startReceiving()
    }

    private func disconnectWebSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        sessionReady = false
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
                            self.onError("WebSocket エラー: \(error.localizedDescription)")
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
            flushPendingChunks()
            DispatchQueue.main.async {
                self.onStatusChange?("voxmlx 接続完了")
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
            let errorMessage = (json["message"] as? String) ?? "voxmlx エラー"
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

    private func startAudioCapture() {
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordingFormat = inputFormat
        debugLog("🔊 voxmlx input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        audioConverter = AVAudioConverter(from: inputFormat, to: voxtralFormat)

        inputNode.installTap(onBus: 0, bufferSize: Constants.Audio.bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let stillRecording = self.isRunning

            if let copy = self.copyBuffer(buffer) {
                self.audioBuffers.append(copy)
            }

            if stillRecording {
                if let converted = self.convertToVoxtralFormat(buffer) {
                    let pcmData = self.extractPCMData(from: converted)
                    self.sendAudioChunk(pcmData)
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

        usleep(Constants.Audio.engineStartDelayMicroseconds)

        do {
            try audioEngine.start()
            debugLog("🎙️ voxmlx audio capture started")
        } catch {
            debugLog("❌ voxmlx audio engine failed to start: \(error)")
            onError("オーディオエンジンの起動に失敗しました")
            isRunning = false
        }
    }

    private func convertToVoxtralFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = audioConverter else { return nil }

        let ratio = voxtralFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: voxtralFormat, frameCapacity: outputFrameCapacity) else {
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
}
