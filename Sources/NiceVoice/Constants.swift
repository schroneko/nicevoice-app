import Foundation
import Carbon.HIToolbox
import CoreGraphics

enum Constants {
    enum Log {
        static let maxFileSizeBytes: UInt64 = 5 * 1024 * 1024
        static let maxBackupCount = 3
    }

    enum Audio {
        static let bufferSize: UInt32 = 4096
        static let realtimeBufferSize: UInt32 = 1024
        static let levelMultiplier: Float = 5.0
        static let finalizationWaitMilliseconds: UInt64 = 500
        static let captureFreshnessThresholdSeconds: Double = 1.5
        static let captureStartupTimeoutSeconds: Double = 1.0
        static let stopDelayUntilFirstBufferSeconds: Double = 0.35
    }

    enum BrailleMeter {
        static let symbols: [Character] = ["⠤", "⠴", "⠶", "⠷", "⡷", "⡿", "⣿"]
        static let historyLength = 4
        static let updateInterval: TimeInterval = 0.06
        static let attack: Double = 0.80
        static let release: Double = 0.25
        static let alphaNoiseFloor: Double = 0.05
    }

    enum Timing {
        static let speechAnalyzerFinalResultTimeoutSeconds: Double = 3.0
        static let localASRFinalResultTimeoutSeconds: Double = 30.0
        static let pastePreDelaySeconds: Double = 0.1
        static let pastePostDelaySeconds: Double = 1.5
        static let keyEventDelayMicroseconds: UInt32 = 50_000
    }

    enum UI {
        static let floatingPanelWidth: CGFloat = 180
        static let floatingPanelHeight: CGFloat = 48
        static let floatingPanelExpandedWidth: CGFloat = 360
        static let floatingPanelExpandedHeight: CGFloat = 104
        static let floatingPanelMaxWidth: CGFloat = 520
        static let floatingPanelBottomOffset: CGFloat = 40
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

    enum LocalASR {
        static let host = "127.0.0.1"
        static let sampleRate: Double = 16000
        static let httpRequestTimeoutSeconds: Double = 3.0
        static let serverStartupTimeoutSeconds: Double = 600.0
        static let healthPollIntervalSeconds: Double = 2.0
        static let voxtralModel = "schroneko/Voxtral-Mini-4B-Realtime-2602-MLX-4bit"
        static let qwen3Model = "schroneko/Qwen3-ASR-1.7B-MLX-4bit"
        static let uvxSearchPaths = [
            "/opt/homebrew/bin/uvx",
            "/usr/local/bin/uvx",
            "\(NSHomeDirectory())/.local/bin/uvx",
            "\(NSHomeDirectory())/.cargo/bin/uvx"
        ]

        static func wsEndpoint(port: Int) -> String {
            "ws://\(host):\(port)/v1/realtime"
        }

        static func healthEndpoint(port: Int) -> String {
            "http://\(host):\(port)/health"
        }
    }

    enum HuggingFace {
        static let hfSearchPaths = [
            "/opt/homebrew/bin/hf",
            "/usr/local/bin/hf",
            "\(NSHomeDirectory())/.local/bin/hf"
        ]
    }

}
