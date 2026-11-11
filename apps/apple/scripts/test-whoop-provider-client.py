#!/usr/bin/env python3
"""Run the WHOOP URLSession seam tests without building an app or using HealthKit.

The temporary Swift package copies production sources and the existing XCTest
suite unchanged. Its URLProtocol intercepts every request; no provider service
or credentials are used. Only the standalone timestamp enum is extracted from
the HealthKit serializer, whose other types require the app's native build.
"""

import argparse
import pathlib
import shutil
import subprocess


APPLE_ROOT = pathlib.Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--filter", help="XCTest name regex (default: entire client suite)")
    parser.add_argument(
        "--scratch-path",
        type=pathlib.Path,
        default=APPLE_ROOT / ".build" / "whoop-provider-client-tests",
    )
    args = parser.parse_args()
    package = args.scratch_path.resolve()
    sources = package / "Sources" / "HealthMd"
    tests = package / "Tests" / "HealthMdTests"
    sources.mkdir(parents=True, exist_ok=True)
    tests.mkdir(parents=True, exist_ok=True)
    for relative in [
        "HealthMd/Shared/Integrations/ExternalIntegrationModels.swift",
        "HealthMd/Shared/Integrations/ExternalProviderAPIClient.swift",
        "HealthMd/Shared/Integrations/WHOOPProviderSections.swift",
        "HealthMd/Shared/Utilities/BoundedURLSessionDataLoader.swift",
    ]:
        source = APPLE_ROOT / relative
        shutil.copyfile(source, sources / source.name)
    serializer = (
        APPLE_ROOT / "HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift"
    ).read_text()
    start = serializer.index("nonisolated enum CanonicalRFC3339UTC {")
    end = serializer.index("\n}\n", start) + len("\n}\n")
    (sources / "CanonicalRFC3339UTC.swift").write_text(
        "import Foundation\n\n" + serializer[start:end]
    )
    for relative in [
        "HealthMdTests/Integrations/WHOOPProviderAPIClientTests.swift",
        "HealthMdTests/Support/ExternalIntegrationURLProtocolStub.swift",
    ]:
        source = APPLE_ROOT / relative
        shutil.copyfile(source, tests / source.name)
    (package / "Package.swift").write_text(
        '// swift-tools-version: 6.0\n'
        'import PackageDescription\n'
        # Match the app/test targets' Swift 5, MainActor-default, approachable
        # concurrency settings; this remains a Foundation-only host package.
        'let settings: [SwiftSetting] = [\n'
        '    .unsafeFlags(["-default-isolation", "MainActor"]),\n'
        '    .enableUpcomingFeature("DisableOutwardActorInference"),\n'
        '    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),\n'
        '    .enableUpcomingFeature("InferIsolatedConformances"),\n'
        '    .enableUpcomingFeature("InferSendableFromCaptures"),\n'
        '    .enableUpcomingFeature("MemberImportVisibility"),\n'
        '    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),\n'
        ']\n'
        'let package = Package(name: "WHOOPProviderClientTests", '
        'platforms: [.macOS(.v13)], targets: [\n'
        '    .target(name: "HealthMd", swiftSettings: settings),\n'
        '    .testTarget(name: "HealthMdTests", dependencies: ["HealthMd"], '
        'swiftSettings: settings),\n'
        '], swiftLanguageModes: [.v5])\n'
    )
    # Release configuration omits the app-only DEBUG performance telemetry.
    command = [
        "swift", "test", "--package-path", str(package),
        "--configuration", "release", "--jobs", "2",
    ]
    if args.filter:
        command += ["--filter", args.filter]
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
