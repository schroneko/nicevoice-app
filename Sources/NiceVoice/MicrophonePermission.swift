import AVFoundation

enum MicrophonePermission {
    static var isGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    static var isDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
