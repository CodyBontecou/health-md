import Foundation
import XCTest
@testable import HealthMdConnectionCore

final class ExportHistoryObservationTests: XCTestCase {
    private func observation() throws -> ExportHistoryObservation {
        try ExportHistoryObservation(
            observationID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            operationID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            observedAt: "2026-10-23T12:00:00.000000000Z",
            requestBindingSHA256: String(repeating: "a", count: 64),
            sourceInstallationID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            destinationInstallationID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            timeZoneIdentifier: "America/Puerto_Rico", metricIDs: ["activeEnergy", "steps"],
            requestedStart: "2026-01-01T04:00:00.000000000Z",
            requestedEnd: "2026-10-23T04:00:00.000000000Z", allAvailable: true,
            rangeSemantics: "owner_dates", evidenceMethod: "healthkit_earliest_authorized_sample_date",
            types: [
                .init(typeID: "HKQuantityTypeIdentifierActiveEnergyBurned", directMetricIDs: ["activeEnergy"], outcome: "unknown"),
                .init(typeID: "HKQuantityTypeIdentifierStepCount", directMetricIDs: ["steps"], outcome: "limited",
                      sampleEndBoundary: "2026-09-23T12:34:56.123456789Z")
            ])
    }

    func testSwiftGeneratedContractFixtureAndRoundTrip() throws {
        let value = try observation()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        let fixture = root.appendingPathComponent("packages/contracts/export-history/v1/synthetic-observation.json")
        if ProcessInfo.processInfo.environment["HEALTHMD_UPDATE_EXPORT_HISTORY_FIXTURE"] == "1" {
            try data.write(to: fixture, options: .atomic)
        }
        let committed = try Data(contentsOf: fixture)
        let rustMirror = root.appendingPathComponent("packages/healthmd-core-rust/crates/healthmd-protocol/tests/fixtures/export-history-v1.json")
        XCTAssertEqual(try Data(contentsOf: rustMirror), committed)
        XCTAssertEqual(committed, data)
        XCTAssertEqual(try JSONDecoder().decode(ExportHistoryObservation.self, from: committed), value)
        XCTAssertEqual(try JSONDecoder().decode(ExportHistoryObservation.self, from: data), value)
    }

    func testObservationIsBoundToImmutableDirectJobAndScope() throws {
        let original = try observation()
        let request = DirectExportRequest(jobID: UUID(uuidString: original.operationID)!,
            createdAt: Date(timeIntervalSince1970: 1_792_756_800), dateSelection: .allAvailable,
            responseMode: .rawJSON, rawProfile: .healthDataProjection,
            canonicalSelection: .init(metricIDs: original.metricIDs, detailLevel: .summary))
        let binding = DirectPeerBinding(sourceInstallationID: UUID(uuidString: original.sourceInstallationID!)!,
            destinationInstallationID: UUID(uuidString: original.destinationInstallationID!)!)
        let session = try DirectTransferSession(sessionID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            jobID: request.jobID, requestFingerprint: DirectRequestFingerprint.make(for: request),
            peerBinding: binding, partitionTargetBytes: DirectTransferLimits.minimumPartitionBytes,
            createdAt: request.createdAt)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["request_binding_sha256"] = session.requestFingerprint.sha256
        func decoded(_ object: [String: Any]) throws -> ExportHistoryObservation {
            try JSONDecoder().decode(ExportHistoryObservation.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let bound = try decoded(object)
        let accepted = DirectExportAccepted(jobID: request.jobID, acceptedAt: request.createdAt,
            peerBinding: binding, resolvedDateIdentifiers: ["2026-01-01", "2026-10-23"],
            sourceTimeZoneIdentifier: original.timeZoneIdentifier,
            resolvedCanonicalSelection: request.canonicalSelection, historyObservation: bound)
        XCTAssertTrue(bound.matches(request: request, accepted: accepted, session: session))
        for selection in [nil, DirectCanonicalSelection(metricIDs: ["other_metric"], detailLevel: .summary)] {
            let changed = DirectExportAccepted(jobID: request.jobID, acceptedAt: request.createdAt,
                peerBinding: binding, resolvedDateIdentifiers: accepted.resolvedDateIdentifiers,
                sourceTimeZoneIdentifier: original.timeZoneIdentifier,
                resolvedCanonicalSelection: selection, historyObservation: bound)
            XCTAssertFalse(bound.matches(request: request, accepted: changed, session: session))
        }
        for (key, value) in [
            ("operation_id", "66666666-6666-4666-8666-666666666666"),
            ("source_installation_id", "66666666-6666-4666-8666-666666666666"),
            ("request_binding_sha256", String(repeating: "b", count: 64)),
            ("requested_start", "2026-01-02T04:00:00.000000000Z"),
            ("time_zone_identifier", "UTC")
        ] {
            var changed = object
            changed[key] = value
            XCTAssertFalse(try decoded(changed).matches(request: request, accepted: accepted, session: session))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func json<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value)) }
        let fixtureData = try JSONSerialization.data(withJSONObject: [
            "request": json(request), "accepted": json(accepted), "session": json(session),
            "capabilities": json(DirectPeerCapabilities(platform: .iOS, installationID: binding.sourceInstallationID,
                exportHistoryObservationVersions: [1]))
        ], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        let fixture = root.appendingPathComponent("packages/contracts/export-history/v1/synthetic-direct-job.json")
        if ProcessInfo.processInfo.environment["HEALTHMD_UPDATE_EXPORT_HISTORY_FIXTURE"] == "1" {
            try fixtureData.write(to: fixture, options: .atomic)
        }
        XCTAssertEqual(try Data(contentsOf: fixture), fixtureData)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("apps/cli/crates/healthmd-client/tests/fixtures/export-history-direct-job-v1.json")), fixtureData)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("packages/healthmd-core-rust/crates/healthmd-protocol/tests/fixtures/export-history-direct-job-v1.json")), fixtureData)
    }

    func testRejectsFullClaimsAndMalformedEvidenceAtDecode() throws {
        let encoded = try JSONEncoder().encode(observation())
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        func rejects(_ edit: (inout [String: Any]) -> Void) throws {
            var changed = original
            edit(&changed)
            let data = try JSONSerialization.data(withJSONObject: changed)
            XCTAssertThrowsError(try JSONDecoder().decode(ExportHistoryObservation.self, from: data))
        }
        try rejects { $0["schema_version"] = 2 }
        try rejects { $0["full_history"] = true }
        try rejects { $0["metric_ids"] = ["steps", "activeEnergy"] }
        try rejects { $0["metric_ids"] = ["activeEnergy", "steps", "unattributed"] }
        try rejects { $0["request_binding_sha256"] = String(repeating: "A", count: 64) }
        try rejects { $0["destination_installation_id"] = NSNull() }
        try rejects { $0["time_zone_identifier"] = "Unknown/Timezone" }
        try rejects { $0["requested_start"] = "2027-01-01T00:00:00.000000000Z" }
        try rejects { $0["observed_at"] = "nan" }
        try rejects { $0["observed_at"] = "2026-02-30T12:00:00.000000000Z" }
        try rejects { $0["requested_start"] = "2026-10-23T04:00:00.000000001Z" }
        try rejects {
            var rows = $0["types"] as! [[String: Any]]
            rows.append(["type_id": "unrelated", "direct_metric_ids": [], "dependency_metric_ids": [],
                         "dependency_reasons": [], "outcome": "limited",
                         "sample_end_boundary": "2026-09-23T12:00:00.000000000Z"])
            $0["types"] = rows
        }
        try rejects {
            var rows = $0["types"] as! [[String: Any]]
            rows[0]["dependency_reasons"] = ["unrelated_reason"]
            $0["types"] = rows
        }
        for outcome in ["full", "denied", "complete"] {
            try rejects {
                var rows = $0["types"] as! [[String: Any]]
                rows[0]["outcome"] = outcome
                $0["types"] = rows
            }
        }
        try rejects {
            var rows = $0["types"] as! [[String: Any]]
            rows[0]["sample_end_boundary"] = "2026-09-23T12:00:00.000000000Z"
            $0["types"] = rows
        }
        try rejects {
            var rows = $0["types"] as! [[String: Any]]
            rows[1].removeValue(forKey: "sample_end_boundary")
            $0["types"] = rows
        }
    }

    func testDependencyAttributionCannotEscapeSelection() throws {
        let data = try JSONEncoder().encode(observation())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = object["types"] as! [[String: Any]]
        rows[0]["dependency_metric_ids"] = ["heartRate"]
        object["types"] = rows
        XCTAssertThrowsError(try JSONDecoder().decode(ExportHistoryObservation.self,
            from: JSONSerialization.data(withJSONObject: object)))
    }
}
