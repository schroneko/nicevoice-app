import Foundation

enum CommandLineTool: String, CaseIterable {
    case uvx = "uvx"
    case hf = "hf"
    case ytDlp = "yt-dlp"

    var isDeveloperOnly: Bool {
        switch self {
        case .uvx, .hf:
            return true
        case .ytDlp:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .uvx: return "uvx"
        case .hf: return "hf"
        case .ytDlp: return "yt-dlp"
        }
    }

    var purpose: String {
        switch self {
        case .uvx:
            return "ローカル ASR サーバーの起動"
        case .hf:
            return "ローカル音声認識モデルのダウンロード"
        case .ytDlp:
            return "YouTube 音声の取得"
        }
    }

    var installHint: String {
        switch self {
        case .uvx:
            return "uvx が見つかりません。`brew install uv`、`curl -LsSf https://astral.sh/uv/install.sh | sh`、または `mise use -g uv@<version>` で uv を使えるようにしてください"
        case .hf:
            return "hf コマンドが見つかりません。`brew install huggingface-cli` または `uv tool install huggingface_hub` でインストールしてください"
        case .ytDlp:
            return "yt-dlp が見つかりません。`brew install yt-dlp` でインストールしてください"
        }
    }

    private var bundledSearchPaths: [String] {
        switch self {
        case .uvx:
            return Constants.LocalASR.uvxSearchPaths
        case .hf:
            return Constants.HuggingFace.hfSearchPaths
        case .ytDlp:
            return [
                "/opt/homebrew/bin/yt-dlp",
                "/usr/local/bin/yt-dlp",
                "\(NSHomeDirectory())/.local/bin/yt-dlp"
            ]
        }
    }

    func resolvedURL(
        additionalAbsolutePaths: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        for candidate in candidatePaths(
            additionalAbsolutePaths: additionalAbsolutePaths,
            environment: environment,
            fileManager: fileManager
        ) {
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    private func candidatePaths(
        additionalAbsolutePaths: [String],
        environment: [String: String],
        fileManager: FileManager
    ) -> [String] {
        let pathDirectories = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let pathCandidates = pathDirectories.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent(rawValue)
                .path
        }

        return deduplicated(
            pathCandidates
            + additionalAbsolutePaths
            + miseSearchPaths(environment: environment, fileManager: fileManager)
            + bundledSearchPaths
        )
    }

    private func miseSearchPaths(
        environment: [String: String],
        fileManager: FileManager
    ) -> [String] {
        let homeDirectory = environment["HOME"] ?? NSHomeDirectory()
        let dataDirectory = environment["MISE_DATA_DIR"] ?? "\(homeDirectory)/.local/share/mise"
        let installsRoot = URL(fileURLWithPath: dataDirectory, isDirectory: true)
            .appendingPathComponent("installs", isDirectory: true)
        let shimCandidates = [
            "\(dataDirectory)/shims/\(rawValue)",
            "\(homeDirectory)/.mise/shims/\(rawValue)"
        ]

        let installCandidates = miseInstallDirectoryNames.flatMap { installDirectoryName in
            miseInstalledExecutablePaths(
                installsRoot: installsRoot,
                installDirectoryName: installDirectoryName,
                fileManager: fileManager
            )
        }

        return shimCandidates + installCandidates
    }

    private var miseInstallDirectoryNames: [String] {
        switch self {
        case .uvx:
            return ["uv"]
        case .hf:
            return ["hf", "huggingface_hub"]
        case .ytDlp:
            return ["yt-dlp"]
        }
    }

    private func miseInstalledExecutablePaths(
        installsRoot: URL,
        installDirectoryName: String,
        fileManager: FileManager
    ) -> [String] {
        let toolRoot = installsRoot.appendingPathComponent(installDirectoryName, isDirectory: true)
        guard let versionDirectories = try? fileManager.contentsOfDirectory(
            at: toolRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return versionDirectories.flatMap { versionDirectory in
            var candidates = [
                versionDirectory.appendingPathComponent(rawValue).path,
                versionDirectory.appendingPathComponent("bin/\(rawValue)").path
            ]

            if let nestedDirectories = try? fileManager.contentsOfDirectory(
                at: versionDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                candidates += nestedDirectories.flatMap { nestedDirectory in
                    [
                        nestedDirectory.appendingPathComponent(rawValue).path,
                        nestedDirectory.appendingPathComponent("bin/\(rawValue)").path
                    ]
                }
            }

            return candidates
        }
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = NSString(string: value).expandingTildeInPath
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }
}

enum ServerResourceLocator {
    static func serverRoot(
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        executableURL: URL? = Bundle.main.executableURL,
        resourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> URL? {
        for candidate in candidateServerRoots(
            currentDirectory: currentDirectory,
            executableURL: executableURL,
            resourceURL: resourceURL
        ) {
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func packageDirectory(
        relativePath: String,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        executableURL: URL? = Bundle.main.executableURL,
        resourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let root = serverRoot(
            currentDirectory: currentDirectory,
            executableURL: executableURL,
            resourceURL: resourceURL,
            fileManager: fileManager
        ) else {
            return nil
        }

        let directory = relativePath.isEmpty
            ? root
            : root.appendingPathComponent(relativePath, isDirectory: true)
        return fileManager.fileExists(atPath: directory.path) ? directory : nil
    }

    static func candidateServerRoots(
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        executableURL: URL? = Bundle.main.executableURL,
        resourceURL: URL? = Bundle.main.resourceURL
    ) -> [URL] {
        var candidates: [URL] = []

        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Server", isDirectory: true))
        }

        candidates.append(
            URL(fileURLWithPath: currentDirectory, isDirectory: true)
                .appendingPathComponent("Server", isDirectory: true)
        )

        if let executableURL {
            var ancestor = executableURL.deletingLastPathComponent()
            for _ in 0..<6 {
                candidates.append(ancestor.appendingPathComponent("Server", isDirectory: true))
                ancestor.deleteLastPathComponent()
            }
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }
}

struct BundledPythonRuntime: Equatable {
    let pythonExecutableURL: URL
    let serverRootURL: URL
    let moduleRootURL: URL
    let sitePackagesURL: URL

    var pythonPathEntries: [String] {
        [moduleRootURL.standardizedFileURL.path, sitePackagesURL.standardizedFileURL.path]
    }
}

enum BundledPythonRuntimeLocator {
    static func runtime(
        packageRelativePath: String,
        resourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> BundledPythonRuntime? {
        guard let resourceURL else {
            return nil
        }

        let serverRootURL = resourceURL.appendingPathComponent("Server", isDirectory: true)
        guard fileManager.fileExists(atPath: serverRootURL.path) else {
            return nil
        }

        let moduleRootURL = packageRelativePath.isEmpty
            ? serverRootURL
            : serverRootURL.appendingPathComponent(packageRelativePath, isDirectory: true)
        let venvRootURL = moduleRootURL.appendingPathComponent(".venv", isDirectory: true)

        guard
            let sitePackagesURL = sitePackagesDirectory(in: venvRootURL, fileManager: fileManager),
            let pythonExecutableURL = pythonExecutable(in: resourceURL, fileManager: fileManager)
        else {
            return nil
        }

        return BundledPythonRuntime(
            pythonExecutableURL: pythonExecutableURL,
            serverRootURL: serverRootURL,
            moduleRootURL: moduleRootURL,
            sitePackagesURL: sitePackagesURL
        )
    }

    private static func pythonExecutable(
        in resourceURL: URL,
        fileManager: FileManager
    ) -> URL? {
        let runtimeContainerURL = resourceURL.appendingPathComponent("PythonRuntime", isDirectory: true)
        guard
            let runtimeDirectories = try? fileManager.contentsOfDirectory(
                at: runtimeContainerURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        else {
            return nil
        }

        for runtimeDirectory in runtimeDirectories {
            let candidates = [
                runtimeDirectory.appendingPathComponent("bin/python3", isDirectory: false),
                runtimeDirectory.appendingPathComponent("bin/python", isDirectory: false)
            ]

            for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func sitePackagesDirectory(
        in venvRootURL: URL,
        fileManager: FileManager
    ) -> URL? {
        let libDirectoryURL = venvRootURL.appendingPathComponent("lib", isDirectory: true)
        guard
            let pythonDirectories = try? fileManager.contentsOfDirectory(
                at: libDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        else {
            return nil
        }

        for pythonDirectory in pythonDirectories {
            let candidate = pythonDirectory.appendingPathComponent("site-packages", isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}

struct DependencyDiagnostic: Identifiable, Equatable {
    enum Status: Equatable {
        case available
        case warning
        case missing

        var label: String {
            switch self {
            case .available: return "Ready"
            case .warning: return "Warn"
            case .missing: return "Missing"
            }
        }
    }

    let id: String
    let title: String
    let summary: String
    let detail: String?
    let status: Status
}

enum DependencyDiagnostics {
    static func snapshot(
        build: AppBuildChannel = .current,
        developerToolsEnabled: Bool = AppFeatureFlags.isDeveloperToolsEnabled(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [DependencyDiagnostic] {
        let tools = CommandLineTool.allCases
            .filter { developerToolsEnabled || !$0.isDeveloperOnly }
            .map { tool -> DependencyDiagnostic in
            if let path = tool.resolvedURL(environment: environment, fileManager: fileManager)?.path {
                return DependencyDiagnostic(
                    id: tool.rawValue,
                    title: tool.displayName,
                    summary: tool.purpose,
                    detail: path,
                    status: .available
                )
            }

            return DependencyDiagnostic(
                id: tool.rawValue,
                title: tool.displayName,
                summary: tool.purpose,
                detail: tool.installHint,
                status: .missing
            )
        }

        let serverDiagnostic: DependencyDiagnostic? = {
            guard developerToolsEnabled else {
                return nil
            }

            guard let serverRoot = ServerResourceLocator.serverRoot(fileManager: fileManager) else {
                return DependencyDiagnostic(
                    id: "server-resources",
                    title: "Server resources",
                    summary: "ローカル ASR 同梱サーバー",
                    detail: "Server ディレクトリが見つかりません。`Scripts/package-app.sh` を使ってアプリをバンドルしてください",
                    status: .missing
                )
            }

            let hasVoxtral = fileManager.fileExists(atPath: serverRoot.appendingPathComponent("voxmlx").path)
            let hasQwen = fileManager.fileExists(atPath: serverRoot.appendingPathComponent("qwen3asr").path)

            if hasVoxtral && hasQwen {
                return DependencyDiagnostic(
                    id: "server-resources",
                    title: "Server resources",
                    summary: "ローカル ASR 同梱サーバー",
                    detail: serverRoot.path,
                    status: .available
                )
            }

            return DependencyDiagnostic(
                id: "server-resources",
                title: "Server resources",
                summary: "ローカル ASR 同梱サーバー",
                detail: "\(serverRoot.path) に必要なパッケージが揃っていません",
                status: .warning
            )
        }()

        let updaterDiagnostic: DependencyDiagnostic = {
            if AppUpdateConfiguration.isConfigured() {
                return DependencyDiagnostic(
                    id: "sparkle",
                    title: "Sparkle",
                    summary: "アプリ内自動更新",
                    detail: AppUpdateConfiguration.feedURLString(),
                    status: .available
                )
            }

            let message = build == .release
                ? "自動更新は未設定です。ビルド時に `NICEVOICE_APPCAST_URL` と `NICEVOICE_SPARKLE_PUBLIC_KEY` を設定してください"
                : "リリースビルド時に `NICEVOICE_APPCAST_URL` と `NICEVOICE_SPARKLE_PUBLIC_KEY` を設定すると自動更新を有効化できます"
            return DependencyDiagnostic(
                id: "sparkle",
                title: "Sparkle",
                summary: "アプリ内自動更新",
                detail: message,
                status: .warning
            )
        }()

        return tools + [serverDiagnostic, updaterDiagnostic].compactMap { $0 }
    }
}
