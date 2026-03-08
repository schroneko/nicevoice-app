#!/usr/bin/env swift
import Foundation

enum AccessMode: String, CaseIterable {
    case preview
    case `public`

    var marker: String {
        switch self {
        case .preview:
            return "nukosuku-preview"
        case .public:
            return "public-access"
        }
    }
}

struct XorShift64Star {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextByte() -> UInt8 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545F4914F6CDD1D
        let byte = UInt8(truncatingIfNeeded: value & 0xFF)
        return byte == 0 ? 0xA5 : byte
    }
}

func stableSeed(for text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}

func obfuscate(_ text: String) -> (data: [UInt8], key: [UInt8]) {
    let bytes = Array(text.utf8)
    var generator = XorShift64Star(seed: stableSeed(for: text))
    let key = bytes.map { _ in generator.nextByte() }
    let data = zip(bytes, key).map { $0 ^ $1 }
    return (data, key)
}

func render(_ bytes: [UInt8]) -> String {
    bytes.map { "0x" + String(format: "%02X", $0) }.joined(separator: ", ")
}

guard let rawMode = CommandLine.arguments.dropFirst().first,
      let mode = AccessMode(rawValue: rawMode) else {
    let supported = AccessMode.allCases.map(\.rawValue).joined(separator: ", ")
    fputs("Usage: set-access-mode.swift <\(supported)>\n", stderr)
    exit(1)
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let targetURL = repoRoot.appendingPathComponent("Sources/NiceVoice/ObfuscatedStrings.swift")
let marker = mode.marker
let obfuscated = obfuscate(marker)
let replacement = """
    static var accessModeMarker: String {
        deobfuscate(
            data: [\(render(obfuscated.data))],
            key: [\(render(obfuscated.key))]
        )
    }
"""

let fileContents = try String(contentsOf: targetURL, encoding: .utf8)
let pattern = #"    static var accessModeMarker: String \{\n        deobfuscate\(\n            data: \[[^\]]*\],\n            key: \[[^\]]*\]\n        \)\n    \}"#
let regex = try NSRegularExpression(pattern: pattern)
let range = NSRange(fileContents.startIndex..<fileContents.endIndex, in: fileContents)
let replaced = regex.stringByReplacingMatches(
    in: fileContents,
    options: [],
    range: range,
    withTemplate: replacement
)

guard replaced != fileContents else {
    fputs("Failed to update accessModeMarker block.\n", stderr)
    exit(1)
}

try replaced.write(to: targetURL, atomically: true, encoding: .utf8)
print("Updated access mode to '\(mode.rawValue)' (\(marker)).")
