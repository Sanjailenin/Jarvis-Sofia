// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sophia",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Sophia", targets: ["Sophia"])],
    targets: [
        .target(name: "SophiaCore"),
        .executableTarget(name: "Sophia", dependencies: ["SophiaCore"]),
        .testTarget(name: "SophiaCoreTests", dependencies: ["SophiaCore"]),
    ]
)
