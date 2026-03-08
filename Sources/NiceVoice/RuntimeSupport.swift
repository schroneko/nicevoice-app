import Foundation

enum CommandLineTool: String, CaseIterable {
    case uvx = "uvx"
    case hf = "hf"
    case ytDlp = "yt-dlp"

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
            return "uvx が見つかりません。`brew install uv` または `curl -LsSf https://astral.sh/uv/install.sh | sh` で uv をインストールしてください"
        case .hf:
            return "hf コマンドが見つかりません。`brew install huggingface-cli` または `uv tool install huggingface_hub` でインストールしてください"
        case .ytDlp:
            return "yt-dlp が見つかりません。`brew install yt-dlp` でインストールしてください"
        }
    }

    private var bundledSearchPaths: [String] {
        switch self {
        case .uvx:
            return Constants.VoxtralLocal.uvxSearchPaths
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
            environment: environment
        ) {
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    private func candidatePaths(
        additionalAbsolutePaths: [String],
        environment: [String: String]
    ) -> [String] {
        let pathDirectories = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let pathCandidates = pathDirectories.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent(rawValue)
                .path
        }

        return deduplicated(pathCandidates + additionalAbsolutePaths + bundledSearchPaths)
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
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [DependencyDiagnostic] {
        let tools = CommandLineTool.allCases.map { tool -> DependencyDiagnostic in
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

        let serverDiagnostic: DependencyDiagnostic = {
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

        return tools + [serverDiagnostic, updaterDiagnostic]
    }
}
