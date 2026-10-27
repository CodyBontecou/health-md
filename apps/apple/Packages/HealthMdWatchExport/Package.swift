// swift-tools-version: 5.9
import PackageDescription

// The Watch target compiles these same sources directly. Host tests need no app,
// HealthKit entitlement, Rust artifact, or third-party dependency.
let package = Package(
    name: "HealthMdWatchExport",
    platforms: [.macOS(.v13), .watchOS(.v10)],
    products: [.library(name: "HealthMdWatchExport", targets: ["HealthMdWatchExport"])],
    targets: [
        .target(name: "HealthMdWatchExport"),
        .testTarget(name: "HealthMdWatchExportTests", dependencies: ["HealthMdWatchExport"],
                    resources: [.copy("Fixtures/watch-snapshot-v1.json")])
    ]
)
