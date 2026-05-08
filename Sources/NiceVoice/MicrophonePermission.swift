import AVFoundation

enum MicrophonePermission {
    static var isGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var isDenied: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            true
        case .authorized, .notDetermined:
            false
        @unknown default:
            true
        }
    }

    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
