import XCTest
@testable import HealthMd

#if os(macOS)
final class EncryptedHealthContextStoreTests: XCTestCase {
    func testRoundTripUsesProtectedFilesAndDeterministicIdentifiers() async throws {
        let root = try makeRoot()
        let key = fixedKey(0x11)
        let store = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: key)
        )
        let later = makeDay("2026-04-18", marker: "later-private-marker")
        let earlier = makeDay("2026-04-17", marker: "earlier-private-marker")

        try await store.upsert(later)
        try await store.upsert(earlier)

        let ownerDates = try await store.listOwnerDates()
        let loadedEarlier = try await store.loadDay(ownerDate: earlier.ownerDate)
        let loadedLater = try await store.loadDay(ownerDate: later.ownerDate)
        let missing = try await store.loadDay(ownerDate: "2026-04-19")
        XCTAssertEqual(ownerDates, ["2026-04-17", "2026-04-18"])
        XCTAssertEqual(loadedEarlier, earlier)
        XCTAssertEqual(loadedLater, later)
        XCTAssertNil(missing)

        let rootAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((rootAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let rootValues = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(rootValues.isExcludedFromBackup, true)
        for url in try storedFiles(root) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testCiphertextAndOpaqueFilenamesDoNotLeakPHI() async throws {
        let root = try makeRoot()
        let store = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x22))
        )
        let ownerDate = "2025-12-31"
        let marker = "private-heart-marker-9471"

        try await store.upsert(makeDay(ownerDate, marker: marker))

        for url in try storedFiles(root) {
            XCTAssertFalse(url.lastPathComponent.contains(ownerDate))
            let data = try Data(contentsOf: url)
            XCTAssertNil(data.range(of: Data(ownerDate.utf8)), "owner date leaked in \(url.lastPathComponent)")
            XCTAssertNil(data.range(of: Data(marker.utf8)), "health marker leaked in \(url.lastPathComponent)")
            XCTAssertThrowsError(try JSONSerialization.jsonObject(with: data))
        }
    }

    func testWrongMissingKeyAndTamperingFailClosed() async throws {
        let root = try makeRoot()
        let provider = InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x33))
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: provider)
        try await store.upsert(makeDay("2024-02-29", marker: "authenticated"))

        let wrongKeyStore = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x34))
        )
        await XCTAssertThrowsStoreError(.ciphertextAuthenticationFailed) {
            _ = try await wrongKeyStore.listOwnerDates()
        }

        provider.replaceKeyData(nil)
        await XCTAssertThrowsStoreError(.missingEncryptionKey) {
            _ = try await store.listOwnerDates()
        }
        provider.replaceKeyData(fixedKey(0x33))

        let generation = try XCTUnwrap(try generationFiles(root).first)
        var ciphertext = try Data(contentsOf: generation)
        ciphertext[ciphertext.index(ciphertext.startIndex, offsetBy: ciphertext.count / 2)] ^= 0x80
        try ciphertext.write(to: generation, options: .atomic)
        await XCTAssertThrowsStoreError(.ciphertextAuthenticationFailed) {
            _ = try await store.loadDay(ownerDate: "2024-02-29")
        }
    }

    func testManifestIsAuthenticatedAgainstTampering() async throws {
        let root = try makeRoot()
        let store = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x44))
        )
        try await store.upsert(makeDay("2026-01-02", marker: "manifest"))
        let manifest = try XCTUnwrap(try storedFiles(root).first { $0.lastPathComponent == "manifest.hctx" })
        var ciphertext = try Data(contentsOf: manifest)
        ciphertext[ciphertext.startIndex] ^= 0x01
        try ciphertext.write(to: manifest, options: .atomic)

        await XCTAssertThrowsStoreError(.ciphertextAuthenticationFailed) {
            _ = try await store.listOwnerDates()
        }
    }

    func testUpsertCommitFailurePreservesOldGenerationAndSuccessfulReplacementCleansIt() async throws {
        enum InjectedFailure: Error { case beforeCommit }
        let root = try makeRoot()
        let provider = InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x55))
        let originalStore = EncryptedHealthContextStore(rootURL: root, keyProvider: provider)
        let oldDay = makeDay("2026-05-01", marker: "old-generation")
        let newDay = makeDay("2026-05-01", marker: "new-generation")
        try await originalStore.upsert(oldDay)
        let oldGeneration = try XCTUnwrap(try generationFiles(root).first?.lastPathComponent)

        let failingStore = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: provider,
            beforeManifestCommit: { throw InjectedFailure.beforeCommit }
        )
        do {
            try await failingStore.upsert(newDay)
            XCTFail("Expected injected failure")
        } catch is InjectedFailure {}

        let loadedOldDay = try await originalStore.loadDay(ownerDate: oldDay.ownerDate)
        XCTAssertEqual(loadedOldDay, oldDay)
        XCTAssertEqual(try generationFiles(root).map(\.lastPathComponent), [oldGeneration])

        try await originalStore.upsert(newDay)
        let loadedNewDay = try await originalStore.loadDay(ownerDate: newDay.ownerDate)
        XCTAssertEqual(loadedNewDay, newDay)
        let remaining = try generationFiles(root).map(\.lastPathComponent)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotEqual(remaining.first, oldGeneration)
    }

    func testUnlimitedTraversalOverThousandsOfDaysLoadsOneDayAtATime() async throws {
        let root = try makeRoot()
        let store = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x66))
        )
        let ownerDates = makeOwnerDates(count: 2_048)
        let days = ownerDates.reversed().map { makeDay($0, marker: "value-\($0)") }

        try await store.upsert(days)

        let identifiers = try await store.listOwnerDates()
        XCTAssertEqual(identifiers, ownerDates)
        XCTAssertEqual(identifiers.count, 2_048)

        let visited = OwnerDateCollector()
        try await store.forEachDay { day in
            XCTAssertEqual(day.metrics.count, 1)
            visited.append(day.ownerDate)
        }
        let sampledOwnerDate = try await store.loadDay(ownerDate: ownerDates[1_731])?.ownerDate
        XCTAssertEqual(visited.values, ownerDates)
        XCTAssertEqual(sampledOwnerDate, ownerDates[1_731])
        XCTAssertEqual(try generationFiles(root).count, 2_048)
    }

    func testDeleteAndExplicitRetentionControlsHaveNoImplicitCap() async throws {
        let root = try makeRoot()
        let key = fixedKey(0x77)
        let provider = InMemoryHealthContextEncryptionKeyProvider(keyData: key)
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: provider)
        try await store.upsert([
            makeDay("2026-01-01", marker: "one"),
            makeDay("2026-01-02", marker: "two"),
            makeDay("2026-01-03", marker: "three")
        ])

        let deleted = try await store.deleteDay(ownerDate: "2026-01-02")
        let deletedAgain = try await store.deleteDay(ownerDate: "2026-01-02")
        let datesAfterDelete = try await store.listOwnerDates()
        let retainedDeletion = try await store.applyRetention(.delete(before: "2026-01-03"))
        let datesAfterRetention = try await store.listOwnerDates()
        XCTAssertTrue(deleted)
        XCTAssertFalse(deletedAgain)
        XCTAssertEqual(datesAfterDelete, ["2026-01-01", "2026-01-03"])
        XCTAssertEqual(retainedDeletion, ["2026-01-01"])
        XCTAssertEqual(datesAfterRetention, ["2026-01-03"])
        XCTAssertEqual(try generationFiles(root).count, 1)

        provider.replaceKeyData(nil)
        try await store.deleteAll()
        let datesAfterDeleteAll = try await store.listOwnerDates()
        XCTAssertEqual(datesAfterDeleteAll, [])
        XCTAssertNil(try provider.existingKeyData())
        XCTAssertEqual(try storedFiles(root), [])
    }

    func testScopedMergePreservesUnrequestedMetricsAndReplacesOnlySelectedSource() async throws {
        let root = try makeRoot()
        let store = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x78))
        )
        let ownerDate = "2026-07-20"
        let existing = makeScopedDay(
            ownerDate,
            observations: [
                ("old-sleep", "sleep_total", "apple_health", nil),
                ("old-steps", "steps", "apple_health", nil),
                ("provider-steps", "steps", "provider_native", "oura")
            ]
        )
        let incoming = makeScopedDay(
            ownerDate,
            observations: [("new-steps", "steps", "apple_health", nil)]
        )
        try await store.upsert(existing)
        try await store.mergeScoped(
            [incoming],
            replacingMetricIDs: ["steps"],
            sourceIDs: ["apple_health"]
        )
        let storedDay = try await store.loadDay(ownerDate: ownerDate)
        let loaded = try XCTUnwrap(storedDay)
        XCTAssertEqual(
            Set(loaded.metrics.map(\.observationID)),
            ["old-sleep", "provider-steps", "new-steps"]
        )
        XCTAssertEqual(Set(loaded.metrics.map(\.metricID)), ["sleep_total", "steps"])
        XCTAssertFalse(loaded.evidence.contains { $0.reference.evidenceID == "evidence-old-steps" })
        XCTAssertTrue(loaded.evidence.contains { $0.reference.evidenceID == "evidence-provider-steps" })
    }

    func testScopedMergeRetainsAndTrimsEvidenceSharedByUnrequestedMetric() async throws {
        let root = try makeRoot()
        let store = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x7a))
        )
        let ownerDate = "2026-07-20"
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let source = HealthMdSourceDescriptor(
            schema: "healthmd.health_data",
            schemaVersion: 7,
            digest: "shared"
        )
        let sharedEvidence = HealthMdContextEvidence(
            reference: .init(
                evidenceID: "shared-evidence",
                locator: .queryManifest(ownerDate: ownerDate, identifier: "shared-query"),
                source: source,
                sourceID: HealthMdEvidenceSourceIDs.appleHealth
            ),
            metricIDs: ["heart_rate", "steps"]
        )
        let existing = HealthMdCompactContextDay(
            ownerDate: ownerDate,
            intervalStart: start,
            intervalEnd: start.addingTimeInterval(86_400),
            calendarTimeZone: "UTC",
            source: source,
            status: .available,
            metrics: [
                HealthMdContextMetric(
                    observationID: "summary:\(ownerDate):steps",
                    metricID: "steps",
                    displayName: "Steps",
                    value: .count(10),
                    status: .available,
                    evidenceIDs: ["shared-evidence"]
                ),
                HealthMdContextMetric(
                    observationID: "summary:\(ownerDate):heart_rate",
                    metricID: "heart_rate",
                    displayName: "Heart Rate",
                    value: .quantity(value: 60, unit: "bpm"),
                    status: .available,
                    evidenceIDs: ["shared-evidence"]
                )
            ],
            evidence: [sharedEvidence]
        )
        let incoming = makeScopedDay(
            ownerDate,
            observations: [("new-steps", "steps", "apple_health", nil)]
        )
        try await store.upsert(existing)
        try await store.mergeScoped(
            [incoming],
            replacingMetricIDs: ["steps"],
            sourceIDs: ["apple_health"]
        )

        let stored = try await store.loadDay(ownerDate: ownerDate)
        let loaded = try XCTUnwrap(stored)
        XCTAssertNotNil(loaded.metrics.first { $0.metricID == "heart_rate" })
        let retained = try XCTUnwrap(
            loaded.evidence.first { $0.reference.evidenceID == "shared-evidence" }
        )
        XCTAssertEqual(retained.metricIDs, ["heart_rate"])
    }

    @MainActor
    func testProviderOnlyScopedMergePreservesProjectedAppleMetricAndDayStatus() async throws {
        let root = try makeRoot()
        let store = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x79))
        )
        let date = ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!
        let appleDay = try HealthMdQueryContextProjector.project(
            HealthData(
                date: date,
                timeContext: .init(calendarTimeZoneIdentifier: "UTC"),
                activity: ActivityData(steps: 123)
            ),
            options: .init(enabledMetricIDs: ["steps"])
        )
        let providerDay = try HealthMdQueryContextProjector.project(
            HealthData(
                date: date,
                timeContext: .init(calendarTimeZoneIdentifier: "UTC"),
                healthKitRecordCaptureStatus: .notRequested
            ),
            externalProviderRecords: [
                ExternalDailyRecord(
                    provider: .whoop,
                    date: "2026-07-20",
                    fetchedAt: date,
                    payloads: [
                        ExternalProviderPayload(
                            name: "cycle",
                            endpoint: "https://api.prod.whoop.com/developer/v2/cycle",
                            statusCode: 200,
                            fetchedAt: date,
                            data: .object(["strain": .number(12.5)])
                        )
                    ]
                )
            ],
            options: .init(enabledMetricIDs: ["steps"], includesAppleHealth: false)
        )
        let appleMetric = try XCTUnwrap(appleDay.metrics.first)
        XCTAssertEqual(appleMetric.observationID, "summary:2026-07-20:steps")
        XCTAssertTrue(providerDay.metrics.isEmpty)

        try await store.upsert(appleDay)
        try await store.mergeScoped(
            [providerDay],
            replacingMetricIDs: ["steps"],
            sourceIDs: ["whoop"]
        )

        let stored = try await store.loadDay(ownerDate: "2026-07-20")
        let merged = try XCTUnwrap(stored)
        XCTAssertEqual(merged.metrics, [appleMetric])
        XCTAssertEqual(merged.status, appleDay.status)
        XCTAssertTrue(merged.evidence.contains { $0.reference.providerID == "whoop" })
    }

    func testRejectsDuplicateBatchDatesAndUnsupportedContextSchemaWithoutChangingExportSchema() async throws {
        let root = try makeRoot()
        let store = EncryptedHealthContextStore(
            rootURL: root,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider(keyData: fixedKey(0x7f))
        )
        let day = makeDay("2026-07-01", marker: "schema")
        await XCTAssertThrowsStoreError(.duplicateOwnerDate(day.ownerDate)) {
            try await store.upsert([day, day])
        }
        let unsupported = HealthMdCompactContextDay(
            ownerDate: day.ownerDate,
            intervalStart: day.intervalStart,
            intervalEnd: day.intervalEnd,
            calendarTimeZone: day.calendarTimeZone,
            source: day.source,
            status: day.status,
            schemaVersion: 2
        )
        await XCTAssertThrowsStoreError(
            .unsupportedContextDay(schema: HealthMdQuerySchemas.compactContextDay, version: 2)
        ) {
            try await store.upsert(unsupported)
        }
        let unchangedDates = try await store.listOwnerDates()
        XCTAssertEqual(HealthMdExportSchema.version, 7)
        XCTAssertEqual(unchangedDates, [])
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptedHealthContextStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func fixedKey(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }

    private func makeDay(_ ownerDate: String, marker: String) -> HealthMdCompactContextDay {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return HealthMdCompactContextDay(
            ownerDate: ownerDate,
            intervalStart: start,
            intervalEnd: start.addingTimeInterval(86_400),
            calendarTimeZone: "America/Los_Angeles",
            source: HealthMdSourceDescriptor(schema: "healthmd.health_data", schemaVersion: 7, digest: "digest-\(marker)"),
            status: .available,
            metrics: [
                HealthMdContextMetric(
                    observationID: "observation-\(marker)",
                    metricID: "heart_rate",
                    displayName: marker,
                    value: .quantity(value: 61, unit: "count/min"),
                    status: .available
                )
            ]
        )
    }

    private func makeScopedDay(
        _ ownerDate: String,
        observations: [(id: String, metric: String, sourceID: String, providerID: String?)]
    ) -> HealthMdCompactContextDay {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let evidence = observations.map { item in
            HealthMdContextEvidence(
                reference: HealthMdEvidenceReference(
                    evidenceID: "evidence-\(item.id)",
                    locator: .summaryKey(ownerDate: ownerDate, key: item.id),
                    source: HealthMdSourceDescriptor(
                        schema: "healthmd.health_data",
                        schemaVersion: 7,
                        digest: "source-\(item.id)"
                    ),
                    sourceID: item.sourceID,
                    providerID: item.providerID
                ),
                metricIDs: [item.metric]
            )
        }
        return HealthMdCompactContextDay(
            ownerDate: ownerDate,
            intervalStart: start,
            intervalEnd: start.addingTimeInterval(86_400),
            calendarTimeZone: "America/Los_Angeles",
            source: HealthMdSourceDescriptor(
                schema: "healthmd.health_data", schemaVersion: 7, digest: "day-\(ownerDate)"
            ),
            status: .available,
            metrics: observations.map { item in
                HealthMdContextMetric(
                    observationID: item.id,
                    metricID: item.metric,
                    displayName: item.metric,
                    value: .quantity(value: 1, unit: "count"),
                    status: .available,
                    evidenceIDs: ["evidence-\(item.id)"]
                )
            },
            evidence: evidence
        )
    }

    private func makeOwnerDates(count: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<count).map { formatter.string(from: calendar.date(byAdding: .day, value: $0, to: start)!) }
    }

    private func storedFiles(_ root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func generationFiles(_ root: URL) throws -> [URL] {
        try storedFiles(root).filter { $0.lastPathComponent.hasPrefix("generation-") }
    }

    private func XCTAssertThrowsStoreError(
        _ expected: EncryptedHealthContextStoreError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as EncryptedHealthContextStoreError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private nonisolated final class OwnerDateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
#endif
