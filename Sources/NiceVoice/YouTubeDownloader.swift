import Foundation

enum YouTubeDownloadError: LocalizedError {
    case ytDlpNotFound
    case downloadFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .ytDlpNotFound:
            return CommandLineTool.ytDlp.installHint
        case .downloadFailed(let message):
            return String(localized: "ダウンロード失敗: \(message)")
        case .invalidOutput:
            return String(localized: "yt-dlp の出力からファイルパスを取得できませんでした")
        }
    }
}

final class YouTubeDownloader {
    static let shared = YouTubeDownloader()

    private init() {}

    func isAvailable() -> Bool {
        resolvedExecutablePath() != nil
    }

    func download(url: String, outputDir: URL) async throws -> URL {
        guard let ytDlpPath = resolvedExecutablePath() else {
            throw YouTubeDownloadError.ytDlpNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = [
            "-x",
            "--audio-format", "m4a",
            "--audio-quality", "0",
            "-o", "\(outputDir.path)/%(title)s.%(ext)s",
            "--print", "after_move:filepath",
            url
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus != 0 {
                    continuation.resume(throwing: YouTubeDownloadError.downloadFailed(stderr))
                    return
                }

                guard !stdout.isEmpty else {
                    continuation.resume(throwing: YouTubeDownloadError.invalidOutput)
                    return
                }

                let filePath = stdout.components(separatedBy: "\n").last ?? stdout
                let fileURL = URL(fileURLWithPath: filePath)

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    continuation.resume(returning: fileURL)
                } else {
                    continuation.resume(throwing: YouTubeDownloadError.invalidOutput)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: YouTubeDownloadError.downloadFailed(error.localizedDescription))
            }
        }
    }

    func installationHint() -> String {
        CommandLineTool.ytDlp.installHint
    }

    private func resolvedExecutablePath() -> String? {
        CommandLineTool.ytDlp.resolvedURL()?.path
    }
}
