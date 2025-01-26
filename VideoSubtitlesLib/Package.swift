// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VideoSubtitlesLib",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "VideoSubtitlesLib",
            targets: ["VideoSubtitlesLib"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "VideoSubtitlesLib",
            dependencies: [],
            path: "Sources/VideoSubtitlesLib",
            exclude: [],
            sources: ["Models", "Core", "Services"]
        ),
        .testTarget(
            name: "VideoSubtitlesLibTests",
            dependencies: ["VideoSubtitlesLib"],
            path: "Tests/VideoSubtitlesLibTests",
            exclude: [],
            resources: [
                .copy("TestAssets/Videos/test1.mp4"),
                .copy("TestAssets/Videos/test2.mp4"),
                .copy("TestAssets/Videos/test3.mp4"),
            ]
        ),
    ]
)
