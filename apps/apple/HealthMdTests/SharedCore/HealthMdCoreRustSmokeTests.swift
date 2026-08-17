import Foundation
import HealthMdCoreRust
import XCTest

/// Exercises only synthetic, health-free Milestone 1 data through the Apple UniFFI boundary.
final class HealthMdCoreRustSmokeTests: XCTestCase {
    private let service = HealthMdCoreService()

    func testBuildInfoReportsIndependentInternalVersions() throws {
        let info = try service.buildInfo()

        XCTAssertEqual(info.crateVersion, "0.1.0-alpha.1")
        XCTAssertFalse(info.coreSourceRevision.isEmpty)
        XCTAssertEqual(info.registrySha256.count, 64)
        XCTAssertEqual(info.coreApiVersion, 4)
        XCTAssertEqual(info.semanticInputVersion, 1)
        XCTAssertEqual(info.canonicalModelVersion, 1)
        XCTAssertEqual(info.registryVersion, 1)
        XCTAssertEqual(info.renderInputVersion, 1)
        XCTAssertEqual(info.artifactPlanVersion, 1)
        XCTAssertEqual(info.renderProfileRevision, 2)
        XCTAssertEqual(info.persistedStateVersion, 1)
    }

    func testEmbeddedSelfTestPassesWithoutHealthData() throws {
        let report = try service.selfTest()

        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.buildInfo, try service.buildInfo())
        XCTAssertEqual(report.fixture.fixtureFormatVersion, 1)
        XCTAssertEqual(report.fixture.byteCount, 152)
        XCTAssertEqual(
            report.fixture.sha256,
            "afb53fde32e77e4b8272f021c262a42b7f943f8604ca7fde4c6dbf7ed977a799"
        )
    }

    func testRegistrySnapshotLoadsThroughPackagedNativeCore() throws {
        let snapshot = try service.metricRegistry(profile: .appleHealthDataV7)

        XCTAssertEqual(snapshot.registrySha256, try service.buildInfo().registrySha256)
        XCTAssertEqual(snapshot.profileId, "apple_health_data_v7")
        XCTAssertEqual(snapshot.publicSchemaVersion, 8)
        XCTAssertEqual(snapshot.metrics.count, 230)
        XCTAssertEqual(snapshot.outputs.count, 226)
    }

    func testLegacyMarkdownMergeUsesAppleProfileAndRejectsAmbiguousYAML() throws {
        let merged = try service.mergeMarkdown(
            existing: "---\ntags:\n  - personal\nkeep: unchanged\n---\n## Sleep\nold\n## Notes\nkeep\n",
            generated: "---\ntags:\n  - healthmd\n---\n## Sleep\nnew\n"
        )
        XCTAssertEqual(
            merged,
            "---\ntags:\n  - healthmd\nkeep: unchanged\n---\n## Sleep\nnew\n## Notes\nkeep\n"
        )

        XCTAssertThrowsError(
            try service.mergeMarkdown(
                existing: "---\n? \"steps\"\n: 100\nkeep: unchanged\n---\n",
                generated: "---\nsteps: 300\n---\n"
            )
        ) { error in
            XCTAssertEqual(error as? HealthMdRenderServiceError, .invalidArtifact)
        }
    }

    func testMalformedSyntheticFixtureReturnsStableHealthFreeError() {
        let malformedFixture = Data("not-json\n".utf8)

        XCTAssertThrowsError(
            try service.validateFixture(
                malformedFixture,
                expectedSHA256: "60498ebafa3f473a2a72c1242e8c3202bf50a6d81dfc721958be1550f46faf33"
            )
        ) { error in
            let serviceError = error as? HealthMdCoreServiceError
            XCTAssertEqual(serviceError, .invalidFixture)
            XCTAssertEqual(serviceError?.code, "invalid_fixture")
            XCTAssertEqual(serviceError?.message, "fixture envelope is invalid")
            XCTAssertFalse(error.localizedDescription.contains("not-json"))
        }
    }
}
