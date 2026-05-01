// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NiceVoice",
    defaultLocalization: "ja",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4"),
    ],
    targets: [
        .executableTarget(
            name: "NiceVoice",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NiceVoiceTests",
            dependencies: [
                "NiceVoice",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
