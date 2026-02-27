import Foundation

enum LocalServerStatus: Equatable {
    case stopped
    case starting(String)
    case running
    case error(String)
}

final class LocalServerManager {
    private var process: Process?
    private var healthCheckTask: Task<Void, Never>?
    private let onStatusChange: (LocalServerStatus) -> Void

    private let serverCommand: String
    private let serverPackagePath: String
    private let modelName: String
    private let port: Int
    private let healthEndpoint: String
    private let httpRequestTimeout: Double
    private let startupTimeout: Double
    private let healthPollInterval: Double
    private let uvxSearchPaths: [String]

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    init(
        serverCommand: String,
        serverPackagePath: String,
        modelName: String,
        port: Int,
        healthEndpoint: String,
        httpRequestTimeout: Double,
        startupTimeout: Double,
        healthPollInterval: Double,
        uvxSearchPaths: [String],
        onStatusChange: @escaping (LocalServerStatus) -> Void
    ) {
        self.serverCommand = serverCommand
        self.serverPackagePath = serverPackagePath
        self.modelName = modelName
        self.port = port
        self.healthEndpoint = healthEndpoint
        self.httpRequestTimeout = httpRequestTimeout
        self.startupTimeout = startupTimeout
        self.healthPollInterval = healthPollInterval
        self.uvxSearchPaths = uvxSearchPaths
        self.onStatusChange = onStatusChange
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }

        killExistingProcessOnPort()

        guard let uvxPath = findUvx() else {
            let status = LocalServerStatus.error("uvx が見つかりません。uv をインストールしてください")
            debugLog("[\(serverCommand)] uvx not found in search paths")
            onStatusChange(status)
            return
        }

        guard let serverPath = Bundle.main.resourceURL?
            .appendingPathComponent("Server")
            .appendingPathComponent(serverPackagePath).path else {
            let status = LocalServerStatus.error("Server リソースが見つかりません")
            debugLog("[\(serverCommand)] Server resource not found in app bundle")
            onStatusChange(status)
            return
        }

        debugLog("[\(serverCommand)] found uvx at \(uvxPath), server at \(serverPath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: uvxPath)
        proc.arguments = [
            "--refresh",
            "--from", "\(serverPath)[server]",
            serverCommand,
            "--model", modelName,
            "--port", String(port)
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self, self.process != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            debugLog("[\(self.serverCommand)] \(line.trimmingCharacters(in: .newlines))")
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self, self.process != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            debugLog("[\(self.serverCommand)] \(line.trimmingCharacters(in: .newlines))")
        }

        proc.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let code = terminatedProcess.terminationStatus
            if code != 0 && code != 15 {
                debugLog("[\(self.serverCommand)] process exited with code \(code)")
                DispatchQueue.main.async {
                    self.onStatusChange(.error("\(self.serverCommand) が異常終了しました (code: \(code))"))
                }
            }
        }

        do {
            try proc.run()
        } catch {
            debugLog("[\(serverCommand)] failed to start process: \(error)")
            onStatusChange(.error("\(serverCommand) の起動に失敗しました: \(error.localizedDescription)"))
            return
        }

        process = proc
        debugLog("[\(serverCommand)] process started (PID: \(proc.processIdentifier))")
        onStatusChange(.starting("\(serverCommand) を起動中..."))
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

        debugLog("[\(serverCommand)] sending SIGTERM (PID: \(proc.processIdentifier))")
        proc.terminate()

        let killWorkItem = DispatchWorkItem {
            guard proc.isRunning else { return }
            debugLog("[\(self.serverCommand)] sending SIGKILL (PID: \(proc.processIdentifier))")
            kill(proc.processIdentifier, SIGKILL)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0, execute: killWorkItem)

        proc.waitUntilExit()
        killWorkItem.cancel()

        process = nil
        debugLog("[\(serverCommand)] process stopped")
        onStatusChange(.stopped)
    }

    private func findUvx() -> String? {
        for path in uvxSearchPaths {
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
            var firstPoll = true

            while !Task.isCancelled {
                if firstPoll {
                    firstPoll = false
                    await MainActor.run {
                        self.onStatusChange(.starting("モデルを読み込み中... (初回はダウンロードに数分かかります)"))
                    }
                }

                if !(self.process?.isRunning ?? false) {
                    debugLog("[\(self.serverCommand)] process died during startup")
                    await MainActor.run {
                        self.onStatusChange(.error("\(self.serverCommand) が起動中にクラッシュしました"))
                    }
                    self.process = nil
                    return
                }

                if await checkHealth() {
                    debugLog("[\(self.serverCommand)] health check passed")
                    await MainActor.run {
                        self.onStatusChange(.running)
                    }
                    return
                }

                if Date().timeIntervalSince(startTime) > self.startupTimeout {
                    debugLog("[\(self.serverCommand)] startup timeout (\(Int(self.startupTimeout))s)")
                    self.stop()
                    await MainActor.run {
                        self.onStatusChange(.error("\(self.serverCommand) の起動がタイムアウトしました"))
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(self.healthPollInterval * 1_000_000_000))
            }
        }
    }

    private func killExistingProcessOnPort() {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice
        do {
            try lsof.run()
            lsof.waitUntilExit()
        } catch {
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return
        }

        for pidStr in output.components(separatedBy: "\n") {
            if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)), pid > 0 {
                debugLog("[\(serverCommand)] killing stale process on port \(port) (PID: \(pid))")
                kill(pid, SIGTERM)
            }
        }

        usleep(500_000)
    }

    private func checkHealth() async -> Bool {
        guard let url = URL(string: healthEndpoint) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = httpRequestTimeout
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
