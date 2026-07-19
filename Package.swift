// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lyrify",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LyrifyCore"),
        .executableTarget(
            name: "LyrifyApp",
            dependencies: ["LyrifyCore"]
        ),
        .testTarget(
            name: "LyrifyCoreTests",
            dependencies: ["LyrifyCore"]
        ),
    ]
)
