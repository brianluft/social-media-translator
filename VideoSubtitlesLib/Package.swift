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
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "VideoSubtitlesLib",
            dependencies: ["SwiftSoup"],
            path: "Sources/VideoSubtitlesLib",
            exclude: [],
            sources: ["Models", "Core", "Services", "Player"]
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
