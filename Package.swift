// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AntigravityMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AntigravityMenuBar", targets: ["AntigravityMenuBar"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AntigravityMenuBar",
            dependencies: []
        )
    ]
)
