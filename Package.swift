// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NiceVoice",
    platforms: [.macOS(.v26)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NiceVoice",
            dependencies: []
        )
    ],
    swiftLanguageModes: [.v5]
)
