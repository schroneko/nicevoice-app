// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NiceVoice",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    ],
    targets: [
        .executableTarget(
            name: "NiceVoice",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            resources: [
                .process("Resources")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
