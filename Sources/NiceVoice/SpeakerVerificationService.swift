import AVFoundation
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
        guard let segment = result.segments.first else {
            throw SpeakerVerificationError.embeddingFailed
        }
        let embedding = segment.embedding

        self.enrolledEmbedding = embedding
        saveEnrolledEmbedding(embedding)
        debugLog("SpeakerVerification: enrolled with \(embedding.count)-dim embedding")
        return true
    }

    func enrollFromAudioFile(url: URL) async throws -> Bool {
        let samples = try await loadAudioSamples(from: url)
        return try enroll(audioSamples: samples)
    }

    func enrollFromRecordedData(_ data: Data, format: AVAudioFormat) throws -> Bool {
        let samples = extractFloatSamples(from: data, format: format)
        guard !samples.isEmpty else {
            throw SpeakerVerificationError.noAudioData
        }
        return try enroll(audioSamples: samples)
    }

    func verify(audioSamples: [Float], threshold: Float = 0.5) throws -> SpeakerVerificationResult {
        guard let diarizer else {
            throw SpeakerVerificationError.notInitialized
        }

        guard let enrolled = enrolledEmbedding else {
            throw SpeakerVerificationError.notEnrolled
        }

        let result = try diarizer.performCompleteDiarization(audioSamples)
        guard let segment = result.segments.first else {
            throw SpeakerVerificationError.embeddingFailed
        }
        let testEmbedding = segment.embedding

        let distance = cosineDistance(enrolled, testEmbedding)
        let isMatch = distance < threshold

        debugLog("SpeakerVerification: distance=\(distance), threshold=\(threshold), match=\(isMatch)")

        return SpeakerVerificationResult(
            isMatch: isMatch,
            distance: distance,
            confidence: confidenceFromDistance(distance)
        )
    }

    func resetEnrollment() {
        enrolledEmbedding = nil
        UserDefaults.standard.removeObject(forKey: "speakerEmbedding")
        debugLog("SpeakerVerification: enrollment reset")
    }

    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        SpeakerUtilities.cosineDistance(a, b)
    }

    private func confidenceFromDistance(_ distance: Float) -> SpeakerConfidence {
        if distance < 0.3 { return .veryHigh }
        if distance < 0.5 { return .high }
        if distance < 0.7 { return .medium }
        if distance < 0.9 { return .low }
        return .veryLow
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

                var error: NSError?
                let status = conv.convert(to: converted, error: &error) { _, outStatus in
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

    private func extractFloatSamples(from data: Data, format: AVAudioFormat) -> [Float] {
        let headerSize = 44
        guard data.count > headerSize else { return [] }

        let pcmData = data.subdata(in: headerSize..<data.count)
        let sampleCount = pcmData.count / 2

        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)

        pcmData.withUnsafeBytes { buffer in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples.append(Float(int16Buffer[i]) / Float(Int16.max))
            }
        }

        return samples
    }
}

struct SpeakerVerificationResult {
    let isMatch: Bool
    let distance: Float
    let confidence: SpeakerConfidence
}

enum SpeakerConfidence: String {
    case veryHigh = "非常に高い"
    case high = "高い"
    case medium = "中程度"
    case low = "低い"
    case veryLow = "非常に低い"
}

enum SpeakerVerificationError: LocalizedError {
    case notInitialized
    case notEnrolled
    case embeddingFailed
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "声紋認証サービスが初期化されていません"
        case .notEnrolled:
            return "声紋が登録されていません。先に声を登録してください"
        case .embeddingFailed:
            return "声紋の抽出に失敗しました"
        case .noAudioData:
            return "音声データがありません"
        }
    }
}
