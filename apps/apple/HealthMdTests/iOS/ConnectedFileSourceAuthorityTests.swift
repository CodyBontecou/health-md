#if os(iOS)
import Foundation
import HealthKit
import Testing
@testable import HealthMd

@MainActor
struct ConnectedFileSourceAuthorityTests {
    // STATIC RETENTION JUSTIFICATION: Match docs/testing/lifecycle-audit.md;
    // observation objects use isolated synthetic settings and no live services.
    private static var retained: [AnyObject] = []

    @Test(arguments: ["unchanged", "replaced", "disconnected", "empty"])
    func freshAcceptanceFreezesSettingsClockAndProviderMembership(change: String) async throws {
        try #require(ConnectedAppsFeature.isEnabled)
        let fixture = try fixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let providers = Provider()
        if change == "empty" { providers.currentID = nil }
        let acceptedID = providers.currentID
        providers.beforeAcceptance = {
            fixture.settings.metricSelection.enabledMetrics = []
            fixture.settings.exportFormats = [.csv]
            fixture.manager.setSleepDayAttribution(.nightBegins)
        }
        defer { #expect(providers.lastAuthorityCount == (change == "empty" ? 0 : 1),
            "accepts=\(providers.acceptanceCalls), frozen=\(fixture.settings.executionExternalProviderCaptureAuthorityIsFrozen)") }
        let capture = try await IPhoneConnectedCorpusProducer.prepareFileCapture(settings: fixture.settings,
            healthSubfolder: "Accepted", protocolVersion: ConnectedCorpusTransferCapabilities.currentProtocolVersion,
            healthKitManager: fixture.manager, providers: providers,
            legacyFetcher: { await providers.fetchDailyRecords(for: $0) })
        Self.retained.append(capture.settings)
        #expect(try #require(capture.snapshot.appleExportEnginePin).isWakeDate)
        #expect(capture.snapshot.metricSelection.enabledMetricIDs == ["steps"])
        #expect(capture.context.sleepDayAttribution == .morningEnds)
        #expect(capture.snapshot.healthSubfolder == "Accepted")
        #expect(capture.snapshot.exportFormats == [.json])
        #expect(providers.acceptanceCalls == 1)
        if change == "empty" { providers.currentID = UUID() }
        providers.afterFirstFetch = {
            if change == "replaced" { providers.currentID = UUID() }
            if change == "disconnected" { providers.currentID = nil }
        }
        for date in fixture.dates {
            let outcome = try await HealthKitDailyCapture.capture(date: date,
                detailPolicy: capture.settings.effectiveDetailPolicy, metricSelection: capture.settings.metricSelection,
                transform: .sanitizeGranular, emptyRecordPolicy: .retain,
                fetchExternalRecords: capture.fetchExternalRecords != nil, failurePolicy: .connectedMac,
                fetchHealthData: { date, detail, selection in
                    try await fixture.manager.fetchHealthData(for: date, detailPolicy: detail,
                        metricSelection: selection, timeZone: capture.context.timeZone, captureContext: capture.context)
                }, fetchExternalDailyRecords: capture.fetchExternalRecords)
            #expect(outcome.record?.activity.steps == 42)
            #expect(outcome.record?.timeContext.sleepDayAttribution == .morningEnds)
        }
        #expect(fixture.healthStore.queriedSumIdentifiers.count == 2)
        #expect(providers.expectedIDs == (change == "empty" ? [] : [acceptedID, acceptedID]))
        #expect(providers.successfulFetches == (change == "empty" ? 0 : change == "unchanged" ? 2 : 1))
    }

    @Test(arguments: ["selected", "empty", "unavailable", "missing"])
    func diskRecoveryKeepsPrivateGrantAndUsesActualRecoveredProducer(mode: String) async throws {
        try #require(ConnectedAppsFeature.isEnabled)
        let fixture = try fixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let providers = Provider()
        if mode == "empty" { providers.currentID = nil }
        defer { #expect(providers.lastAuthorityCount == (mode == "empty" ? 0 : 1),
            "accepts=\(providers.acceptanceCalls), frozen=\(fixture.settings.executionExternalProviderCaptureAuthorityIsFrozen)") }
        let accepted = try await IPhoneConnectedCorpusProducer.prepareFileCapture(settings: fixture.settings,
            healthSubfolder: "Accepted", protocolVersion: ConnectedCorpusTransferCapabilities.currentProtocolVersion,
            healthKitManager: fixture.manager, providers: providers)
        Self.retained.append(accepted.settings)
        var snapshot = accepted.snapshot
        if mode == "unavailable" { snapshot.externalProviderCaptureAuthority = .init(connections: ["whoop": nil]) }
        if mode == "missing" { snapshot.externalProviderCaptureAuthority = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnectedSourceAuthority-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let manifest = manifest(snapshot: snapshot, dates: fixture.dates, now: now)
        let session = ConnectedCorpusTransferSession(sessionID: UUID(), jobID: UUID(), requestFingerprint: try .make(for: manifest),
            partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes, createdAt: now,
            peerBinding: .init(sourceInstallationID: UUID(), destinationInstallationID: UUID()))
        let storeRoot = root.appendingPathComponent("outbound")
        let store = ConnectedCorpusOutboundStore(rootURL: storeRoot, now: { now })
        _ = try store.createOrRestore(origin: .interactiveIPhone, session: session, manifest: manifest)
        let relaunched = ConnectedCorpusOutboundStore(rootURL: storeRoot, now: { now })
        let loaded = try #require(try relaunched.load(jobID: session.jobID))
        #expect(loaded.exportManifest.settingsSnapshot.externalProviderCaptureAuthority == snapshot.externalProviderCaptureAuthority)
        var changed = snapshot
        changed.externalProviderCaptureAuthority = .init(connections: ["whoop": UUID()])
        let changedManifest = self.manifest(snapshot: changed, dates: fixture.dates, now: now)
        #expect(try ConnectedCorpusRequestFingerprint.make(for: changedManifest) == session.requestFingerprint)
        #expect(throws: ConnectedCorpusOutboundStoreError.self) {
            _ = try relaunched.createOrRestore(origin: .interactiveIPhone, session: session, manifest: changedManifest)
        }
        let publicJSON = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
        #expect(!publicJSON.contains("externalProviderCaptureAuthority"))
        providers.currentID = UUID()
        fixture.manager.setSleepDayAttribution(.nightBegins)
        fixture.settings.metricSelection.enabledMetrics = []
        let recovery = IPhoneCorpusExportRecoveryManager(store: relaunched)
        let sync = SyncService()
        Self.retained += [recovery, sync]
        recovery.configure(syncService: sync, healthKitManager: fixture.manager, externalIntegrations: providers)
        let current = try #require(try relaunched.load(jobID: session.jobID))
        let producer = recovery.makeRecoveredProducer(for: current)
        let before = providers.acceptanceCalls
        if mode == "missing" {
            await #expect(throws: ExternalProviderCaptureAuthority.RecoveryError.self) {
                _ = try await producer(0, fixture.dates[0])
            }
            #expect(fixture.healthStore.queriedSumIdentifiers.isEmpty)
        } else {
            let item = try await producer(0, fixture.dates[0])
            defer { item.file.remove() }
            let payload = try ConnectedCorpusApplicationItemCodec.decode(ConnectedCorpusHealthDayPayload.self,
                from: item.file.url, expectedKind: .macHealthDay)
            #expect(payload.record?.activity.steps == 42)
            #expect(payload.record?.timeContext.sleepDayAttribution == .morningEnds)
            if mode == "empty" {
                #expect(payload.externalDailyRecords.isEmpty)
                #expect(providers.expectedIDs.isEmpty)
            } else {
                #expect(payload.externalDailyRecords.first?.payloads.isEmpty == true)
                #expect(payload.externalDailyRecords.first?.warnings.isEmpty == false)
                try #require(providers.expectedIDs.count == 1)
                #expect(providers.expectedIDs[0] == (snapshot.externalProviderCaptureAuthority?.connections["whoop"] ?? nil))
            }
        }
        #expect(providers.acceptanceCalls == before)
        let replay = try await IPhoneConnectedCorpusProducer.prepareFileCapture(settings: fixture.settings,
            savedSnapshot: loaded.exportManifest.settingsSnapshot, healthSubfolder: "Changed", protocolVersion: session.protocolVersion,
            healthKitManager: fixture.manager, providers: nil, needsCapture: false)
        Self.retained.append(replay.settings)
        #expect(replay.snapshot == loaded.exportManifest.settingsSnapshot)
        #expect(replay.fetchExternalRecords == nil)
    }

    @Test(arguments: [false, true])
    func scheduledConnectedOccurrencesAcceptSourceAndProfileBeforeCapture(profile: Bool) async throws {
        try #require(ConnectedAppsFeature.isEnabled)
        let fixture = try fixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let providers = Provider()
        let scheduler = SchedulingManager(persistScheduleChanges: false, systemSideEffectsEnabled: false)
        let sync = SyncService()
        Self.retained += [scheduler, sync]
        scheduler.configureScheduledExportDependencies(syncService: sync, externalIntegrations: providers)
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let snapshot = await AppleSleepCaptureContext.pinned.withValue(context) {
            if profile {
                let saved = ExportSettingsSnapshot.from(fixture.settings, healthSubfolder: "Saved", calendarTimeZoneIdentifier: "GMT")
                return await scheduler.makeSettingsSnapshotForNewScheduledProfileOperation(.init(profileID: UUID(),
                    profileName: "Synthetic", target: .connectedMac, settings: saved))
            }
            return await scheduler.makeSettingsSnapshotForNewScheduledOperation(target: .connectedMac,
                settings: fixture.settings, calendarTimeZone: .gmt)
        }
        #expect(try #require(snapshot.appleExportEnginePin).isWakeDate)
        #expect(snapshot.sleepCaptureContext == context)
        #expect(snapshot.externalProviderCaptureAuthority?.connections["whoop"] == providers.currentID)
        #expect(providers.acceptanceCalls == 1)
        #expect(providers.expectedIDs.isEmpty)
        if profile { #expect(snapshot.healthSubfolder == "Saved") }
    }

    @Test func missingFrozenClockCannotAcquireCurrentAttributionOrProviderScope() async throws {
        let fixture = try fixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.settings.executionSleepCaptureContext = nil
        fixture.settings.executionSleepCaptureContextIsFrozen = true
        let providers = Provider()
        let scheduler = SchedulingManager(persistScheduleChanges: false, systemSideEffectsEnabled: false)
        let sync = SyncService()
        Self.retained += [scheduler, sync]
        scheduler.configureScheduledExportDependencies(syncService: sync, externalIntegrations: providers)
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let snapshot = await AppleSleepCaptureContext.pinned.withValue(context) {
            await scheduler.makeSettingsSnapshotForNewScheduledOperation(target: .connectedMac,
                settings: fixture.settings, calendarTimeZone: .gmt)
        }
        #expect(snapshot.sleepCaptureContext == nil)
        #expect(snapshot.appleExportEnginePin == nil)
        #expect(providers.acceptanceCalls == 0)
    }

    private struct Fixture {
        let suite: String
        let defaults: UserDefaults
        let settings: AdvancedExportSettings
        let healthStore: FakeHealthStore
        let manager: HealthKitManager
        let dates: [Date]
    }
    private func fixture() throws -> Fixture {
        let suite = "ConnectedFileAuthority.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json]; settings.generateRangeSummary = false
        settings.archiveExportFiles = false; settings.summaryOnlyExport = false
        settings.includeDataDictionary = false; settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false; settings.detailPolicy = .summary
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.exportTimeZoneOverride = TimeZone(secondsFromGMT: 0)!
        let store = FakeHealthStore(); store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 42
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        manager.setSleepDayAttribution(.morningEnds)
        Self.retained += [settings, manager]
        return Fixture(suite: suite, defaults: defaults, settings: settings, healthStore: store, manager: manager,
            dates: [Date(timeIntervalSince1970: 1_777_766_400), Date(timeIntervalSince1970: 1_777_852_800)])
    }
    private func manifest(snapshot: ExportSettingsSnapshot, dates: [Date], now: Date) -> ConnectedCorpusExportManifest {
        .init(mode: .writeFiles, createdAt: now, sourceDeviceName: "Synthetic", sourceTimeZoneIdentifier: snapshot.calendarTimeZoneIdentifier,
            dateRangeStart: dates[0], dateRangeEnd: dates[1], requestedDates: dates, transferDates: dates,
            settingsSnapshot: snapshot, requestedTarget: nil)
    }

    @MainActor private final class Provider: ExternalIntegrationDailyRecordProviding {
        var currentID: UUID? = UUID()
        var acceptanceCalls = 0
        var lastAuthorityCount: Int?
        var successfulFetches = 0
        var expectedIDs: [UUID?] = []
        var beforeAcceptance: (() -> Void)?
        var afterFirstFetch: (() -> Void)?
        var connectedProviderCount: Int { currentID == nil ? 0 : 1 }
        func forCaptureOperation() -> any ExternalIntegrationDailyRecordProviding {
            acceptanceCalls += 1; let id = currentID; beforeAcceptance?()
            let scope = Scope(root: self, authority: .init(connections: id == nil ? [:] : ["whoop": id]))
            lastAuthorityCount = scope.captureAuthority?.connections.count
            return scope
        }
        func forCaptureOperation(authority: ExternalProviderCaptureAuthority) throws -> any ExternalIntegrationDailyRecordProviding { Scope(root: self, authority: authority) }
        func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] { records(date, expected: currentID) }
        func fetchDailyRecords(for date: Date, providerIDs: Set<String>) async -> [ExternalDailyRecord] { await fetchDailyRecords(for: date) }
        func records(_ date: Date, expected: UUID?) -> [ExternalDailyRecord] {
            expectedIDs.append(expected)
            let available = expected != nil && expected == currentID
            if available { successfulFetches += 1 }
            let records = [ExternalDailyRecord(provider: .whoop, date: APIExportClient.dayString(from: date, timeZone: .gmt),
                payloads: available ? [.init(name: "cycles", endpoint: "https://synthetic.invalid", statusCode: 200,
                    data: .object(["synthetic": .string("accepted-source")]))] : [], warnings: available ? [] : ["Unavailable saved connection"])]
            if expectedIDs.count == 1 { afterFirstFetch?() }
            return records
        }
    }
    @MainActor private final class Scope: ExternalIntegrationDailyRecordProviding {
        let root: Provider
        let authority: ExternalProviderCaptureAuthority
        init(root: Provider, authority: ExternalProviderCaptureAuthority) { self.root = root; self.authority = authority }
        var captureAuthority: ExternalProviderCaptureAuthority? { authority }
        var connectedProviderCount: Int { authority.connections.count }
        func forCaptureOperation(authority: ExternalProviderCaptureAuthority) throws -> any ExternalIntegrationDailyRecordProviding {
            guard authority == self.authority else { throw ExternalProviderCaptureAuthority.RecoveryError.unavailable }; return self
        }
        func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] { root.records(date, expected: authority.connections["whoop"] ?? nil) }
        func fetchDailyRecords(for date: Date, providerIDs: Set<String>) async -> [ExternalDailyRecord] { await fetchDailyRecords(for: date) }
    }
}
#endif
