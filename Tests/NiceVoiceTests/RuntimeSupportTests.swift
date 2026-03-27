import Foundation
import Testing
@testable import NiceVoice

struct RuntimeSupportTests {
    @Test
    func commandLineToolResolvesExecutablesFromPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let executableURL = tempDir.appendingPathComponent("yt-dlp")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let resolved = CommandLineTool.ytDlp.resolvedURL(
            environment: ["PATH": tempDir.path]
        )

        #expect(resolved?.path == executableURL.path)
    }

    @Test
    func commandLineToolResolvesUvxFromMiseInstallDirectory() throws {
        let homeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let uvxURL = homeDir
            .appendingPathComponent(".local/share/mise/installs/uv/0.11.1/uv-aarch64-apple-darwin/uvx")

        try FileManager.default.createDirectory(
            at: uvxURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: homeDir) }

        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: uvxURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: uvxURL.path
        )

        let resolved = CommandLineTool.uvx.resolvedURL(
            environment: [
                "HOME": homeDir.path,
                "PATH": "/usr/bin:/bin"
            ]
        )

        #expect(resolved?.standardizedFileURL.path == uvxURL.standardizedFileURL.path)
    }

    @Test
    func serverResourceLocatorFindsRepositoryStyleLayoutFromExecutablePath() throws {
        let repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executableDir = repoRoot
            .appendingPathComponent(".build/debug", isDirectory: true)
        let serverDir = repoRoot
            .appendingPathComponent("Server/qwen3asr", isDirectory: true)

        try FileManager.default.createDirectory(at: executableDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: serverDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoRoot) }

        let packageDirectory = ServerResourceLocator.packageDirectory(
            relativePath: "qwen3asr",
            currentDirectory: "/tmp/does-not-exist",
            executableURL: executableDir.appendingPathComponent("NiceVoice"),
            resourceURL: nil
        )

        #expect(packageDirectory?.path == serverDir.path)
    }

    @Test
    func bundledPythonRuntimeLocatorFindsPackagedVoxtralRuntime() throws {
        let bundleRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resourceRoot = bundleRoot.appendingPathComponent("Resources", isDirectory: true)
        let serverRoot = resourceRoot.appendingPathComponent("Server", isDirectory: true)
        let sitePackages = serverRoot
            .appendingPathComponent(".venv/lib/python3.13/site-packages", isDirectory: true)
        let pythonExecutable = resourceRoot
            .appendingPathComponent("PythonRuntime/cpython-test/bin/python3", isDirectory: false)
        let moduleRoot = serverRoot.appendingPathComponent("voxmlx", isDirectory: true)

        try FileManager.default.createDirectory(at: sitePackages, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: moduleRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: pythonExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bundleRoot) }

        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: pythonExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pythonExecutable.path
        )

        let runtime = BundledPythonRuntimeLocator.runtime(
            packageRelativePath: "",
            resourceURL: resourceRoot
        )

        #expect(runtime?.pythonExecutableURL.standardizedFileURL.path == pythonExecutable.standardizedFileURL.path)
        #expect(runtime?.serverRootURL.standardizedFileURL.path == serverRoot.standardizedFileURL.path)
        #expect(runtime?.sitePackagesURL.standardizedFileURL.path == sitePackages.standardizedFileURL.path)
        #expect(runtime?.pythonPathEntries == [serverRoot.standardizedFileURL.path, sitePackages.standardizedFileURL.path])
    }
}
