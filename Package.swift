// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "shotty",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "shotty", path: "Sources/shotty")
    ]
)
