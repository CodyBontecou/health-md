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
    targets: [
        .executableTarget(
            name: "healthmd",
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
