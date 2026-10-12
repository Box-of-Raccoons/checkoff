// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Checkoff",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CheckoffCore"),
        .executableTarget(
            name: "Checkoff",
            dependencies: ["CheckoffCore"]
        ),
        .testTarget(
            name: "CheckoffCoreTests",
            dependencies: ["CheckoffCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
