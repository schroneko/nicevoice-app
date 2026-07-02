@preconcurrency import AVFoundation
import FluidAudio
import Foundation

final class SpeakerVerificationService {
    static let shared = SpeakerVerificationService()

    private var diarizer: DiarizerManager?
    private var enrolledEmbedding: [Float]?
    private var isInitialized = false

    var isEnrolled: Bool {
        enrolledEmbedding != nil
    }

    var isReady: Bool {
        isInitialized
    }

    private init() {
        loadEnrolledEmbedding()
    }

    func initialize() async throws {
        guard !isInitialized else { return }

        debugLog("SpeakerVerification: downloading models...")
        let models = try await DiarizerModels.downloadIfNeeded()

        debugLog("SpeakerVerification: initializing diarizer...")
        let manager = DiarizerManager()
        manager.initialize(models: models)
        self.diarizer = manager
        self.isInitialized = true
        debugLog("SpeakerVerification: initialized")
    }

    func enroll(audioSamples: [Float]) throws -> Bool {
        guard let diarizer else {
            throw SpeakerVerificationError.notInitialized
        }

        let result = try diarizer.performCompleteDiarization(audioSamples)
        guard !result.segments.isEmpty else {
            throw SpeakerVerificationError.embeddingFailed
        }
        let segment = result.segments.max(by: { $0.durationSeconds < $1.durationSeconds })!
        let embedding = segment.embedding

        self.enrolledEmbedding = embedding
        saveEnrolledEmbedding(embedding)
        debugLog("SpeakerVerification: enrolled with \(embedding.count)-dim embedding from \(String(format: "%.1f", segment.durationSeconds))s segment")
        return true
    }

    func enrollFromRecordedData(_ data: Data, format: AVAudioFormat) async throws -> Bool {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let samples = try await loadAudioSamples(from: tempURL)
        guard !samples.isEmpty else {
            throw SpeakerVerificationError.noAudioData
        }
        return try enroll(audioSamples: samples)
    }

    func quickVerify(wavData: Data) async throws -> Bool {
        guard let diarizer, let enrolled = enrolledEmbedding else {
            return true
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try wavData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let samples = try await loadAudioSamples(from: tempURL)
        let tailSamples = samples.count > 80000 ? Array(samples.suffix(80000)) : samples
        guard tailSamples.count > 8000 else { return true }

        let result = try diarizer.performCompleteDiarization(tailSamples)
        guard let segment = result.segments.last else { return true }

        let distance = SpeakerUtilities.cosineDistance(enrolled, segment.embedding)
        debugLog("SpeakerCheck: quickVerify distance=\(distance)")
        return distance < 0.7
    }

    func filterByEnrolledSpeaker(wavData: Data, threshold: Float = 0.7) async throws -> SpeakerFilterResult {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try wavData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let samples = try await loadAudioSamples(from: tempURL)
        guard !samples.isEmpty else {
            throw SpeakerVerificationError.noAudioData
        }
        return try filterSamples(samples, threshold: threshold)
    }

    func createWAV(from samples: [Float], sampleRate: Int = 16000) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let chunkSize: UInt32 = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: chunkSize.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        withUnsafeBytes(of: UInt32(16).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: numChannels.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataSize.littleEndian) { data.append(contentsOf: $0) }

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16.littleEndian) { data.append(contentsOf: $0) }
        }

        return data
    }

    private func filterSamples(_ samples: [Float], threshold: Float) throws -> SpeakerFilterResult {
        guard let diarizer else {
            throw SpeakerVerificationError.notInitialized
        }

        guard let enrolled = enrolledEmbedding else {
            throw SpeakerVerificationError.notEnrolled
        }

        let result = try diarizer.performCompleteDiarization(samples, sampleRate: 16000)

        var enrolledSegments: [(start: Float, end: Float)] = []
        var totalDuration: Float = 0
        var enrolledDuration: Float = 0
        var speakerIds = Set<String>()

        for segment in result.segments {
            totalDuration += segment.durationSeconds
            speakerIds.insert(segment.speakerId)

            let distance = SpeakerUtilities.cosineDistance(enrolled, segment.embedding)
            debugLog("SpeakerFilter: segment \(segment.speakerId) [\(segment.startTimeSeconds)-\(segment.endTimeSeconds)s] distance=\(distance)")
            if distance < threshold {
                enrolledSegments.append((start: segment.startTimeSeconds, end: segment.endTimeSeconds))
                enrolledDuration += segment.durationSeconds
            }
        }

        let ratio = totalDuration > 0 ? enrolledDuration / totalDuration : 0
        let isSingleSpeaker = speakerIds.count <= 1

        var filteredSamples: [Float]? = nil
        if !enrolledSegments.isEmpty && !isSingleSpeaker {
            var extracted: [Float] = []
            for seg in enrolledSegments {
                let startIdx = Int(seg.start * 16000)
                let endIdx = min(Int(seg.end * 16000), samples.count)
                if startIdx < endIdx {
                    extracted.append(contentsOf: samples[startIdx..<endIdx])
                }
            }
            filteredSamples = extracted
        }

        debugLog("SpeakerFilter: \(speakerIds.count) speakers, enrolledRatio=\(ratio), enrolledSegments=\(enrolledSegments.count)")

        return SpeakerFilterResult(
            enrolledRatio: ratio,
            enrolledSegments: enrolledSegments,
            filteredAudioSamples: filteredSamples,
            totalSpeechDuration: totalDuration,
            enrolledSpeechDuration: enrolledDuration,
            isSingleSpeaker: isSingleSpeaker
        )
    }

    func resetEnrollment() {
        enrolledEmbedding = nil
        UserDefaults.standard.removeObject(forKey: "speakerEmbedding")
        debugLog("SpeakerVerification: enrollment reset")
    }

    private func saveEnrolledEmbedding(_ embedding: [Float]) {
        let data = embedding.withUnsafeBytes { Data($0) }
        UserDefaults.standard.set(data, forKey: "speakerEmbedding")
    }

    private func loadEnrolledEmbedding() {
        guard let data = UserDefaults.standard.data(forKey: "speakerEmbedding") else { return }
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return }

        enrolledEmbedding = data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self).prefix(count))
        }
        debugLog("SpeakerVerification: loaded enrolled embedding (\(count)-dim)")
    }

    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let audioFile = try AVAudioFile(forReading: url)
        let processingFormat = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        var converter: AVAudioConverter?
        if processingFormat.sampleRate != 16000 || processingFormat.channelCount != 1 {
            converter = AVAudioConverter(from: processingFormat, to: targetFormat)
        }

        let bufferSize: AVAudioFrameCount = 4096
        var allSamples: [Float] = []

        var framesRead: AVAudioFrameCount = 0
        while framesRead < totalFrames {
            let framesToRead = min(bufferSize, totalFrames - framesRead)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: framesToRead) else { break }

            try audioFile.read(into: buffer)
            if buffer.frameLength == 0 { break }

            var outputBuffer: AVAudioPCMBuffer

            if let conv = converter {
                let ratio = targetFormat.sampleRate / processingFormat.sampleRate
                let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else { break }

                var inputConsumed = false
                var error: NSError?
                let status = conv.convert(to: converted, error: &error) { _, outStatus in
                    if inputConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    inputConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                if status == .error { break }
                outputBuffer = converted
            } else {
                outputBuffer = buffer
            }

            if let floatData = outputBuffer.floatChannelData {
                let frameCount = Int(outputBuffer.frameLength)
                for i in 0..<frameCount {
                    allSamples.append(floatData[0][i])
                }
            }

            framesRead += buffer.frameLength
        }

        debugLog("SpeakerVerification: loaded \(allSamples.count) samples from \(url.lastPathComponent)")
        return allSamples
    }

}

struct SpeakerFilterResult {
    let enrolledRatio: Float
    let enrolledSegments: [(start: Float, end: Float)]
    let filteredAudioSamples: [Float]?
    let totalSpeechDuration: Float
    let enrolledSpeechDuration: Float
    let isSingleSpeaker: Bool
}

enum SpeakerVerificationError: LocalizedError {
    case notInitialized
    case notEnrolled
    case embeddingFailed
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return String(localized: "声紋認証サービスが初期化されていません")
        case .notEnrolled:
            return String(localized: "声紋が登録されていません。先に声を登録してください")
        case .embeddingFailed:
            return String(localized: "声紋の抽出に失敗しました")
        case .noAudioData:
            return String(localized: "音声データがありません")
        }
    }
}
