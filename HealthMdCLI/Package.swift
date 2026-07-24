// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthMdCLI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "healthmd", targets: ["healthmd"]),
        .executable(name: "healthmd-mcp", targets: ["healthmd-mcp"])
    ],
    dependencies: [
        .package(path: "../Packages/HealthMdConnectivity")
    ],
    targets: [
        .executableTarget(
            name: "healthmd",
            dependencies: [
                .product(name: "HealthMdConnectionCore", package: "HealthMdConnectivity"),
                .product(name: "HealthMdDirectClientCore", package: "HealthMdConnectivity")
            ],
            path: "Sources/healthmd"
        ),
        .target(
            name: "HealthMdMCPCore",
            path: "Sources/HealthMdMCPCore"
        ),
        .executableTarget(
            name: "healthmd-mcp",
            dependencies: ["HealthMdMCPCore"],
            path: "Sources/healthmd-mcp"
        ),
        .testTarget(
            name: "HealthMdCLITests",
            dependencies: ["healthmd", "HealthMdMCPCore"],
            path: "Tests/HealthMdCLITests"
        )
    ]
)
