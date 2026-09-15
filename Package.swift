// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pier",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pier",
            path: "Sources/Pier",
            resources: [.copy("Fonts")]
        )
    ]
)
