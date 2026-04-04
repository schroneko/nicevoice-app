import Foundation
import Darwin

enum LocalServerStatus: Equatable {
    case stopped
    case starting(String)
    case running
    case error(String)
}

final class LocalServerManager {
    private enum LaunchConfiguration {
        case bundled(runtime: BundledPythonRuntime)
        case uvx(uvxPath: String, serverPath: String)
    }

    private var process: Process?
    private var healthCheckTask: Task<Void, Never>?
    private let onStatusChange: (LocalServerStatus) -> Void

    private let serverCommand: String
    private let serverModule: String
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
        serverModule: String,
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
        self.serverModule = serverModule
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

    static func resolvePort(
        preferred: Int,
        fallbackRange: ClosedRange<Int>,
        serverCommand: String,
        serverPackagePath: String
    ) -> Int {
        guard let commandLine = processCommandLine(usingPort: preferred) else {
            return preferred
        }

        if isManagedServerProcess(
            commandLine,
            serverCommand: serverCommand,
            serverPackagePath: serverPackagePath
        ) {
            return preferred
        }

        for candidate in fallbackRange where candidate != preferred {
            if isPortAvailable(candidate) {
                debugLog("[\(serverCommand)] using fallback port \(candidate) because \(preferred) is occupied by: \(commandLine)")
                return candidate
            }
        }

        return preferred
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }

        guard let launchConfiguration = resolveLaunchConfiguration() else {
            debugLog("[\(serverCommand)] no launch configuration available")
            onStatusChange(.error(missingRuntimeMessage()))
            return
        }

        do {
            try clearConflictingProcessOnPort()
        } catch {
            debugLog("[\(serverCommand)] port conflict: \(error.localizedDescription)")
            onStatusChange(.error(error.localizedDescription))
            return
        }

        let proc = Process()
        proc.environment = ProcessInfo.processInfo.environment

        switch launchConfiguration {
        case .bundled(let runtime):
            debugLog("[\(serverCommand)] using bundled python at \(runtime.pythonExecutableURL.path)")
            proc.executableURL = runtime.pythonExecutableURL
            proc.currentDirectoryURL = runtime.serverRootURL
            proc.arguments = [
                "-m", serverModule,
                "--model", modelName,
                "--port", String(port)
            ]
            proc.environment?["PYTHONPATH"] = mergedPythonPath(
                existingValue: proc.environment?["PYTHONPATH"],
                additionalEntries: runtime.pythonPathEntries
            )
        case .uvx(let uvxPath, let serverPath):
            debugLog("[\(serverCommand)] found uvx at \(uvxPath), server at \(serverPath)")
            proc.executableURL = URL(fileURLWithPath: uvxPath)
            proc.arguments = [
                "--refresh",
                "--from", "\(serverPath)[server]",
                serverCommand,
                "--model", modelName,
                "--port", String(port)
            ]
        }

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
                    self.onStatusChange(.error(String(localized: "\(self.serverCommand) が異常終了しました (code: \(code))")))
                }
            }
        }

        do {
            try proc.run()
        } catch {
            debugLog("[\(serverCommand)] failed to start process: \(error)")
            onStatusChange(.error(String(localized: "\(serverCommand) の起動に失敗しました: \(error.localizedDescription)")))
            return
        }

        process = proc
        debugLog("[\(serverCommand)] process started (PID: \(proc.processIdentifier))")
        onStatusChange(.starting(String(localized: "\(serverCommand) を起動中...")))
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
        CommandLineTool.uvx.resolvedURL(additionalAbsolutePaths: uvxSearchPaths)?.path
    }

    private func resolveLaunchConfiguration() -> LaunchConfiguration? {
        if let runtime = BundledPythonRuntimeLocator.runtime(packageRelativePath: serverPackagePath) {
            return .bundled(runtime: runtime)
        }

        guard
            let uvxPath = findUvx(),
            let serverPath = ServerResourceLocator.packageDirectory(relativePath: serverPackagePath)?.path
        else {
            return nil
        }

        return .uvx(uvxPath: uvxPath, serverPath: serverPath)
    }

    private func mergedPythonPath(existingValue: String?, additionalEntries: [String]) -> String {
        let existingEntries = existingValue?
            .split(separator: ":")
            .map(String.init) ?? []
        let entries = additionalEntries + existingEntries
        var seen = Set<String>()
        return entries.filter { entry in
            !entry.isEmpty && seen.insert(entry).inserted
        }.joined(separator: ":")
    }

    private func missingRuntimeMessage() -> String {
        if serverCommand == "voxmlx-serve" {
            return String(localized: "Voxtral ランタイムが見つかりません。アプリを再インストールしてください")
        }

        return CommandLineTool.uvx.installHint
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
                        self.onStatusChange(.starting(String(localized: "モデルを読み込み中... (初回はダウンロードに数分かかります)")))
                    }
                }

                if !(self.process?.isRunning ?? false) {
                    debugLog("[\(self.serverCommand)] process died during startup")
                    await MainActor.run {
                        self.onStatusChange(.error(String(localized: "\(self.serverCommand) が起動中にクラッシュしました")))
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
                        self.onStatusChange(.error(String(localized: "\(self.serverCommand) の起動がタイムアウトしました")))
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(self.healthPollInterval * 1_000_000_000))
            }
        }
    }

    private func clearConflictingProcessOnPort() throws {
        let pids = Self.processIdentifiers(usingPort: port)
        guard !pids.isEmpty else {
            return
        }

        for pid in pids {
            guard let commandLine = Self.processCommandLine(pid: pid) else {
                throw NSError(
                    domain: "NiceVoice.LocalServerManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "ポート \(port) を使用中のプロセス (PID: \(pid)) を確認できませんでした。手動で停止してください")]
                )
            }

            if Self.isManagedServerProcess(
                commandLine,
                serverCommand: serverCommand,
                serverPackagePath: serverPackagePath
            ) {
                debugLog("[\(serverCommand)] killing stale managed process on port \(port) (PID: \(pid))")
                kill(pid, SIGTERM)
            } else {
                throw NSError(
                    domain: "NiceVoice.LocalServerManager",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "ポート \(port) は別のプロセスが使用中です。NiceVoice 以外のプロセスは自動停止しません。該当プロセスを停止してから再試行してください")]
                )
            }
        }

        usleep(500_000)
    }

    private static func processIdentifiers(usingPort port: Int) -> [Int32] {
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
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty else {
            return []
        }

        return output
            .components(separatedBy: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }
    }

    private static func processCommandLine(usingPort port: Int) -> String? {
        for pid in processIdentifiers(usingPort: port) {
            if let commandLine = processCommandLine(pid: pid) {
                return commandLine
            }
        }
        return nil
    }

    private static func processCommandLine(pid: Int32) -> String? {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "command=", "-p", String(pid)]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        do {
            try ps.run()
            ps.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    private static func isManagedServerProcess(
        _ commandLine: String,
        serverCommand: String,
        serverPackagePath: String
    ) -> Bool {
        if commandLine.contains(serverCommand) {
            return true
        }

        if !serverPackagePath.isEmpty, commandLine.contains(serverPackagePath) {
            return true
        }

        if commandLine.contains("voxmlx") || commandLine.contains("qwen3asr") {
            return true
        }

        return false
    }

    private static func isPortAvailable(_ port: Int) -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        defer { close(socketDescriptor) }

        var reuseAddress: Int32 = 1
        setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(
                    socketDescriptor,
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
            }
        }
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
