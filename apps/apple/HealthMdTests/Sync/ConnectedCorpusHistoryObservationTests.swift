import Foundation
import HealthMdConnectionCore
import XCTest
@testable import HealthMd

@MainActor
private enum ObservedContextTestSettings {
    // STATIC RETENTION JUSTIFICATION: Combine-backed settings fixtures have a
    // platform-specific iOS Simulator teardown crash; preserve their lifetime.
    static var retained: [AdvancedExportSettings] = []
}

@MainActor
func makeObservedContextTestFixture() throws -> (manifest: ConnectedCorpusExportManifest,
                                                session: ConnectedCorpusTransferSession, date: Date) {
    let defaults = UserDefaults(suiteName: "ObservedContextTests.\(UUID())")!
    let settings = AdvancedExportSettings(userDefaults: defaults)
    ObservedContextTestSettings.retained.append(settings)
    settings.metricSelection.enabledMetrics = ["steps"]
    settings.exportFormats = [.json]
    settings.filenameFormat = "{date}"
    settings.folderStructure = ""
    settings.generateRangeSummary = false
    settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")
    let date = Date(timeIntervalSince1970: 1_776_384_000)
    let now = Date()
    var manifest = ConnectedCorpusExportManifest(mode: .encryptedContext, createdAt: now,
        sourceDeviceName: "Synthetic iPhone", sourceTimeZoneIdentifier: "UTC",
        dateRangeStart: date, dateRangeEnd: date, requestedDates: [date],
        requestedDateIdentifiers: ["2026-04-17"], transferDates: [date],
        settingsSnapshot: .from(settings, calendarTimeZoneIdentifier: "UTC"),
        canonicalSelection: CanonicalHealthDataSelection(metricIDs: ["steps"], sourceIDs: ["apple_health"]),
        selectedSourceIDs: ["apple_health"], requestedTarget: nil)
    let jobID = UUID()
    let binding = ConnectedCorpusPeerBinding(sourceInstallationID: UUID(), destinationInstallationID: UUID())
    manifest.historyObservation = try ExportHistoryObservation(observationID: UUID(), operationID: jobID,
        observedAt: CanonicalRFC3339UTC.string(from: now), requestBindingSHA256: manifest.historyRequestBinding(),
        sourceInstallationID: binding.sourceInstallationID, destinationInstallationID: binding.destinationInstallationID,
        timeZoneIdentifier: "UTC", metricIDs: ["steps"],
        requestedStart: "2026-04-17T00:00:00.000000000Z", requestedEnd: "2026-04-17T00:00:00.000000000Z",
        allAvailable: false, rangeSemantics: "owner_dates", evidenceMethod: "healthkit_earliest_authorized_sample_date",
        types: [ExportHistoryTypeObservation(typeID: "HKQuantityTypeIdentifierStepCount", directMetricIDs: ["steps"],
            outcome: "limited", sampleEndBoundary: "2026-04-17T12:00:00.000000000Z")])
    let session = ConnectedCorpusTransferSession(sessionID: UUID(), jobID: jobID,
        requestFingerprint: try .make(for: manifest), protocolVersion: 2,
        partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes,
        createdAt: now, peerBinding: binding)
    return (manifest, session, date)
}

@MainActor
final class ConnectedCorpusHistoryObservationTests: XCTestCase {
    func testBilateralVersionNegotiationAndLegacyCapabilityBytes() throws {
        let legacy = ConnectedCorpusTransferCapabilities(protocolVersions: [2])
        let supported = ConnectedCorpusTransferCapabilities(protocolVersions: [2], contextHistoryObservationVersion: 1)
        let unknown = ConnectedCorpusTransferCapabilities(protocolVersions: [2], contextHistoryObservationVersion: 2)
        XCTAssertNil(ConnectedCorpusTransferNegotiator.negotiate(local: supported, remote: legacy)?.contextHistoryObservationVersion)
        XCTAssertNil(ConnectedCorpusTransferNegotiator.negotiate(local: supported, remote: unknown)?.contextHistoryObservationVersion)
        XCTAssertEqual(ConnectedCorpusTransferNegotiator.negotiate(local: supported, remote: supported)?.contextHistoryObservationVersion, 1)
        let nondurable = ConnectedCorpusTransferCapabilities(protocolVersions: [1], contextHistoryObservationVersion: 1)
        XCTAssertNil(ConnectedCorpusTransferNegotiator.negotiate(local: nondurable, remote: nondurable)?.contextHistoryObservationVersion)
        let legacyBytes = try JSONEncoder().encode(legacy)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyBytes) as? [String: Any])
        XCTAssertNil(object["contextHistoryObservationVersion"])
        XCTAssertEqual(try JSONDecoder().decode(ConnectedCorpusTransferCapabilities.self, from: legacyBytes), legacy)
        XCTAssertEqual(ConnectedCorpusTransferCapabilities.current.contextHistoryObservationVersion, 1)
        XCTAssertEqual(ConnectedCorpusTransferNegotiator.negotiate(local: .current, remote: .current)?.contextHistoryObservationVersion, 1)
        XCTAssertNil(ConnectedCorpusTransferNegotiator.negotiate(local: .current, remote: legacy)?.contextHistoryObservationVersion)
    }

    func testManifestBindsOriginalRequestThenObservedSessionAndPeer() throws {
        let fixture = try makeObservedContextTestFixture()
        try fixture.manifest.validate()
        try fixture.manifest.validateHistory(session: fixture.session)
        let bytes = try JSONEncoder().encode(fixture.manifest)
        let restored = try JSONDecoder().decode(ConnectedCorpusExportManifest.self, from: bytes)
        XCTAssertEqual(restored.historyObservation, fixture.manifest.historyObservation)
        try restored.validate()
        try restored.validateHistory(session: fixture.session)
        var legacy = fixture.manifest
        legacy.historyObservation = nil
        XCTAssertEqual(try ConnectedCorpusRequestFingerprint.make(for: legacy).sha256,
                       fixture.manifest.historyObservation?.requestBindingSHA256)
        XCTAssertNotEqual(try ConnectedCorpusRequestFingerprint.make(for: legacy), fixture.session.requestFingerprint)
        let changedPeer = ConnectedCorpusTransferSession(sessionID: fixture.session.sessionID,
            jobID: fixture.session.jobID, requestFingerprint: fixture.session.requestFingerprint,
            protocolVersion: 2, partitionTargetBytes: fixture.session.partitionTargetBytes,
            createdAt: fixture.session.createdAt,
            peerBinding: .init(sourceInstallationID: UUID(), destinationInstallationID: UUID()))
        XCTAssertThrowsError(try restored.validateHistory(session: changedPeer))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["sourceDeviceName"] = "Different immutable manifest"
        let rebound = try JSONDecoder().decode(ConnectedCorpusExportManifest.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try rebound.validate(), "A new session digest cannot rebind old admission evidence")
        func reboundCheckpoint(_ changed: [String: Any]) throws -> ConnectedCorpusExportManifest {
            var unobserved = changed
            var observation = try XCTUnwrap(unobserved.removeValue(forKey: "historyObservation") as? [String: Any])
            let base = try JSONDecoder().decode(ConnectedCorpusExportManifest.self,
                from: JSONSerialization.data(withJSONObject: unobserved))
            observation["request_binding_sha256"] = try base.historyRequestBinding()
            unobserved["historyObservation"] = observation
            return try JSONDecoder().decode(ConnectedCorpusExportManifest.self,
                from: JSONSerialization.data(withJSONObject: unobserved))
        }
        let originalObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var differentCalendar = originalObject
        differentCalendar["sourceTimeZoneIdentifier"] = "America/Los_Angeles"
        XCTAssertThrowsError(try reboundCheckpoint(differentCalendar).validate(),
            "Even internally rebound evidence must match the actual capture calendar")
        var differentSnapshotCalendar = originalObject
        var snapshot = try XCTUnwrap(differentSnapshotCalendar["settingsSnapshot"] as? [String: Any])
        snapshot["calendarTimeZoneIdentifier"] = "America/Los_Angeles"
        differentSnapshotCalendar["settingsSnapshot"] = snapshot
        XCTAssertThrowsError(try reboundCheckpoint(differentSnapshotCalendar).validate())
        var extraCaptureDay = originalObject
        extraCaptureDay["transferDates"] = [fixture.date, fixture.date.addingTimeInterval(86400)]
            .map(\.timeIntervalSinceReferenceDate)
        XCTAssertThrowsError(try reboundCheckpoint(extraCaptureDay).validate(),
            "Context admission cannot authorize an extra captured owner day")
        let legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(legacyObject["historyObservation"])
    }

    func testObservedSourceJournalRestartRejectsEvidenceRemovalWithoutMigrationWrites() throws {
        let fixture = try makeObservedContextTestFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr183-corpus-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConnectedCorpusOutboundStore(rootURL: root)
        let journal = try store.createOrRestore(origin: .macInitiated, session: fixture.session, manifest: fixture.manifest)
        XCTAssertEqual(journal.version, ConnectedCorpusOutboundJournal.historyObservationVersion)
        let reopened = ConnectedCorpusOutboundStore(rootURL: root)
        XCTAssertEqual(try reopened.load(jobID: fixture.session.jobID)?.exportManifest.historyObservation,
                       fixture.manifest.historyObservation)
        let url = root.appendingPathComponent(fixture.session.jobID.uuidString.lowercased()).appendingPathComponent("journal.json")
        let original = try Data(contentsOf: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var manifest = try XCTUnwrap(object["exportManifest"] as? [String: Any])
        manifest.removeValue(forKey: "historyObservation")
        object["exportManifest"] = manifest
        let malformed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try malformed.write(to: url)
        XCTAssertThrowsError(try reopened.load(jobID: fixture.session.jobID))
        XCTAssertEqual(try Data(contentsOf: url), malformed, "Rejected reads must preserve source evidence")
        try original.write(to: url)
        XCTAssertEqual(try reopened.load(jobID: fixture.session.jobID)?.version,
                       ConnectedCorpusOutboundJournal.historyObservationVersion)
    }
}
