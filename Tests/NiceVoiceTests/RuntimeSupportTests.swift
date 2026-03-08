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
