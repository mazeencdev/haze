// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Haze",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Haze", path: "Sources/Haze")
    ],
    swiftLanguageModes: [.v5]
)
