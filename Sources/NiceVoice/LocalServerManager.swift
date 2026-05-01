import Foundation
import Darwin

enum LocalServerStatus: Equatable {
    case stopped
    case starting(String)
    case running
    case error(String)
}

final class LocalServerManager {
    private static let managedProcessOwner = "nicevoice"

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
    private let requestedPort: Int
    private let endpointFactory: (Int) -> LocalServerEndpoint
    private let httpRequestTimeout: Double
    private let startupTimeout: Double
    private let healthPollInterval: Double
    private let uvxSearchPaths: [String]
    private let onEndpointResolved: (LocalServerEndpoint) -> Void
    private var resolvedEndpoint: LocalServerEndpoint?

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    init(
        serverCommand: String,
        serverModule: String,
        serverPackagePath: String,
        modelName: String,
        requestedPort: Int,
        endpointFactory: @escaping (Int) -> LocalServerEndpoint,
        httpRequestTimeout: Double,
        startupTimeout: Double,
        healthPollInterval: Double,
        uvxSearchPaths: [String],
        onEndpointResolved: @escaping (LocalServerEndpoint) -> Void,
        onStatusChange: @escaping (LocalServerStatus) -> Void
    ) {
        self.serverCommand = serverCommand
        self.serverModule = serverModule
        self.serverPackagePath = serverPackagePath
        self.modelName = modelName
        self.requestedPort = requestedPort
        self.endpointFactory = endpointFactory
        self.httpRequestTimeout = httpRequestTimeout
        self.startupTimeout = startupTimeout
        self.healthPollInterval = healthPollInterval
        self.uvxSearchPaths = uvxSearchPaths
        self.onEndpointResolved = onEndpointResolved
        self.onStatusChange = onStatusChange
    }

    static func resolvedPort(from line: String) -> Int? {
        let patterns = [
            #"NICEVOICE_PORT=(\d+)"#,
            #"Uvicorn running on http://[^:]+:(\d+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges > 1,
                  let portRange = Range(match.range(at: 1), in: line),
                  let port = Int(line[portRange]) else {
                continue
            }
            return port
        }

        return nil
    }

    deinit {
        stop()
    }

    func start() {
        debugLog("[\(serverCommand)] start requested")
        guard !isRunning else { return }
        resolvedEndpoint = nil

        guard let launchConfiguration = resolveLaunchConfiguration() else {
            debugLog("[\(serverCommand)] no launch configuration available")
            onStatusChange(.error(missingRuntimeMessage()))
            return
        }
        debugLog("[\(serverCommand)] launch configuration resolved")

        terminateStaleManagedProcesses()

        if requestedPort > 0 {
            do {
                try clearConflictingProcessOnPort()
            } catch {
                debugLog("[\(serverCommand)] port conflict: \(error.localizedDescription)")
                onStatusChange(.error(error.localizedDescription))
                return
            }
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
                "--port", String(requestedPort),
                "--managed-by", Self.managedProcessOwner
            ]
            proc.environment?["PYTHONPATH"] = mergedPythonPath(
                existingValue: proc.environment?["PYTHONPATH"],
                additionalEntries: runtime.pythonPathEntries
            )
            proc.environment?["PYTHONDONTWRITEBYTECODE"] = "1"
        case .uvx(let uvxPath, let serverPath):
            debugLog("[\(serverCommand)] found uvx at \(uvxPath), server at \(serverPath)")
            proc.executableURL = URL(fileURLWithPath: uvxPath)
            proc.arguments = [
                "--refresh",
                "--from", "\(serverPath)[server]",
                serverCommand,
                "--model", modelName,
                "--port", String(requestedPort),
                "--managed-by", Self.managedProcessOwner
            ]
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self, self.process != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            self.handleProcessOutput(output)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self, self.process != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            self.handleProcessOutput(output)
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
        resolvedEndpoint = nil
        debugLog("[\(serverCommand)] process stopped")
        onStatusChange(.stopped)
    }

    private func handleProcessOutput(_ output: String) {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            debugLog("[\(serverCommand)] \(line)")

            guard resolvedEndpoint == nil, let port = Self.resolvedPort(from: line) else {
                continue
            }

            let endpoint = endpointFactory(port)
            resolvedEndpoint = endpoint
            debugLog("[\(serverCommand)] resolved listening port \(port)")
            DispatchQueue.main.async {
                self.onEndpointResolved(endpoint)
            }
        }
    }

    private func terminateStaleManagedProcesses() {
        let pids = Self.managedProcessIdentifiers(
            serverCommand: serverCommand,
            serverModule: serverModule,
            serverPackagePath: serverPackagePath
        )

        guard !pids.isEmpty else { return }

        for pid in pids {
            debugLog("[\(serverCommand)] killing stale managed process (PID: \(pid))")
            kill(pid, SIGTERM)
        }

        usleep(500_000)
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
        let pids = Self.processIdentifiers(usingPort: requestedPort)
        guard !pids.isEmpty else {
            return
        }

        for pid in pids {
            guard let commandLine = Self.processCommandLine(pid: pid) else {
                throw NSError(
                    domain: "NiceVoice.LocalServerManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "ポート \(requestedPort) を使用中のプロセス (PID: \(pid)) を確認できませんでした。手動で停止してください")]
                )
            }

            if Self.isManagedServerProcess(
                commandLine,
                serverCommand: serverCommand,
                serverModule: serverModule,
                serverPackagePath: serverPackagePath
            ) {
                debugLog("[\(serverCommand)] killing stale managed process on port \(requestedPort) (PID: \(pid))")
                kill(pid, SIGTERM)
            } else {
                throw NSError(
                    domain: "NiceVoice.LocalServerManager",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "ポート \(requestedPort) は別のプロセスが使用中です。NiceVoice 以外のプロセスは自動停止しません。該当プロセスを停止してから再試行してください")]
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
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        lsof.waitUntilExit()
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

    private static func managedProcessIdentifiers(
        serverCommand: String,
        serverModule: String,
        serverPackagePath: String
    ) -> [Int32] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        do {
            try ps.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return []
        }

        return output
            .split(separator: "\n")
            .compactMap { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard let separatorIndex = trimmedLine.firstIndex(where: \.isWhitespace) else {
                    return nil
                }

                let pidString = trimmedLine[..<separatorIndex].trimmingCharacters(in: .whitespaces)
                let commandLine = trimmedLine[separatorIndex...].trimmingCharacters(in: .whitespaces)

                guard let pid = Int32(pidString),
                      pid > 0,
                      pid != Int32(ProcessInfo.processInfo.processIdentifier),
                      isStaleManagedServerProcess(
                        commandLine,
                        serverCommand: serverCommand,
                        serverModule: serverModule,
                        serverPackagePath: serverPackagePath
                      ) else {
                    return nil
                }

                return pid
            }
    }

    private static func isStaleManagedServerProcess(
        _ commandLine: String,
        serverCommand: String,
        serverModule: String,
        serverPackagePath: String
    ) -> Bool {
        if commandLine.contains("--managed-by \(managedProcessOwner)") &&
            (commandLine.contains(serverCommand) || commandLine.contains(serverModule)) {
            return true
        }

        if commandLine.contains("/NiceVoice.app/") && commandLine.contains(serverModule) {
            return true
        }

        if !serverPackagePath.isEmpty && commandLine.contains("/NiceVoice.app/") && commandLine.contains(serverPackagePath) {
            return true
        }

        return false
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
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    private static func isManagedServerProcess(
        _ commandLine: String,
        serverCommand: String,
        serverModule: String,
        serverPackagePath: String
    ) -> Bool {
        if commandLine.contains("--managed-by \(managedProcessOwner)") &&
            (commandLine.contains(serverCommand) || commandLine.contains(serverModule)) {
            return true
        }

        if commandLine.contains("/NiceVoice.app/") && commandLine.contains(serverModule) {
            return true
        }

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

    private func checkHealth() async -> Bool {
        guard let healthEndpoint = resolvedEndpoint?.healthEndpoint,
              let url = URL(string: healthEndpoint) else {
            return false
        }
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
