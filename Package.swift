// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Open1000X",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MDRKit", targets: ["MDRKit"]),
        .executable(name: "mdrctl", targets: ["mdrctl"]),
        .executable(name: "Open1000X", targets: ["Open1000X"]),
    ],
    targets: [
        .target(name: "MDRKit", linkerSettings: [.linkedFramework("IOBluetooth")]),
        .executableTarget(name: "mdrctl", dependencies: ["MDRKit"]),
        .executableTarget(name: "Open1000X", dependencies: ["MDRKit"]),
        .testTarget(name: "MDRKitTests", dependencies: ["MDRKit"]),
    ]
)
