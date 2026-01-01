import AVFoundation
import Speech

final class SpeechRecognitionService {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let onTranscription: (String, Bool) -> Void
    private let onRealtimeInput: (String, String) -> Void
    private let onRecognitionError: ((String) -> Void)?
    private var lastTranscription = ""

    private var savedText = ""
    private var lastRecognizedText = ""

    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var recordingFormat: AVAudioFormat?

    private var lastVoiceTime = Date()
    private let silenceThreshold: Float = 0.01
    private let silenceDuration: TimeInterval = 0.8
    private var confirmedOnSilence = false

    init(
        onTranscription: @escaping (String, Bool) -> Void,
        onRealtimeInput: @escaping (String, String) -> Void,
        onRecognitionError: ((String) -> Void)? = nil
    ) {
        self.onTranscription = onTranscription
        self.onRealtimeInput = onRealtimeInput
        self.onRecognitionError = onRecognitionError
    }

    func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        lastTranscription = ""
        savedText = ""
        lastRecognizedText = ""
        lastVoiceTime = Date()
        confirmedOnSilence = false
        audioBuffers = []

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw NSError(domain: "SpeechService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create request"])
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        recordingFormat = format

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            recognitionRequest.append(buffer)
            if let copy = self.copyBuffer(buffer) {
                self.audioBuffers.append(copy)
            }

            let rms = self.calculateRMS(buffer)
            let now = Date()
            if rms > self.silenceThreshold {
                self.lastVoiceTime = now
                self.confirmedOnSilence = false
            } else {
                let elapsed = now.timeIntervalSince(self.lastVoiceTime)
                if elapsed >= self.silenceDuration && !self.lastRecognizedText.isEmpty && !self.confirmedOnSilence {
                    self.savedText = self.lastRecognizedText
                    self.confirmedOnSilence = true
                    debugLog("🔇 [VAD] Confirmed on silence: \(self.savedText.count) chars")
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        debugLog("🔍 [DEBUG] Starting recognition task")
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let error {
                debugLog("🔍 [DEBUG] Recognition error: \(error)")
                let nsError = error as NSError
                if nsError.domain == "kLSRErrorDomain" && nsError.code == 201 {
                    self.onRecognitionError?("音声認識が無効です: システム設定で Siri を有効にするか、Chrome を起動してください")
                }
            }
            if let result {
                let currentText = result.bestTranscription.formattedString
                let oldText = self.lastTranscription
                debugLog("🔍 [DEBUG] Recognition: current=\(currentText.count) chars, saved=\(self.savedText.count) chars, isFinal=\(result.isFinal)")

                self.lastRecognizedText = currentText

                let displayText: String
                if self.savedText.isEmpty {
                    displayText = currentText
                    debugLog("🔍 [MERGE] savedText empty, using currentText")
                } else {
                    let savedNormalized = self.savedText.filter { !$0.isPunctuation && !$0.isWhitespace }
                    let currentNormalized = currentText.filter { !$0.isPunctuation && !$0.isWhitespace }

                    let commonLen = self.commonPrefixLength(savedNormalized, currentNormalized)
                    let threshold = Int(Double(savedNormalized.count) * 0.7)
                    debugLog("🔍 [MERGE] savedText=\(self.savedText.count) chars, currentText=\(currentText.count) chars, commonLen=\(commonLen), threshold=\(threshold)")

                    let isShortFragment = savedNormalized.count <= 5
                    let isLikelyCorrection = isShortFragment && currentNormalized.count >= savedNormalized.count * 2 && commonLen < 2

                    let savedContainedInCurrent = currentNormalized.contains(savedNormalized) || savedNormalized.hasPrefix(String(currentNormalized.prefix(savedNormalized.count)))

                    let currentIsLongerOrSimilar = currentNormalized.count >= savedNormalized.count
                    let hasSignificantOverlap = commonLen >= min(savedNormalized.count, currentNormalized.count) / 3

                    if isLikelyCorrection {
                        displayText = currentText
                        debugLog("🔍 [MERGE] Treating as correction (short fragment replaced)")
                    } else if commonLen >= threshold || savedContainedInCurrent {
                        displayText = currentText
                        debugLog("🔍 [MERGE] Using currentText (continuation or correction)")
                    } else if currentIsLongerOrSimilar && hasSignificantOverlap {
                        displayText = currentText
                        debugLog("🔍 [MERGE] Using currentText (longer/similar with overlap)")
                    } else {
                        displayText = self.savedText + " " + currentText
                        debugLog("🔍 [MERGE] Concatenating: \(displayText.count) chars")
                    }
                }

                self.lastTranscription = displayText
                self.onTranscription(displayText, result.isFinal)
                self.onRealtimeInput(oldText, displayText)
            }
        }
        debugLog("🔍 [DEBUG] Recognition task created: \(recognitionTask != nil)")
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
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

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        let data = channelData[0]
        for i in 0..<frameLength {
            let sample = data[i]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameLength))
    }

    private func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        for (c1, c2) in zip(a, b) {
            if c1 == c2 { count += 1 } else { break }
        }
        return count
    }

    func getRecordedAudioData() -> Data? {
        guard let format = recordingFormat, !audioBuffers.isEmpty else {
            debugLog("❌ No audio buffers to convert")
            return nil
        }

        let totalFrames = audioBuffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else {
            debugLog("❌ Audio buffers are empty")
            return nil
        }

        debugLog("🎵 Converting \(audioBuffers.count) buffers (\(totalFrames) frames) to WAV")

        let wavHeader = createWAVHeader(
            sampleRate: UInt32(format.sampleRate),
            channels: UInt16(format.channelCount),
            bitsPerSample: 16,
            dataSize: UInt32(totalFrames * Int(format.channelCount) * 2)
        )

        var audioData = Data()
        audioData.append(wavHeader)

        for buffer in audioBuffers {
            if let floatData = buffer.floatChannelData {
                for frame in 0..<Int(buffer.frameLength) {
                    for channel in 0..<Int(format.channelCount) {
                        let sample = floatData[channel][frame]
                        let clampedSample = max(-1.0, min(1.0, sample))
                        var int16Sample = Int16(clampedSample * Float(Int16.max))
                        withUnsafeBytes(of: &int16Sample) { audioData.append(contentsOf: $0) }
                    }
                }
            }
        }

        debugLog("🎵 WAV data created: \(audioData.count) bytes")
        return audioData
    }

    private func createWAVHeader(sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16, dataSize: UInt32) -> Data {
        var header = Data()

        header.append(contentsOf: "RIFF".utf8)
        var fileSize = dataSize + 36
        withUnsafeBytes(of: &fileSize) { header.append(contentsOf: $0) }

        header.append(contentsOf: "WAVE".utf8)

        header.append(contentsOf: "fmt ".utf8)
        var fmtSize: UInt32 = 16
        withUnsafeBytes(of: &fmtSize) { header.append(contentsOf: $0) }
        var audioFormat: UInt16 = 1
        withUnsafeBytes(of: &audioFormat) { header.append(contentsOf: $0) }
        var numChannels = channels
        withUnsafeBytes(of: &numChannels) { header.append(contentsOf: $0) }
        var sampleRateVal = sampleRate
        withUnsafeBytes(of: &sampleRateVal) { header.append(contentsOf: $0) }
        var byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        withUnsafeBytes(of: &byteRate) { header.append(contentsOf: $0) }
        var blockAlign = channels * bitsPerSample / 8
        withUnsafeBytes(of: &blockAlign) { header.append(contentsOf: $0) }
        var bitsPerSampleVal = bitsPerSample
        withUnsafeBytes(of: &bitsPerSampleVal) { header.append(contentsOf: $0) }

        header.append(contentsOf: "data".utf8)
        var dataSizeVal = dataSize
        withUnsafeBytes(of: &dataSizeVal) { header.append(contentsOf: $0) }

        return header
    }

    func clearAudioBuffers() {
        audioBuffers = []
    }
}
