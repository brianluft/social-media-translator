// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "BuildTools",
    platforms: [.macOS(.v10_11)],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.2"),
    ],
    targets: [.target(name: "BuildTools", path: "")]
)
