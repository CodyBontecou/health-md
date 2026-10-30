#if os(iOS)
import Foundation
import HealthMdConnectionCore
import Testing
@testable import HealthMd

@MainActor
struct DirectMorningFileRenderingTests {
    // STATIC RETENTION JUSTIFICATION: Match the observation teardown policy in
    // docs/testing/lifecycle-audit.md; all fixtures use isolated synthetic state.
    private static var retained: [AnyObject] = []

    @Test(arguments: ["native-only", "provider", "range", "metadata-off", "warning"])
    func wholeSessionAndProviderFilesSurviveSpoolingAndCommit(mode: String) async throws {
        let fixture = try await makeFixture(mode: mode)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let encoded = try ConnectedCorpusApplicationItemCodec.encode(fixture.payload, kind: .macHealthDay)
        defer { encoded.remove() }
        let restored = try ConnectedCorpusApplicationItemCodec.decode(ConnectedCorpusHealthDayPayload.self,
            from: encoded.url, expectedKind: .macHealthDay)
        let journal = fixture.journal
        let snapshot = journal.settingsSnapshot
        #expect(try #require(snapshot.appleExportEnginePin).isWakeDate)
        let planned = try #require(try await IPhoneDirectFileExportProducer.materializePinnedGeneratedFiles(
            journal: journal, payloads: [restored], settingsSnapshot: snapshot, vault: fixture.vault))
        #expect(planned.operation.artifacts.count == (mode == "range" ? 8 : 4))
        #expect(planned.providerSidecars.count == (mode == "native-only" ? 0 : 1))
        // Compare all four complete daily artifacts against the already-qualified
        // local producer under the identical frozen pin and operation identity.
        let restoredRecord = try #require(restored.record)
        let timeZoneIdentifier = try #require(journal.originalCalendarTimeZoneIdentifier)
        let baseline = try #require(try await fixture.vault.materializeHealthDataRange([restoredRecord],
            settingsSnapshot: snapshot.forDailyArtifactPreview(), operationSurface: .localVaultRangeWithoutSideEffects,
            operationIdentity: .init(requestID: journal.request.jobID.uuidString.lowercased(),
                sessionID: journal.session.sessionID.uuidString.lowercased(), capturedAt: journal.session.createdAt,
                calendarTimeZoneIdentifier: timeZoneIdentifier)))
        for expected in baseline.operation.artifacts {
            let direct = try #require(planned.operation.artifacts.first { $0.artifact.relativePath == expected.artifact.relativePath })
            #expect(try direct.artifact.content.materializedData() == expected.artifact.content.materializedData())
        }
        let destination = try fixture.vault.freezeHealthDataRangeDestination()
        _ = try await fixture.vault.commitHealthDataRangeMaterialization(planned, destination: destination)
        for artifact in planned.operation.artifacts {
            let bytes = try Data(contentsOf: fixture.root.appendingPathComponent(artifact.artifact.relativePath))
            #expect(NativeExportArtifact.sha256(of: bytes) == artifact.artifact.sha256)
        }
        let dailyJSONPath = try #require(baseline.operation.artifacts.first { $0.format == .json }).artifact.relativePath
        let json = try #require(planned.operation.artifacts.first { $0.artifact.relativePath == dailyJSONPath })
        let object = try #require(JSONSerialization.jsonObject(with: json.artifact.content.materializedData()) as? [String: Any])
        #expect(object["schema_version"] as? Int == 11)
        let sleep = try #require(object["sleep"] as? [String: Any])
        #expect(sleep["totalDuration"] as? Double == 97_200.5)
        let stage = try #require((sleep["sleepStages"] as? [[String: Any]])?.first)
        #expect(stage["durationSeconds"] as? Double == 97_200.5)
        #expect((stage["metadata"] as? [String: String])?["synthetic"] == "whole-source-session")
        if let sidecar = planned.providerSidecars.first {
            let bytes = try Data(contentsOf: fixture.root.appendingPathComponent(sidecar.relativePath))
            let record = try JSONDecoder.externalRecordDecoder.decode(ExternalDailyRecord.self, from: bytes)
            #expect(record == fixture.payload.externalDailyRecords.first)
        }
        // Replaying the retained plan needs no provider/HealthKit object and
        // produces exactly the same files through the production staging writer.
        _ = try await fixture.vault.commitHealthDataRangeMaterialization(planned, destination: destination)
    }

    @Test(arguments: ["missing-authority", "foreign-day", "unselected-provider", "count-mismatch", "unavailable-with-payload"])
    func contradictorySidecarScopeRejectsBeforeWriting(damage: String) async throws {
        let fixture = try await makeFixture(mode: "provider")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var snapshot = fixture.journal.settingsSnapshot
        var external = fixture.payload.externalDailyRecords
        if damage == "missing-authority" { snapshot.externalProviderCaptureAuthority = nil }
        if damage == "unselected-provider" { snapshot.externalProviderCaptureAuthority = .init(connections: [:]) }
        if damage == "unavailable-with-payload" { snapshot.externalProviderCaptureAuthority = .init(connections: ["whoop": nil]) }
        if damage == "foreign-day" { external[0].date = "2000-01-01" }
        if damage == "count-mismatch" { external = [] }
        let payload = ConnectedCorpusHealthDayPayload(sourceDate: fixture.payload.sourceDate, isRequestedDate: true,
            record: fixture.payload.record, externalDailyRecords: external, failure: nil)
        await #expect(throws: IPhoneDirectFileProducerError.self) {
            _ = try await IPhoneDirectFileExportProducer.materializePinnedGeneratedFiles(journal: fixture.journal,
                payloads: [payload], settingsSnapshot: snapshot, vault: fixture.vault)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    private struct Fixture {
        let root: URL
        let vault: VaultManager
        let journal: IPhoneDirectFileJournal
        let payload: ConnectedCorpusHealthDayPayload
        let ownerID: String
    }

    private func makeFixture(mode: String) async throws -> Fixture {
        let suite = "DirectMorningFileRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retained.append(settings)
        settings.exportFormats = Set(ExportFormat.allCases)
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.generateRangeSummary = mode == "range"
        settings.includeDataDictionary = false
        settings.includeMetadata = mode != "metadata-off"
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        settings.detailPolicy = .detailedTimeSeries
        settings.metricSelection.enabledMetrics = ["sleep_total", "sleep_core", "sleep_bedtime", "sleep_wake"]
        let zone = try #require(TimeZone(identifier: "UTC"))
        settings.executionSleepCaptureContext = .init(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.executionSleepCaptureContextIsFrozen = true
        let hasProvider = mode != "native-only"
        let connections: [String: UUID?] = mode == "warning" ? ["whoop": nil] : (hasProvider ? ["whoop": UUID()] : [:])
        settings.executionExternalProviderCaptureAuthority = .init(connections: connections)
        let owner = Calendar.utc.startOfDay(for: ExportFixtures.referenceDate)
        let ownerID = APIExportClient.dayString(from: owner, timeZone: zone)
        let start = owner.addingTimeInterval(-14 * 3600 - 0.25)
        let end = owner.addingTimeInterval(13 * 3600 + 0.25)
        var record = HealthData(date: owner, timeContext: .init(timeZone: zone, sleepDayAttribution: .morningEnds),
            sleep: SleepData(totalDuration: end.timeIntervalSince(start), coreSleep: end.timeIntervalSince(start),
                sessionStart: start, sessionEnd: end,
                stages: [SleepStageSample(stage: "core", startDate: start, endDate: end,
                    metadata: ["synthetic": "whole-source-session"])]),
            providers: hasProvider ? ExportFixtures.whoopDay.providers : nil)
        let external = hasProvider ? [ExternalDailyRecord(provider: .whoop, date: ownerID, fetchedAt: owner,
            payloads: mode == "warning" ? [] : [.init(name: "cycles", endpoint: "https://synthetic.invalid/cycles",
                statusCode: 200, fetchedAt: owner, data: .object(["synthetic": .string("retained-provider-fact")]))],
            warnings: mode == "warning" ? ["Synthetic connection unavailable"] : [])] : []
        if mode == "warning" { record.providers = HealthProviderSections.normalized(from: external) }
        let id = UUID()
        let request = DirectExportRequest(jobID: id, createdAt: owner,
            dateSelection: .exact(start: ownerID, end: ownerID), responseMode: .writeFiles,
            destination: .init(rootPath: "/synthetic"))
        let surface = IPhoneDirectFileExportProducer.operationSurfaceForNewGeneratedFileJob(request: request,
            settings: settings, connectedProviderCount: hasProvider ? 1 : 0)
        #expect(surface == (hasProvider ? .directGeneratedFilesWithProviderSidecars : .directGeneratedFilesWithoutSideEffects))
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings, healthSubfolder: "Health",
            calendarTimeZone: zone, surface: surface)
        let peer = DirectPeerBinding(sourceInstallationID: UUID(), destinationInstallationID: UUID())
        let session = try DirectTransferSession(sessionID: UUID(), jobID: id,
            requestFingerprint: DirectRequestFingerprint.make(for: request), peerBinding: peer,
            partitionTargetBytes: DirectTransferLimits.preferredPartitionBytes, createdAt: owner)
        let accepted = DirectExportAccepted(jobID: id, acceptedAt: owner, peerBinding: peer,
            resolvedDateIdentifiers: [ownerID], sourceDeviceName: "Synthetic", sourceTimeZoneIdentifier: zone.identifier)
        let day = IPhoneDirectCapturedDay(sourceDate: owner, sourceDateIdentifier: ownerID, isRequestedDate: true,
            relativePath: "capture.citem", succeeded: true, externalRecordCount: external.count)
        let journal = IPhoneDirectFileJournal(request: request, accepted: accepted, session: session,
            settingsSnapshot: snapshot, healthSubfolder: "Health", requestedDates: [owner], transferDates: [owner],
            capturedDays: [day], generatedFiles: [], partitions: [], committedPartitionCount: 0, committedBytes: 0,
            state: "preparing", completionRecorded: false, updatedAt: owner)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DirectMorningGenerated-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let vault = VaultManager(defaults: FakeUserDefaults(), fileCoordinator: PassthroughFileCoordinator(),
            bookmarkResolver: FakeBookmarkResolver())
        try vault.configureDirectTransportStagingRoot(root, healthSubfolder: "Health")
        Self.retained.append(vault)
        return Fixture(root: root, vault: vault, journal: journal,
            payload: .init(sourceDate: owner, isRequestedDate: true, record: record, externalDailyRecords: external, failure: nil),
            ownerID: ownerID)
    }
}

private extension JSONDecoder {
    static var externalRecordDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
private extension Calendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
#endif
