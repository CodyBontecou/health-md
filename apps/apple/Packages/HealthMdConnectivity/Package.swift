// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthMdConnectivity",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "HealthMdConnectionCore",
            targets: ["HealthMdConnectionCore"]
        ),
        .library(
            name: "HealthMdDirectClientCore",
            targets: ["HealthMdDirectClientCore"]
        )
    ],
    targets: [
        .target(name: "HealthMdConnectionCore"),
        .target(
            name: "HealthMdDirectClientCore",
            dependencies: ["HealthMdConnectionCore"]
        ),
        .testTarget(
            name: "HealthMdConnectionCoreTests",
            dependencies: ["HealthMdConnectionCore"]
        ),
        .testTarget(
            name: "HealthMdDirectClientCoreTests",
            dependencies: ["HealthMdDirectClientCore"],
            resources: [.copy("Fixtures/markdown-merge-v1.json")]
        )
    ]
)
