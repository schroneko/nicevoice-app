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
}
