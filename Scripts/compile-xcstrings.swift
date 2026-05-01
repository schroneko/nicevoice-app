import Foundation

enum CompileError: Error, CustomStringConvertible {
    case usage
    case invalidCatalog

    var description: String {
        switch self {
        case .usage:
            return "Usage: swift Scripts/compile-xcstrings.swift <Localizable.xcstrings> <output-resources-dir>"
        case .invalidCatalog:
            return "Invalid string catalog"
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    throw CompileError.usage
}

let catalogURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
let data = try Data(contentsOf: catalogURL)

guard
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
    let strings = root["strings"] as? [String: Any]
else {
    throw CompileError.invalidCatalog
}

func escapedStringsValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}

func plistEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func formatValueType(for key: String) -> String {
    if key.contains("%lld") {
        return "lld"
    }

    if key.contains("%d") {
        return "d"
    }

    return "d"
}

func localizedStringUnit(from localization: [String: Any]) -> String? {
    guard
        let stringUnit = localization["stringUnit"] as? [String: Any],
        let value = stringUnit["value"] as? String
    else {
        return nil
    }

    return value
}

func pluralVariants(from localization: [String: Any]) -> [String: String]? {
    guard
        let variations = localization["variations"] as? [String: Any],
        let plural = variations["plural"] as? [String: Any]
    else {
        return nil
    }

    var variants: [String: String] = [:]

    for (rule, rawRuleValue) in plural {
        guard
            let ruleValue = rawRuleValue as? [String: Any],
            let value = localizedStringUnit(from: ruleValue)
        else {
            continue
        }

        variants[rule] = value
    }

    return variants.isEmpty ? nil : variants
}

let enOutputURL = outputURL.appendingPathComponent("en.lproj", isDirectory: true)
try FileManager.default.createDirectory(at: enOutputURL, withIntermediateDirectories: true)

var stringsLines: [String] = []
var stringsDictEntries: [String] = []

for key in strings.keys.sorted() {
    guard
        let entry = strings[key] as? [String: Any],
        let localizations = entry["localizations"] as? [String: Any],
        let en = localizations["en"] as? [String: Any]
    else {
        continue
    }

    if let variants = pluralVariants(from: en) {
        var variantLines: [String] = []
        for rule in variants.keys.sorted() {
            guard let value = variants[rule] else {
                continue
            }

            variantLines.append("""
                    <key>\(plistEscaped(rule))</key>
                    <string>\(plistEscaped(value))</string>
            """)
        }

        stringsDictEntries.append("""
            <key>\(plistEscaped(key))</key>
            <dict>
                <key>NSStringLocalizedFormatKey</key>
                <string>%#@value@</string>
                <key>value</key>
                <dict>
                    <key>NSStringFormatSpecTypeKey</key>
                    <string>NSStringPluralRuleType</string>
                    <key>NSStringFormatValueTypeKey</key>
                    <string>\(formatValueType(for: key))</string>
        \(variantLines.joined(separator: "\n"))
                </dict>
            </dict>
        """)
        continue
    }

    if let value = localizedStringUnit(from: en) {
        stringsLines.append("\"\(escapedStringsValue(key))\" = \"\(escapedStringsValue(value))\";")
    }
}

let stringsContent = stringsLines.joined(separator: "\n") + "\n"
try stringsContent.write(
    to: enOutputURL.appendingPathComponent("Localizable.strings"),
    atomically: true,
    encoding: .utf8
)

if stringsDictEntries.isEmpty == false {
    let stringsDictContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \(stringsDictEntries.joined(separator: "\n"))
    </dict>
    </plist>
    """

    try stringsDictContent.write(
        to: enOutputURL.appendingPathComponent("Localizable.stringsdict"),
        atomically: true,
        encoding: .utf8
    )
}
