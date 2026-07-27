// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthMdCoreRust",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "HealthMdCoreRust",
            targets: ["HealthMdCoreRust"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "HealthmdCoreFFI",
            path: "Artifacts/HealthmdCore.xcframework"
        ),
        .target(
            name: "HealthMdCoreRust",
            dependencies: ["HealthmdCoreFFI"]
        ),
        .testTarget(
            name: "HealthMdCoreRustTests",
            dependencies: ["HealthMdCoreRust"]
        )
    ]
)
