#!/usr/bin/env swift

import Foundation

struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogString]
}

struct CatalogString: Decodable {
    let localizations: [String: Localization]?
}

struct Localization: Decodable {
    let stringUnit: StringUnit?
    let variations: Variations?
}

struct Variations: Decodable {
    let plural: [String: PluralVariant]?
}

struct PluralVariant: Decodable {
    let stringUnit: StringUnit?
}

struct StringUnit: Decodable {
    let state: String?
    let value: String
}

func usage() -> Never {
    FileHandle.standardError.write(Data("Usage: compile-xcstrings.swift <Localizable.xcstrings> <resources-output-dir>\n".utf8))
    exit(64)
}

func stringsEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}

func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

func valueType(for key: String) -> String {
    if key.contains("%lld") { return "lld" }
    if key.contains("%ld") { return "ld" }
    if key.contains("%d") { return "d" }
    if key.contains("%@") { return "@" }
    return "d"
}

func writeStrings(_ entries: [(String, String)], to url: URL) throws {
    let body = entries
        .sorted { $0.0 < $1.0 }
        .map { "\"\(stringsEscape($0.0))\" = \"\(stringsEscape($0.1))\";" }
        .joined(separator: "\n")
    try body.appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

func writeStringsdict(_ entries: [(String, [String: String])], to url: URL) throws {
    var lines: [String] = [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"https://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
        "<plist version=\"1.0\">",
        "<dict>"
    ]

    for (key, variants) in entries.sorted(by: { $0.0 < $1.0 }) {
        lines.append("  <key>\(xmlEscape(key))</key>")
        lines.append("  <dict>")
        lines.append("    <key>NSStringLocalizedFormatKey</key>")
        lines.append("    <string>%#@value@</string>")
        lines.append("    <key>value</key>")
        lines.append("    <dict>")
        lines.append("      <key>NSStringFormatSpecTypeKey</key>")
        lines.append("      <string>NSStringPluralRuleType</string>")
        lines.append("      <key>NSStringFormatValueTypeKey</key>")
        lines.append("      <string>\(xmlEscape(valueType(for: key)))</string>")
        for category in variants.keys.sorted() {
            guard let value = variants[category] else { continue }
            lines.append("      <key>\(xmlEscape(category))</key>")
            lines.append("      <string>\(xmlEscape(value))</string>")
        }
        lines.append("    </dict>")
        lines.append("  </dict>")
    }

    lines.append("</dict>")
    lines.append("</plist>")
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

let args = CommandLine.arguments
guard args.count == 3 else {
    usage()
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let data = try Data(contentsOf: inputURL)
let catalog = try JSONDecoder().decode(Catalog.self, from: data)
let fileManager = FileManager.default
var stringsByLanguage: [String: [(String, String)]] = [:]
var pluralsByLanguage: [String: [(String, [String: String])]] = [:]

for (key, entry) in catalog.strings {
    guard let localizations = entry.localizations else { continue }
    for (language, localization) in localizations where language != catalog.sourceLanguage {
        if let value = localization.stringUnit?.value {
            stringsByLanguage[language, default: []].append((key, value))
        }

        if let plural = localization.variations?.plural {
            let variants = plural.reduce(into: [String: String]()) { result, item in
                if let value = item.value.stringUnit?.value {
                    result[item.key] = value
                }
            }
            if !variants.isEmpty {
                pluralsByLanguage[language, default: []].append((key, variants))
            }
        }
    }
}

let languages = Set(stringsByLanguage.keys).union(pluralsByLanguage.keys)
for language in languages {
    let languageDirectory = outputURL.appendingPathComponent("\(language).lproj", isDirectory: true)
    try fileManager.createDirectory(at: languageDirectory, withIntermediateDirectories: true)

    let stringsURL = languageDirectory.appendingPathComponent("Localizable.strings")
    try writeStrings(stringsByLanguage[language] ?? [], to: stringsURL)

    let stringsdictURL = languageDirectory.appendingPathComponent("Localizable.stringsdict")
    if let pluralEntries = pluralsByLanguage[language], !pluralEntries.isEmpty {
        try writeStringsdict(pluralEntries, to: stringsdictURL)
    } else if fileManager.fileExists(atPath: stringsdictURL.path) {
        try fileManager.removeItem(at: stringsdictURL)
    }
}
