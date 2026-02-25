import Foundation
import Carbon.HIToolbox

enum Constants {
    enum Log {
        static let maxFileSizeBytes: UInt64 = 5 * 1024 * 1024
        static let maxBackupCount = 3
    }

    enum Audio {
        static let bufferSize: UInt32 = 4096
        static let levelMultiplier: Float = 5.0
        static let engineStartDelayMicroseconds: UInt32 = 100_000
        static let finalizationWaitMilliseconds: UInt64 = 500
    }

    enum Waveform {
        static let minAmplitude: CGFloat = 0.08
        static let amplificationFactor: CGFloat = 15.0
        static let animationSpeed: Double = 2.5
        static let maxAmplitudeRatio: CGFloat = 0.48
    }

    enum Timing {
        static let finalResultTimeoutSeconds: Double = 3.0
        static let pastePreDelaySeconds: Double = 0.1
        static let pastePostDelaySeconds: Double = 0.15
        static let keyEventDelayMicroseconds: UInt32 = 50_000
        static let deleteKeyDelayMicroseconds: UInt32 = 10_000
        static let accessibilityCheckDelaySeconds: Double = 1.0
    }

    enum UI {
        static let floatingPanelWidth: CGFloat = 180
        static let floatingPanelHeight: CGFloat = 48
        static let floatingPanelBottomOffset: CGFloat = 40
        static let maxFocusedElementHeight: CGFloat = 100
        static let maxAXTreeSearchDepth = 10
    }

    enum History {
        static let maxCount = 20
    }

    enum KeyCode {
        static let escape: UInt16 = 53
        static let delete = UInt16(kVK_Delete)
        static let v = UInt16(kVK_ANSI_V)
    }

    enum VoxtralLocal {
        static let wsEndpoint = "ws://127.0.0.1:8000/v1/realtime"
        static let healthEndpoint = "http://127.0.0.1:8000/health"
        static let sampleRate: Double = 16000
        static let healthCheckTimeoutSeconds: Double = 3.0
        static let serverStartupTimeoutSeconds: Double = 600.0
        static let healthPollIntervalSeconds: Double = 2.0
        static let defaultModel = "schroneko/Voxtral-Mini-4B-Realtime-2602-MLX-4bit"
        static let uvxSearchPaths = [
            "/opt/homebrew/bin/uvx",
            "/usr/local/bin/uvx",
            "\(NSHomeDirectory())/.local/bin/uvx",
            "\(NSHomeDirectory())/.cargo/bin/uvx"
        ]
    }
}
