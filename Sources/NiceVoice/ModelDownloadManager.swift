import Foundation

enum ModelDownloadStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double, message: String)
    case downloaded
    case error(String)
}

final class ModelDownloadManager {
    private var process: Process?
    private let modelName: String
    private let onStatusChange: (ModelDownloadStatus) -> Void
    private let hfSearchPaths: [String]

    var isDownloading: Bool {
        process?.isRunning ?? false
    }

    init(
        modelName: String,
        hfSearchPaths: [String],
        onStatusChange: @escaping (ModelDownloadStatus) -> Void
    ) {
        self.modelName = modelName
        self.hfSearchPaths = hfSearchPaths
        self.onStatusChange = onStatusChange
    }

    deinit {
        cancelDownload()
    }

    var isModelCached: Bool {
        let snapshotsDir = modelCacheDirectory + "/snapshots"
        guard FileManager.default.fileExists(atPath: snapshotsDir) else { return false }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir) else { return false }
        return !contents.filter({ !$0.hasPrefix(".") }).isEmpty
    }

    func checkAndReport() {
        DispatchQueue.main.async {
            self.onStatusChange(self.isModelCached ? .downloaded : .notDownloaded)
        }
    }

    func startDownload() {
        guard !isDownloading else { return }

        guard let hfPath = findHf() else {
            debugLog("[ModelDownload] hf CLI not found")
            DispatchQueue.main.async {
                self.onStatusChange(.error(CommandLineTool.hf.installHint))
            }
            return
        }

        debugLog("[ModelDownload] starting download: \(modelName) using \(hfPath)")
        DispatchQueue.main.async {
            self.onStatusChange(.downloading(progress: 0, message: String(localized: "ダウンロードを開始中...")))
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: hfPath)
        proc.arguments = ["download", modelName]

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = stdoutPipe

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            self?.handleProgressOutput(line)
        }

        proc.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            let code = terminatedProcess.terminationStatus
            if code == 0 {
                debugLog("[ModelDownload] download completed successfully")
                DispatchQueue.main.async {
                    self.onStatusChange(.downloaded)
                }
            } else if code == 15 {
                debugLog("[ModelDownload] download cancelled")
            } else {
                debugLog("[ModelDownload] download failed with code \(code)")
                DispatchQueue.main.async {
                    self.onStatusChange(.error(String(localized: "ダウンロードに失敗しました (code: \(code))")))
                }
            }
        }

        do {
            try proc.run()
            process = proc
            debugLog("[ModelDownload] process started (PID: \(proc.processIdentifier))")
        } catch {
            debugLog("[ModelDownload] failed to start: \(error)")
            DispatchQueue.main.async {
                self.onStatusChange(.error(String(localized: "ダウンロードの開始に失敗しました: \(error.localizedDescription)")))
            }
        }
    }

    func cancelDownload() {
        guard let proc = process, proc.isRunning else {
            process = nil
            return
        }
        debugLog("[ModelDownload] cancelling download (PID: \(proc.processIdentifier))")
        proc.terminate()
        process = nil
        DispatchQueue.main.async {
            self.onStatusChange(.notDownloaded)
        }
    }

    func deleteModel() {
        cancelDownload()
        let cacheDir = modelCacheDirectory
        guard FileManager.default.fileExists(atPath: cacheDir) else {
            debugLog("[ModelDownload] cache directory not found: \(cacheDir)")
            DispatchQueue.main.async {
                self.onStatusChange(.notDownloaded)
            }
            return
        }
        do {
            try FileManager.default.removeItem(atPath: cacheDir)
            debugLog("[ModelDownload] deleted cache: \(cacheDir)")
            DispatchQueue.main.async {
                self.onStatusChange(.notDownloaded)
            }
        } catch {
            debugLog("[ModelDownload] failed to delete cache: \(error)")
            DispatchQueue.main.async {
                self.onStatusChange(.error(String(localized: "モデルの削除に失敗しました: \(error.localizedDescription)")))
            }
        }
    }

    private var modelCacheDirectory: String {
        let sanitized = modelName.replacingOccurrences(of: "/", with: "--")
        return NSHomeDirectory() + "/.cache/huggingface/hub/models--" + sanitized
    }

    private func findHf() -> String? {
        CommandLineTool.hf.resolvedURL(additionalAbsolutePaths: hfSearchPaths)?.path
    }

    private func handleProgressOutput(_ output: String) {
        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            debugLog("[ModelDownload] \(line.trimmingCharacters(in: .whitespacesAndNewlines))")

            if let progress = parseProgress(from: line) {
                let sizeInfo = parseSizeInfo(from: line) ?? ""
                let message = sizeInfo.isEmpty
                    ? String(localized: "ダウンロード中... \(Int(progress * 100))%")
                    : String(localized: "ダウンロード中... \(sizeInfo)")
                DispatchQueue.main.async {
                    self.onStatusChange(.downloading(progress: progress, message: message))
                }
            }
        }
    }

    private func parseProgress(from line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)%\|"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        guard let percent = Int(line[range]) else { return nil }
        return Double(percent) / 100.0
    }

    private func parseSizeInfo(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\|\s*([\d.]+[KMGT]?i?B?)\s*/\s*([\d.]+[KMGT]?i?B)"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let currentRange = Range(match.range(at: 1), in: line),
              let totalRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return "\(line[currentRange]) / \(line[totalRange])"
    }
}
