// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NiceVoice",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NiceVoice",
            dependencies: [],
            resources: [
                .process("punctuation-rules.json")
            ]
        )
    ]
)
