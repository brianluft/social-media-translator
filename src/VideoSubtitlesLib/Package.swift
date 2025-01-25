// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "VideoSubtitlesLib",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "VideoSubtitlesLib",
            targets: ["VideoSubtitlesLib"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "VideoSubtitlesLib",
            dependencies: []),
        .testTarget(
            name: "VideoSubtitlesLibTests",
            dependencies: ["VideoSubtitlesLib"]),
    ]
) 