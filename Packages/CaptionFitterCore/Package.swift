// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptionFitterCore",
    defaultLocalization: "zh-Hant",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CaptionFitterCore", targets: ["CaptionFitterCore"]),
        .executable(name: "captionfitter-cli", targets: ["captionfitter-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "CaptionFitterCore",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")]
        ),
        .executableTarget(
            name: "captionfitter-cli",
            dependencies: ["CaptionFitterCore"]
        ),
        .testTarget(
            name: "CaptionFitterCoreTests",
            dependencies: ["CaptionFitterCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
