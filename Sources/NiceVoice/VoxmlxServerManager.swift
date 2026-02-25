import Foundation

enum VoxmlxServerStatus: Equatable {
    case stopped
    case starting(String)
    case running
    case error(String)
}

final class VoxmlxServerManager {
    private var process: Process?
    private var healthCheckTask: Task<Void, Never>?
    private let onStatusChange: (VoxmlxServerStatus) -> Void

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    init(onStatusChange: @escaping (VoxmlxServerStatus) -> Void) {
        self.onStatusChange = onStatusChange
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }

        guard let uvxPath = findUvx() else {
            let status = VoxmlxServerStatus.error("uvx が見つかりません。uv をインストールしてください")
            debugLog("❌ voxmlx-serve: uvx not found in search paths")
            onStatusChange(status)
            return
        }

        guard let serverPath = Bundle.main.resourceURL?.appendingPathComponent("Server").path else {
            let status = VoxmlxServerStatus.error("Server リソースが見つかりません")
            debugLog("❌ voxmlx-serve: Server resource not found in app bundle")
            onStatusChange(status)
            return
        }

        debugLog("✅ voxmlx-serve: found uvx at \(uvxPath), server at \(serverPath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: uvxPath)
        proc.arguments = [
            "--from", "\(serverPath)[server]",
            "voxmlx-serve",
            "--model", Constants.VoxtralLocal.defaultModel,
            "--port", "8000"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard self?.process != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            debugLog("voxmlx-serve: \(line.trimmingCharacters(in: .newlines))")
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard self?.process != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            debugLog("voxmlx-serve: \(line.trimmingCharacters(in: .newlines))")
        }

        proc.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let code = terminatedProcess.terminationStatus
            if code != 0 && code != 15 {
                debugLog("❌ voxmlx-serve: process exited with code \(code)")
                DispatchQueue.main.async {
                    self.onStatusChange(.error("voxmlx-serve が異常終了しました (code: \(code))"))
                }
            }
        }

        do {
            try proc.run()
        } catch {
            debugLog("❌ voxmlx-serve: failed to start process: \(error)")
            onStatusChange(.error("voxmlx-serve の起動に失敗しました: \(error.localizedDescription)"))
            return
        }

        process = proc
        debugLog("🚀 voxmlx-serve: process started (PID: \(proc.processIdentifier))")
        onStatusChange(.starting("voxmlx-serve を起動中..."))
        startHealthPolling()
    }

    func stop() {
        healthCheckTask?.cancel()
        healthCheckTask = nil

        guard let proc = process, proc.isRunning else {
            process = nil
            onStatusChange(.stopped)
            return
        }

        debugLog("🛑 voxmlx-serve: sending SIGTERM (PID: \(proc.processIdentifier))")
        proc.terminate()

        let killWorkItem = DispatchWorkItem {
            guard proc.isRunning else { return }
            debugLog("🛑 voxmlx-serve: sending SIGKILL (PID: \(proc.processIdentifier))")
            kill(proc.processIdentifier, SIGKILL)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0, execute: killWorkItem)

        proc.waitUntilExit()
        killWorkItem.cancel()

        process = nil
        debugLog("🛑 voxmlx-serve: process stopped")
        onStatusChange(.stopped)
    }

    private func findUvx() -> String? {
        for path in Constants.VoxtralLocal.uvxSearchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func startHealthPolling() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { [weak self] in
            guard let self else { return }

            let startTime = Date()
            let timeout = Constants.VoxtralLocal.serverStartupTimeoutSeconds
            let interval = Constants.VoxtralLocal.healthPollIntervalSeconds
            var firstPoll = true

            while !Task.isCancelled {
                if firstPoll {
                    firstPoll = false
                    await MainActor.run {
                        self.onStatusChange(.starting("モデルを読み込み中... (初回はダウンロードに数分かかります)"))
                    }
                }

                if await checkHealth() {
                    debugLog("✅ voxmlx-serve: health check passed")
                    await MainActor.run {
                        self.onStatusChange(.running)
                    }
                    return
                }

                if Date().timeIntervalSince(startTime) > timeout {
                    debugLog("❌ voxmlx-serve: startup timeout (\(Int(timeout))s)")
                    self.stop()
                    await MainActor.run {
                        self.onStatusChange(.error("voxmlx-serve の起動がタイムアウトしました"))
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func checkHealth() async -> Bool {
        guard let url = URL(string: Constants.VoxtralLocal.healthEndpoint) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.VoxtralLocal.healthCheckTimeoutSeconds
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
