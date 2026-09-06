import CommonCrypto
import XCTest
@testable import HealthMd

/// Field-for-field manifest builder tests against the eight registered
/// `ingest-*.json` conformance fixture shapes in
/// `packages/contracts/agent-data/v1/fixtures/`.
final class AgentDataIngestManifestTests: XCTestCase {

    // MARK: - Complete daily manifest (ingest-request-complete.json shape)

    func testCompleteDailyManifestMatchesFixtureShape() throws {
        let artifactBytes = Data(repeating: 0x61, count: 512)
        let manifest = try AgentDataIngestManifestBuilder.manifest(
            kind: .healthDataDaily,
            platform: "apple",
            artifactSchema: "healthmd.health_data",
            artifactSchemaVersion: 8,
            ownerDate: "2026-03-15",
            physicalFormat: .json,
            mediaType: "application/json",
            artifactBytes: artifactBytes
        )

        XCTAssertEqual(manifest.schema, "healthmd.agent_data_ingest")
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.artifactKind, .healthDataDaily)
        XCTAssertEqual(manifest.platform, "apple")
        XCTAssertEqual(manifest.artifactSchema, "healthmd.health_data")
        XCTAssertEqual(manifest.artifactSchemaVersion, 8)
        XCTAssertEqual(manifest.ownerDate, "2026-03-15")
        XCTAssertEqual(manifest.physicalFormat, .json)
        XCTAssertEqual(manifest.mediaType, "application/json")
        XCTAssertEqual(manifest.byteCount, 512)
        XCTAssertEqual(manifest.sha256, AgentDataIngestManifest.sha256(of: artifactBytes))
        XCTAssertEqual(manifest.completeness, .complete)

        // The encoded line mirrors the fixture's field inventory exactly,
        // with sorted keys and no record_count (omitting is always valid).
        let line = String(decoding: try manifest.encodedLine(), as: UTF8.self)
        XCTAssertFalse(line.contains("\n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(line.utf8)
        ) as? [String: Any])
        XCTAssertEqual(object["schema"] as? String, "healthmd.agent_data_ingest")
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["artifact_kind"] as? String, "health_data_daily")
        XCTAssertEqual(object["platform"] as? String, "apple")
        XCTAssertEqual(object["artifact_schema"] as? String, "healthmd.health_data")
        XCTAssertEqual(object["artifact_schema_version"] as? Int, 8)
        XCTAssertEqual(object["owner_date"] as? String, "2026-03-15")
        XCTAssertEqual(object["physical_format"] as? String, "json")
        XCTAssertEqual(object["media_type"] as? String, "application/json")
        XCTAssertEqual(object["byte_count"] as? Int, 512)
        XCTAssertNotNil(object["sha256"] as? String)
        XCTAssertEqual((object["completeness"] as? [String: Any])?["type"] as? String, "complete")
        XCTAssertNil(object["record_count"])
        XCTAssertEqual(Set(object.keys), [
            "schema", "schema_version", "artifact_kind", "platform",
            "artifact_schema", "artifact_schema_version", "owner_date",
            "physical_format", "media_type", "byte_count", "sha256",
            "completeness",
        ])
    }

    // MARK: - Finalized partial (ingest-request-partial.json shape)

    func testFinalizedPartialManifestMatchesFixtureShape() throws {
        let artifactBytes = Data("{}".utf8)
        let manifest = try AgentDataIngestManifestBuilder.manifest(
            kind: .healthDataDaily,
            platform: "android",
            artifactSchema: "healthmd.health_data",
            artifactSchemaVersion: 4,
            ownerDate: "2026-03-16",
            physicalFormat: .json,
            mediaType: "application/json",
            artifactBytes: artifactBytes,
            completeness: .partial(finalized: true, coveredOwnerDates: ["2026-03-16"])
        )

        XCTAssertEqual(
            manifest.completeness,
            .partial(finalized: true, coveredOwnerDates: ["2026-03-16"])
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try manifest.encodedLine()
        ) as? [String: Any])
        let completeness = try XCTUnwrap(object["completeness"] as? [String: Any])
        XCTAssertEqual(completeness["type"] as? String, "partial")
        XCTAssertEqual(completeness["finalized"] as? Bool, true)
        XCTAssertEqual(completeness["covered_owner_dates"] as? [String], ["2026-03-16"])
    }

    func testUnfinalizedPartialIsRejectedByValidation() throws {
        let manifest = AgentDataIngestManifest(
            artifactKind: .healthDataDaily,
            platform: "apple",
            artifactSchema: "healthmd.health_data",
            artifactSchemaVersion: 8,
            ownerDate: "2026-03-16",
            physicalFormat: .json,
            mediaType: "application/json",
            byteCount: 2,
            sha256: AgentDataIngestManifest.sha256(of: Data("{}".utf8)),
            completeness: .partial(finalized: false, coveredOwnerDates: ["2026-03-16"])
        )
        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? AgentDataIngestManifest.ValidationError,
                .unfinalizedPartial
            )
        }
    }

    // MARK: - Raw kinds (ingest-request-raw-complete.json shape)

    func testRawCompleteManifestMatchesFixtureShape() throws {
        let artifactBytes = Data(repeating: 0x63, count: 384)
        let manifest = try AgentDataIngestManifestBuilder.manifest(
            kind: .rawSnapshot,
            platform: "android",
            artifactSchema: "healthmd.raw-snapshot",
            artifactSchemaVersion: 1,
            ownerDate: "2026-03-18",
            physicalFormat: .ndjson,
            mediaType: "application/x-ndjson",
            artifactBytes: artifactBytes
        )

        XCTAssertEqual(manifest.artifactKind, .rawSnapshot)
        XCTAssertEqual(manifest.physicalFormat, .ndjson)
        XCTAssertEqual(manifest.mediaType, "application/x-ndjson")
        XCTAssertEqual(manifest.completeness, .complete)
        XCTAssertEqual(manifest.byteCount, 384)
        XCTAssertEqual(manifest.sha256, AgentDataIngestManifest.sha256(of: artifactBytes))
    }

    func testPartialRawArtifactIsRejectedByValidation() {
        let manifest = AgentDataIngestManifest(
            artifactKind: .rawChanges,
            platform: "android",
            artifactSchema: "healthmd.raw-changes",
            artifactSchemaVersion: 1,
            ownerDate: "2026-03-18",
            physicalFormat: .json,
            mediaType: "application/json",
            byteCount: 2,
            sha256: AgentDataIngestManifest.sha256(of: Data("{}".utf8)),
            completeness: .partial(finalized: true, coveredOwnerDates: ["2026-03-18"])
        )
        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(
                error as? AgentDataIngestManifest.ValidationError,
                .partialRawArtifact
            )
        }
    }

    // MARK: - Integrity over exact bytes

    func testSha256AndByteCountAreComputedOverExactBytes() throws {
        let bytes = Data("{\"schema\":\"healthmd.health_data\"}".utf8)
        let manifest = try AgentDataIngestManifestBuilder.manifest(
            kind: .healthDataDaily,
            platform: "apple",
            artifactSchema: "healthmd.health_data",
            artifactSchemaVersion: 8,
            ownerDate: "2026-03-15",
            physicalFormat: .json,
            mediaType: "application/json",
            artifactBytes: bytes
        )
        XCTAssertEqual(manifest.byteCount, bytes.count)
        // SHA-256 of the exact bytes via an independent implementation.
        XCTAssertEqual(manifest.sha256, CryptoDigestTestHelper.sha256Hex(bytes))

        // A one-byte difference changes the digest.
        var other = bytes
        other.append(0x20)
        let otherManifest = try AgentDataIngestManifestBuilder.manifest(
            kind: .healthDataDaily,
            platform: "apple",
            artifactSchema: "healthmd.health_data",
            artifactSchemaVersion: 8,
            ownerDate: "2026-03-15",
            physicalFormat: .json,
            mediaType: "application/json",
            artifactBytes: other
        )
        XCTAssertNotEqual(manifest.sha256, otherManifest.sha256)
        XCTAssertEqual(otherManifest.byteCount, bytes.count + 1)
    }

    func testFileBackedManifestDigestsExactFileBytes() throws {
        let bytes = Data(repeating: 0x0A, count: 100_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifest-bytes-\(UUID().uuidString).json")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let manifest = try AgentDataIngestManifestBuilder.manifest(
            kind: .healthDataDaily,
            platform: "apple",
            artifactSchema: "healthmd.health_data",
            artifactSchemaVersion: 8,
            ownerDate: "2026-03-15",
            physicalFormat: .json,
            mediaType: "application/json",
            artifactFileURL: url
        )
        XCTAssertEqual(manifest.byteCount, bytes.count)
        XCTAssertEqual(manifest.sha256, CryptoDigestTestHelper.sha256Hex(bytes))
    }

    // MARK: - Validation grammar

    func testValidationRejectsInvalidShapes() {
        func manifest(
            ownerDate: String = "2026-03-15",
            byteCount: Int = 4,
            sha256: String = AgentDataIngestManifest.sha256(of: Data("test".utf8)),
            platform: String = "apple"
        ) -> AgentDataIngestManifest {
            AgentDataIngestManifest(
                artifactKind: .healthDataDaily,
                platform: platform,
                artifactSchema: "healthmd.health_data",
                artifactSchemaVersion: 8,
                ownerDate: ownerDate,
                physicalFormat: .json,
                mediaType: "application/json",
                byteCount: byteCount,
                sha256: sha256,
                completeness: .complete
            )
        }

        XCTAssertThrowsError(try manifest(ownerDate: "2026-3-15").validate())
        XCTAssertThrowsError(try manifest(ownerDate: "not-a-date").validate())
        XCTAssertThrowsError(try manifest(byteCount: 0).validate())
        XCTAssertThrowsError(
            try manifest(byteCount: AgentDataIngestManifest.maximumByteCount + 1).validate()
        )
        XCTAssertThrowsError(try manifest(sha256: "ABC").validate())
        XCTAssertThrowsError(try manifest(sha256: String(repeating: "z", count: 64)).validate())
        XCTAssertThrowsError(try manifest(platform: "watchos").validate())
    }

    func testCoveredOwnerDatesGrammar() {
        func partial(_ covered: [String]) -> AgentDataIngestManifest {
            AgentDataIngestManifest(
                artifactKind: .healthDataDaily,
                platform: "apple",
                artifactSchema: "healthmd.health_data",
                artifactSchemaVersion: 8,
                ownerDate: "2026-03-15",
                physicalFormat: .json,
                mediaType: "application/json",
                byteCount: 4,
                sha256: AgentDataIngestManifest.sha256(of: Data("test".utf8)),
                completeness: .partial(finalized: true, coveredOwnerDates: covered)
            )
        }

        XCTAssertNoThrow(try partial(["2026-03-14", "2026-03-15"]).validate())
        XCTAssertThrowsError(try partial([]).validate())
        XCTAssertThrowsError(try partial(["2026-03-15", "2026-03-15"]).validate())
        XCTAssertThrowsError(
            try partial((0..<(AgentDataIngestManifest.maximumCoveredOwnerDates + 1)).map {
                String(format: "2026-01-%02d", ($0 % 28) + 1)
            }).validate()
        )
    }

    // MARK: - Receipts (ingest-accepted-* and ingest-rejected-* shapes)

    func testDecodesAcceptedCompleteReceiptFixtureGrammar() throws {
        // ingest-accepted-complete.json grammar: stored revision + partition
        // view with complete authority.
        let digest = String(repeating: "d", count: 64)
        let json = """
        {
          "schema": "healthmd.agent_ingest_response",
          "schema_version": 1,
          "outcome": "accepted",
          "stored": {
            "revision_id": "\(digest)",
            "byte_count": 20480,
            "completeness": { "type": "complete" }
          },
          "partition": {
            "owner_date": "2026-03-15",
            "authoritative": {
              "revision_id": "\(digest)",
              "completeness": { "type": "complete" }
            },
            "complete_revision_present": true,
            "partial_revision_present": true
          }
        }
        """
        let receipt = try AgentDataIngestReceipt(decoding: Data(json.utf8))
        XCTAssertEqual(receipt.outcome, .accepted)
        XCTAssertEqual(receipt.stored?.revisionID, digest)
        XCTAssertEqual(receipt.stored?.byteCount, 20_480)
        XCTAssertEqual(receipt.stored?.completeness, .complete)
        XCTAssertEqual(receipt.partitionOwnerDate, "2026-03-15")
        XCTAssertNil(receipt.rejection)
    }

    func testDecodesAcceptedPartialReceiptFixtureGrammar() throws {
        let digest = String(repeating: "e", count: 64)
        let json = """
        {
          "schema": "healthmd.agent_ingest_response",
          "schema_version": 1,
          "outcome": "accepted",
          "stored": {
            "revision_id": "\(digest)",
            "byte_count": 8192,
            "completeness": {
              "type": "partial",
              "finalized": true,
              "covered_owner_dates": ["2026-03-16"]
            }
          },
          "partition": {
            "owner_date": "2026-03-16",
            "authoritative": {
              "revision_id": "\(digest)",
              "completeness": {
                "type": "partial",
                "finalized": true,
                "covered_owner_dates": ["2026-03-16"]
              }
            },
            "complete_revision_present": false,
            "partial_revision_present": true
          }
        }
        """
        let receipt = try AgentDataIngestReceipt(decoding: Data(json.utf8))
        XCTAssertEqual(receipt.outcome, .accepted)
        XCTAssertEqual(
            receipt.stored?.completeness,
            .partial(finalized: true, coveredOwnerDates: ["2026-03-16"])
        )
    }

    func testDecodesRejectedReceiptsForAllFourCodes() throws {
        for code in [
            "truncated", "transient", "checksum_invalid", "manifest_incomplete",
        ] {
            // ingest-rejected-manifest-incomplete.json grammar: the minimal
            // rejection receipt carries only the code.
            let json = """
            {
              "schema": "healthmd.agent_ingest_response",
              "schema_version": 1,
              "outcome": "rejected",
              "rejection": { "code": "\(code)" }
            }
            """
            let receipt = try AgentDataIngestReceipt(decoding: Data(json.utf8))
            XCTAssertEqual(
                receipt.outcome,
                .rejected(try XCTUnwrap(AgentDataIngestRejectionCode(rawValue: code)))
            )
            XCTAssertNil(receipt.stored)
        }
        // ingest-rejected-checksum-invalid.json grammar: rejection plus the
        // authoritative partition view of already-stored content.
        let json = """
        {
          "schema": "healthmd.agent_ingest_response",
          "schema_version": 1,
          "outcome": "rejected",
          "rejection": { "code": "checksum_invalid" },
          "partition": {
            "owner_date": "2026-03-17",
            "authoritative": {
              "revision_id": "\(String(repeating: "f", count: 64))",
              "completeness": { "type": "complete" }
            },
            "complete_revision_present": true,
            "partial_revision_present": false
          }
        }
        """
        let receipt = try AgentDataIngestReceipt(decoding: Data(json.utf8))
        XCTAssertEqual(receipt.outcome, .rejected(.checksumInvalid))
        XCTAssertEqual(receipt.partitionOwnerDate, "2026-03-17")
    }

    func testRejectsMalformedReceipts() {
        let cases: [(String, AgentDataIngestReceipt.DecodingError)] = [
            (
                """
                {"schema":"healthmd.other","schema_version":1,"outcome":"accepted",
                 "stored":{"revision_id":"\(String(repeating: "d", count: 64))","byte_count":1,"completeness":{"type":"complete"}}}
                """,
                .wrongSchema
            ),
            (
                """
                {"schema":"healthmd.agent_ingest_response","schema_version":2,"outcome":"rejected","rejection":{"code":"truncated"}}
                """,
                .wrongSchemaVersion
            ),
            (
                """
                {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"maybe"}
                """,
                .invalidOutcome
            ),
            (
                """
                {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"rejected"}
                """,
                .missingRejection
            ),
            (
                """
                {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"rejected","rejection":{"code":"no_sother_code"}}
                """,
                .missingRejection
            ),
            (
                """
                {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"accepted"}
                """,
                .missingStored
            ),
            (
                """
                {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"accepted",
                 "stored":{"revision_id":"\(String(repeating: "d", count: 64))","byte_count":1,"completeness":{"type":"complete"}},
                 "rejection":{"code":"truncated"}}
                """,
                .rejectionOnAccepted
            ),
            (
                """
                {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"rejected",
                 "rejection":{"code":"truncated"},
                 "stored":{"revision_id":"\(String(repeating: "d", count: 64))","byte_count":1,"completeness":{"type":"complete"}}}
                """,
                .storedOnRejected
            ),
        ]
        for (json, expected) in cases {
            XCTAssertThrowsError(try AgentDataIngestReceipt(decoding: Data(json.utf8))) { error in
                XCTAssertEqual(error as? AgentDataIngestReceipt.DecodingError, expected, "for \(json.prefix(60))")
            }
        }
    }

    func testFixAndReuploadClassification() {
        XCTAssertTrue(AgentDataIngestRejectionCode.truncated.isFixAndReupload)
        XCTAssertTrue(AgentDataIngestRejectionCode.checksumInvalid.isFixAndReupload)
        XCTAssertTrue(AgentDataIngestRejectionCode.manifestIncomplete.isFixAndReupload)
        XCTAssertFalse(AgentDataIngestRejectionCode.transient.isFixAndReupload)
    }
}

/// Independent SHA-256 reference for digest assertions (CommonCrypto, a
/// second implementation distinct from the manifest's CryptoKit digest).
enum CryptoDigestTestHelper {
    static func sha256Hex(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
