import AVFoundation

enum WAVEncoder {
    static func header(sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16 = 16, dataSize: UInt32) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
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
        return header
    }

    static func data(pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16 = 16) -> Data {
        var data = header(
            sampleRate: sampleRate,
            channels: channels,
            bitsPerSample: bitsPerSample,
            dataSize: UInt32(pcmData.count)
        )
        data.append(pcmData)
        return data
    }

    static func data(samples: [Float], sampleRate: Int = 16000) -> Data {
        var data = header(
            sampleRate: UInt32(sampleRate),
            channels: 1,
            dataSize: UInt32(samples.count * 2)
        )
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}

final class RecordedAudioStore {
    private let label: String
    private(set) var format: AVAudioFormat?
    private var buffers: [AVAudioPCMBuffer] = []

    init(label: String) {
        self.label = label
    }

    func setFormat(_ format: AVAudioFormat) {
        self.format = format
    }

    @discardableResult
    func append(copyOf buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = buffer.copied() else { return nil }
        buffers.append(copy)
        return copy
    }

    func clear() {
        buffers = []
    }

    func wavData(consuming: Bool) -> Data? {
        guard let format, !buffers.isEmpty else {
            debugLog("❌ No audio buffers to convert (\(label))")
            return nil
        }

        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else {
            debugLog("❌ Audio buffers are empty (\(label))")
            return nil
        }

        debugLog("🎵 Converting \(buffers.count) buffers (\(totalFrames) frames) to WAV (\(label))")

        let channels = Int(format.channelCount)
        var audioData = WAVEncoder.header(
            sampleRate: UInt32(format.sampleRate),
            channels: UInt16(format.channelCount),
            dataSize: UInt32(totalFrames * channels * 2)
        )

        for buffer in buffers {
            guard let floatData = buffer.floatChannelData else { continue }
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<channels {
                    let sample = floatData[channel][frame]
                    let clipped = max(-1.0, min(1.0, sample))
                    let intSample = Int16(clipped * Float(Int16.max))
                    withUnsafeBytes(of: intSample.littleEndian) { audioData.append(contentsOf: $0) }
                }
            }
        }

        debugLog("🎵 WAV data created: \(audioData.count) bytes (\(label))")
        if consuming {
            buffers = []
        }
        return audioData
    }
}

extension AVAudioPCMBuffer {
    func copied() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copy.frameLength = frameLength

        if let srcFloatData = floatChannelData, let dstFloatData = copy.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                memcpy(dstFloatData[channel], srcFloatData[channel], Int(frameLength) * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    var meterLevel: Float? {
        guard let channelData = floatChannelData else { return nil }
        let frameLength = Int(self.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        return min(1.0, rms * Constants.Audio.levelMultiplier)
    }

    var int16PCMData: Data {
        let frameLength = Int(self.frameLength)
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let totalBytes = frameLength * bytesPerFrame

        guard let int16Data = int16ChannelData else {
            return Data()
        }

        return Data(bytes: int16Data[0], count: totalBytes)
    }
}

extension AVAudioConverter {
    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCapacity) else {
            return nil
        }

        var error: NSError?
        let status = convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        return status == .error ? nil : convertedBuffer
    }
}
