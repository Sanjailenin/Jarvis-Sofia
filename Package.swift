// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sofia",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Sofia", targets: ["Sofia"])],
    targets: [
        .target(name: "SofiaCore"),
        .executableTarget(name: "Sofia", dependencies: ["SofiaCore"]),
        .testTarget(name: "SofiaCoreTests", dependencies: ["SofiaCore"]),
    ]
)
