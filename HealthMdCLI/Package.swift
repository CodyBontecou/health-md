// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthMdCLI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "healthmd", targets: ["healthmd"])
    ],
    targets: [
        .executableTarget(
            name: "healthmd",
            path: "Sources/healthmd"
        )
    ]
)
