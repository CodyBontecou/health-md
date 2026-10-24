import Foundation
import HealthMdConnectionCore
import XCTest
@testable import HealthMd

#if os(macOS)
final class EncryptedHealthContextHistoryTests: XCTestCase {
    func testFoundationNormalizedUTCProvenancePreservesScope() throws {
        let original = day(metrics: ["steps"])
        let projected = HealthMdCompactContextDay(ownerDate: original.ownerDate,
            intervalStart: original.intervalStart, intervalEnd: original.intervalEnd,
            calendarTimeZone: TimeZone(identifier: "UTC")!.identifier,
            source: original.source, status: original.status, metrics: original.metrics)
        try HealthContextHistoryProvenance(metricIDs: ["steps"],
            observation: observation(metrics: ["steps"])).validate(for: projected)
        var foreignCalendar = Calendar(identifier: .gregorian)
        foreignCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let foreignStart = foreignCalendar.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let foreignEnd = foreignCalendar.date(byAdding: .day, value: 1, to: foreignStart)!
        let foreignZone = HealthMdCompactContextDay(ownerDate: original.ownerDate,
            intervalStart: foreignStart, intervalEnd: foreignEnd,
            calendarTimeZone: "America/New_York", source: original.source,
            status: original.status, metrics: original.metrics)
        XCTAssertThrowsError(try HealthContextHistoryProvenance(metricIDs: ["steps"],
            observation: observation(metrics: ["steps"])).validate(for: foreignZone))
    }

    func testScopedRefreshKeepsOnlyMatchingGenerationAndMetricProvenance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr183-context-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let key = InMemoryHealthContextEncryptionKeyProvider(keyData: Data(repeating: 0x63, count: 32))
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: key)
        let first = try observation(metrics: ["heart_rate", "steps"])
        try await store.mergeScoped([day(metrics: ["heart_rate", "steps"])],
            replacingMetricIDs: ["heart_rate", "steps"], sourceIDs: ["apple_health"], historyObservation: first)
        let initial = try await store.snapshot()
        let initialEvidence = try await store.historyProvenance(from: initial, at: 0)
        XCTAssertEqual(initialEvidence.map(\.observation), [first])
        let second = try observation(metrics: ["steps"])
        try await store.mergeScoped([day(metrics: ["steps"])], replacingMetricIDs: ["steps"],
            sourceIDs: ["apple_health"], historyObservation: second)
        let updated = try await store.snapshot()
        XCTAssertNotEqual(initial.revision, updated.revision)
        let reopened = EncryptedHealthContextStore(rootURL: root, keyProvider: key)
        let scoped = try await reopened.historyProvenance(from: updated, at: 0)
        XCTAssertEqual(scoped.count, 2)
        XCTAssertEqual(scoped.first(where: { $0.observation == first })?.metricIDs, ["heart_rate"])
        XCTAssertEqual(scoped.first(where: { $0.observation == second })?.metricIDs, ["steps"])
        // Legacy refresh cannot borrow the evidence of a prior acquisition.
        try await reopened.mergeScoped([day(metrics: ["heart_rate"])],
            replacingMetricIDs: ["heart_rate"], sourceIDs: ["apple_health"])
        let legacy = try await reopened.snapshot()
        let legacyEvidence = try await reopened.historyProvenance(from: legacy, at: 0)
        XCTAssertEqual(legacyEvidence.map(\.observation), [second])
        // A provider-only import leaves the Apple scope intact.
        try await reopened.mergeScoped([day(metrics: [])], replacingMetricIDs: ["whoop_recovery"], sourceIDs: ["whoop"])
        let provider = try await reopened.snapshot()
        let providerEvidence = try await reopened.historyProvenance(from: provider, at: 0)
        XCTAssertEqual(providerEvidence, legacyEvidence)
        let retainedDay = try await reopened.loadDay(ownerDate: "2026-04-17")
        XCTAssertNotNil(retainedDay?.metrics.first { $0.metricID == "steps" })
        // An unattributed legacy entity that actually gets replaced cannot retain
        // its old Apple observation just because this refresh selected a provider.
        try await reopened.mergeScoped([day(metrics: [])], replacingMetricIDs: ["steps"], sourceIDs: ["whoop"])
        let ambiguous = try await reopened.snapshot()
        let ambiguousEvidence = try await reopened.historyProvenance(from: ambiguous, at: 0)
        XCTAssertTrue(ambiguousEvidence.isEmpty)
        try await reopened.mergeScoped([day(metrics: ["steps"])], replacingMetricIDs: ["steps"],
            sourceIDs: ["apple_health"], historyObservation: second)
        // Incoming legacy rows can have a matching observation ID outside the
        // declared provider scope. Such a replacement cannot keep Apple evidence.
        try await reopened.mergeScoped([day(metrics: ["steps"], value: 2)],
            replacingMetricIDs: ["whoop_recovery"], sourceIDs: ["whoop"])
        let offScope = try await reopened.snapshot()
        let offScopeEvidence = try await reopened.historyProvenance(from: offScope, at: 0)
        XCTAssertTrue(offScopeEvidence.isEmpty)
        try await reopened.mergeScoped([day(metrics: ["heart_rate", "steps"])],
            replacingMetricIDs: ["heart_rate", "steps"], sourceIDs: ["apple_health"], historyObservation: first)
        try await reopened.mergeScoped([day(metrics: ["steps"], value: 3)],
            replacingMetricIDs: ["heart_rate"], sourceIDs: ["apple_health"])
        let appleOffScope = try await reopened.snapshot()
        let appleOffScopeEvidence = try await reopened.historyProvenance(from: appleOffScope, at: 0)
        XCTAssertTrue(appleOffScopeEvidence.isEmpty)
        // Full replacement without evidence clears all old provenance.
        try await reopened.upsert(day(metrics: ["steps"]))
        let replacement = try await reopened.snapshot()
        let replacementEvidence = try await reopened.historyProvenance(from: replacement, at: 0)
        XCTAssertTrue(replacementEvidence.isEmpty)
    }

    func testAttributedRefreshRetainsUnchangedSiblingMetricAndEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr183-context-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let key = InMemoryHealthContextEncryptionKeyProvider(keyData: Data(repeating: 0x65, count: 32))
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: key)
        let first = try observation(metrics: ["heart_rate", "steps"])
        try await store.mergeScoped([day(metrics: ["heart_rate", "steps"], attributed: true)],
            replacingMetricIDs: ["heart_rate", "steps"], sourceIDs: ["apple_health"], historyObservation: first)
        let second = try observation(metrics: ["steps"])
        try await store.mergeScoped([day(metrics: ["steps"], value: 2, attributed: true)],
            replacingMetricIDs: ["steps"], sourceIDs: ["apple_health"], historyObservation: second)
        let snapshot = try await store.snapshot()
        let evidence = try await store.historyProvenance(from: snapshot, at: 0)
        XCTAssertEqual(evidence.first(where: { $0.observation == first })?.metricIDs, ["heart_rate"])
        XCTAssertEqual(evidence.first(where: { $0.observation == second })?.metricIDs, ["steps"])
        let stored = try await store.loadDay(from: snapshot, at: 0)
        XCTAssertEqual(stored.metrics.first(where: { $0.metricID == "heart_rate" })?.value, .quantity(value: 1, unit: "count"))
        XCTAssertEqual(stored.metrics.first(where: { $0.metricID == "steps" })?.value, .quantity(value: 2, unit: "count"))
    }

    func testInvalidScopeAndFailedCommitPreservePriorContextProvenance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr183-context-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let key = InMemoryHealthContextEncryptionKeyProvider(keyData: Data(repeating: 0x64, count: 32))
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: key)
        let original = try observation(metrics: ["steps"], requestedStart: "2026-04-17T12:00:00.000000000Z")
        try await store.mergeScoped([day(metrics: ["steps"])], replacingMetricIDs: ["steps"],
            sourceIDs: ["apple_health"], historyObservation: original)
        let baseline = try await store.snapshot()
        let mismatched = try observation(metrics: ["heart_rate"])
        do {
            try await store.mergeScoped([day(metrics: ["steps"])], replacingMetricIDs: ["steps"],
                sourceIDs: ["apple_health"], historyObservation: mismatched)
            XCTFail("Mismatched metric authority must be rejected")
        } catch {}
        enum Injected: Error { case commit }
        let failing = EncryptedHealthContextStore(rootURL: root, keyProvider: key,
            beforeManifestCommit: { throw Injected.commit })
        do {
            try await failing.mergeScoped([day(metrics: ["steps"])], replacingMetricIDs: ["steps"],
                sourceIDs: ["apple_health"], historyObservation: observation(metrics: ["steps"]))
            XCTFail("Injected commit failure must remain a failure")
        } catch {}
        let unchanged = try await store.snapshot()
        XCTAssertEqual(unchanged, baseline)
        let evidence = try await store.historyProvenance(from: unchanged, at: 0)
        XCTAssertEqual(evidence.map(\.observation), [original])
        let wrongDate = HealthContextHistoryProvenance(metricIDs: ["steps"], observation: original)
        var foreignDay = day(metrics: ["steps"])
        foreignDay = HealthMdCompactContextDay(ownerDate: "2026-04-18", intervalStart: foreignDay.intervalEnd,
            intervalEnd: foreignDay.intervalEnd.addingTimeInterval(86400), calendarTimeZone: "UTC",
            source: foreignDay.source, status: .completeEmpty)
        XCTAssertThrowsError(try wrongDate.validate(for: foreignDay))
    }

    func testQueryDisclosureFollowsMatchingGenerationRequestAndSourceScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr183-context-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let key = InMemoryHealthContextEncryptionKeyProvider(keyData: Data(repeating: 0x66, count: 32))
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: key)
        let first = try observation(metrics: ["heart_rate", "steps"], limitedMetrics: ["steps"])
        try await store.mergeScoped([day(metrics: ["heart_rate", "steps"], attributed: true)],
            replacingMetricIDs: ["heart_rate", "steps"], sourceIDs: ["apple_health"], historyObservation: first)
        let executor = EncryptedHealthContextQueryExecutor(store: store,
            evidenceScope: HealthMdEvidenceScope(allowedMetricIDs: ["heart_rate", "steps"]))
        @Sendable func query(_ metricID: String, sources: HealthMdSourceSelection = .allAvailable) async throws -> HealthMdQueryResponse {
            try await executor.execute(HealthMdQueryRequest(metrics: .explicit([metricID]), sources: sources,
                dates: .exact(.init(startDate: "2026-04-17", endDate: "2026-04-17")),
                operation: .coverage,
                page: .init(maxItems: 10, maxBytes: 100_000)), detailLevel: .summary)
        }
        async let steps = query("steps")
        async let heart = query("heart_rate")
        let (stepResult, heartResult) = try await (steps, heart)
        XCTAssertTrue(stepResult.limitations.contains { $0.code == "history_sample_end_limited" })
        XCTAssertFalse(heartResult.limitations.contains { $0.code == "history_sample_end_limited" })
        XCTAssertTrue(heartResult.limitations.contains { $0.code == "history_access_unverified" })
        let provider = try await query("steps", sources: .explicit(sourceIDs: [], providerIDs: ["whoop"]))
        XCTAssertFalse(provider.limitations.contains { $0.code.hasPrefix("history_") })
        let second = try observation(metrics: ["steps"])
        try await store.mergeScoped([day(metrics: ["steps"], value: 2, attributed: true)],
            replacingMetricIDs: ["steps"], sourceIDs: ["apple_health"], historyObservation: second)
        let refreshed = try await query("steps")
        XCTAssertFalse(refreshed.limitations.contains { $0.code == "history_sample_end_limited" })
        XCTAssertTrue(refreshed.limitations.contains { $0.code == "history_admission_observation" })
        let encoded = String(decoding: try HealthMdQueryCanonicalSerializer.data(for: refreshed), as: UTF8.self)
        XCTAssertFalse(encoded.contains(first.observationID), "Unrelated original observation objects must not leak")
        try await store.upsert(day(metrics: ["steps"], attributed: true))
        let legacy = try await query("steps")
        XCTAssertFalse(legacy.limitations.contains { $0.code == "history_admission_observation" })
        XCTAssertTrue(legacy.limitations.contains { $0.code == "history_access_unverified" })
    }

    func testWorkoutOperationIncludesItsSeparatelyAuthorizedImplicitHistoryScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr183-context-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EncryptedHealthContextStore(rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: Data(repeating: 0x67, count: 32)))
        let observed = try observation(metrics: ["heart_rate", "workouts"], limitedMetrics: ["workouts"])
        try await store.mergeScoped([day(metrics: ["heart_rate"], attributed: true)],
            replacingMetricIDs: ["heart_rate", "workouts"], sourceIDs: ["apple_health"], historyObservation: observed)
        let executor = EncryptedHealthContextQueryExecutor(store: store,
            evidenceScope: HealthMdEvidenceScope(allowedMetricIDs: ["heart_rate"], allowsWorkouts: true))
        let response = try await executor.execute(HealthMdQueryRequest(metrics: .explicit(["heart_rate"]),
            dates: .exact(.init(startDate: "2026-04-17", endDate: "2026-04-17")), operation: .workoutListing), detailLevel: .summary)
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertTrue(response.limitations.contains { $0.code == "history_sample_end_limited" },
                      "Workout access is granted independently of the explicit metric list")
    }

    private func observation(metrics: [String], requestedStart: String = "2026-04-17T00:00:00.000000000Z",
                             limitedMetrics: Set<String> = []) throws -> ExportHistoryObservation {
        try ExportHistoryObservation(observationID: UUID(), operationID: UUID(),
            observedAt: "2026-04-18T00:00:00.000000000Z", requestBindingSHA256: String(repeating: "a", count: 64),
            timeZoneIdentifier: "UTC", metricIDs: metrics.sorted(), requestedStart: requestedStart,
            requestedEnd: "2026-04-17T23:59:59.000000000Z", allAvailable: false, rangeSemantics: "owner_dates",
            evidenceMethod: "healthkit_earliest_authorized_sample_date", types: metrics.sorted().map {
                ExportHistoryTypeObservation(typeID: "synthetic.\($0)", directMetricIDs: [$0],
                    outcome: limitedMetrics.contains($0) ? "limited" : "unknown",
                    sampleEndBoundary: limitedMetrics.contains($0) ? "2026-04-17T12:00:00.000000000Z" : nil)
            })
    }

    private func day(metrics: [String], value: Double = 1, attributed: Bool = false) -> HealthMdCompactContextDay {
        let start = Date(timeIntervalSince1970: 1_776_384_000)
        return HealthMdCompactContextDay(ownerDate: "2026-04-17", intervalStart: start,
            intervalEnd: start.addingTimeInterval(86400), calendarTimeZone: "UTC",
            source: HealthMdSourceDescriptor(schema: "healthmd.health_data", schemaVersion: 8, digest: String(repeating: "b", count: 64)),
            status: .completeEmpty, metrics: metrics.map {
                HealthMdContextMetric(observationID: "synthetic:\($0)", metricID: $0,
                    displayName: $0, value: .quantity(value: value, unit: "count"), status: .available,
                    evidenceIDs: attributed ? ["evidence:\($0)"] : [])
            }, evidence: attributed ? metrics.map {
                HealthMdContextEvidence(reference: HealthMdEvidenceReference(evidenceID: "evidence:\($0)",
                    locator: .summaryKey(ownerDate: "2026-04-17", key: $0),
                    source: HealthMdSourceDescriptor(schema: "healthmd.health_data", schemaVersion: 8,
                        digest: String(repeating: "b", count: 64)), sourceID: HealthMdEvidenceSourceIDs.appleHealth),
                    note: "value:\(value)", metricIDs: [$0])
            } : [])
    }
}
#endif
