import Foundation
import HealthKit
import Testing
@testable import HealthMd

@MainActor
struct APIProviderCaptureTests {
    // STATIC RETENTION JUSTIFICATION: Match the observation teardown policy in
    // docs/testing/lifecycle-audit.md; these isolated fixtures have no live effects.
    private static var retained: [AnyObject] = []

    @Test(arguments: ["unchanged", "replaced", "disconnected"])
    func acceptedConnectionAndSettingsRemainFixed(change: String) async throws {
        try #require(ConnectedAppsFeature.isEnabled)
        let (settings, manager, store) = fixture()
        let provider = Provider()
        let accepted = provider.currentID
        provider.onBegin = {
            settings.metricSelection.enabledMetrics = []
            manager.setSleepDayAttribution(.nightBegins)
        }
        provider.onFirstFetch = {
            if change == "replaced" { provider.currentID = UUID() }
            if change == "disconnected" { provider.currentID = nil }
        }
        var bodies: [Data] = []
        let result = await APIEndpointExportRunner.export(dates: dates, healthKitManager: manager,
            settings: settings, destination: destination, externalIntegrations: provider,
            upload: { batch, _ in
                bodies.append(batch.body)
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            })
        #expect(result.successCount == 2, "Failures: \(result.failedDateDetails)")
        #expect(provider.captureCalls == 1)
        #expect(provider.expectedIDs == [accepted, accepted])
        #expect(provider.beginCount == 1 && provider.endCount == 1)
        #expect(store.queriedSumIdentifiers.count == 2)
        let text = bodies.map { String(decoding: $0, as: UTF8.self) }.joined()
        #expect(text.components(separatedBy: "accepted_source").count - 1 == (change == "unchanged" ? 2 : 1))
        #expect(text.contains("morningEnds") || text.contains("morning_ends"))
        if change != "unchanged" { #expect(text.contains("connection unavailable")) }
    }

    @Test(arguments: ["empty", "missing", "unavailable"])
    func recoveryNeverAdoptsCurrentConnection(authority: String) async throws {
        let (settings, manager, store) = fixture()
        let provider = Provider()
        settings.executionExternalProviderCaptureAuthorityIsFrozen = true
        if authority == "empty" {
            settings.executionExternalProviderCaptureAuthority = .init(connections: [:])
        } else if authority == "unavailable" {
            settings.executionExternalProviderCaptureAuthority = .init(connections: ["whoop": nil])
        }
        var bodies: [Data] = []
        let result = await APIEndpointExportRunner.export(dates: dates, healthKitManager: manager,
            settings: settings, destination: destination, externalIntegrations: provider,
            upload: { batch, _ in
                bodies.append(batch.body)
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            })
        #expect(provider.captureCalls == 0)
        if authority == "missing" {
            #expect(result.successCount == 0)
            #expect(result.failedDateDetails.count == 2)
            #expect(store.queriedSumIdentifiers.isEmpty)
            #expect(bodies.isEmpty)
            #expect(provider.beginCount == 0)
        } else {
            #expect(result.successCount == 2, "Failures: \(result.failedDateDetails)")
            #expect(store.queriedSumIdentifiers.count == 2)
            let text = bodies.map { String(decoding: $0, as: UTF8.self) }.joined()
            #expect(!text.contains("accepted_source"))
            if authority == "empty" {
                #expect(provider.expectedIDs.isEmpty)
                #expect(provider.beginCount == 0)
                #expect(!text.contains("external_records"))
            } else {
                #expect(provider.expectedIDs.count == 2)
                #expect(provider.expectedIDs.allSatisfy { $0 == nil })
                #expect(text.contains("connection unavailable"))
            }
        }
    }

    @Test func executionAuthoritySurvivesRecoveryButNotEditableConfiguration() throws {
        let (settings, _, _) = fixture()
        let id = UUID()
        settings.executionExternalProviderCaptureAuthority = .init(connections: ["whoop": id])
        settings.executionExternalProviderCaptureAuthorityIsFrozen = true
        let snapshot = ExportSettingsSnapshot.from(settings)
        let restored = snapshot.makeAdvancedExportSettings()
        let editable = snapshot.makeAdvancedExportSettings(forNewConfiguration: true)
        Self.retained += [restored, editable]
        #expect(restored.executionExternalProviderCaptureAuthority == settings.executionExternalProviderCaptureAuthority)
        #expect(restored.executionExternalProviderCaptureAuthorityIsFrozen)
        #expect(editable.executionExternalProviderCaptureAuthority == nil)
        #expect(!editable.executionExternalProviderCaptureAuthorityIsFrozen)
        let publicJSON = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!publicJSON.contains(id.uuidString))
        #expect(!publicJSON.contains("externalProviderCaptureAuthority"))
    }

    #if os(iOS)
    @Test(arguments: [false, true])
    func scheduledAPIAdmissionCapturesProvidersEvenWhenLocalSidecarsAreSuppressed(profile: Bool) async throws {
        try #require(ConnectedAppsFeature.isEnabled)
        let (settings, _, _) = fixture()
        settings.generateRangeSummary = true
        settings.summaryOnlyExport = true
        #expect(!settings.writesExternalProviderSidecars)
        let provider = Provider()
        let scheduler = SchedulingManager(persistScheduleChanges: false, systemSideEffectsEnabled: false)
        let sync = SyncService()
        Self.retained += [scheduler, sync]
        scheduler.configureScheduledExportDependencies(syncService: sync, externalIntegrations: provider)
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let snapshot = await AppleSleepCaptureContext.pinned.withValue(context) {
            if profile {
                let original = ExportSettingsSnapshot.from(settings, healthSubfolder: "Saved", calendarTimeZoneIdentifier: "UTC")
                let request = ScheduledExportCoordinator.ScheduledProfileRequestContext(profileID: UUID(),
                    profileName: "Synthetic", target: .apiEndpoint, settings: original)
                return await scheduler.makeSettingsSnapshotForNewScheduledProfileOperation(request)
            }
            return await scheduler.makeSettingsSnapshotForNewScheduledOperation(target: .apiEndpoint,
                settings: settings, calendarTimeZone: .gmt)
        }
        #expect(snapshot.sleepCaptureContext == context)
        #expect(try #require(snapshot.appleExportEnginePin).isWakeDate)
        #expect(snapshot.externalProviderCaptureAuthority?.connections["whoop"] == provider.currentID)
        #expect(provider.captureCalls == 1)
        #expect(provider.expectedIDs.isEmpty)
        if profile { #expect(snapshot.healthSubfolder == "Saved") }
    }
    #endif

    private func fixture() -> (AdvancedExportSettings, HealthKitManager, FakeHealthStore) {
        let defaults = UserDefaults(suiteName: "APIProviderCaptureTests.\(UUID())")!
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.exportTimeZoneOverride = TimeZone(secondsFromGMT: 0)!
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 42
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        manager.setSleepDayAttribution(.morningEnds)
        Self.retained += [settings, manager]
        return (settings, manager, store)
    }

    private var dates: [Date] { [Date(timeIntervalSince1970: 1_777_766_400), Date(timeIntervalSince1970: 1_777_852_800)] }
    private var destination: APIExportDestinationSnapshot {
        .init(endpointURL: URL(string: "https://synthetic.invalid/export")!, authorizationHeaderValue: nil,
            displayName: "Synthetic", redactedEndpointDescription: "synthetic.invalid")
    }

    @MainActor private final class Provider: ExternalIntegrationDailyRecordProviding {
        var currentID: UUID? = UUID()
        var captureCalls = 0
        var beginCount = 0
        var endCount = 0
        var expectedIDs: [UUID?] = []
        var onBegin: (() -> Void)?
        var onFirstFetch: (() -> Void)?
        var connectedProviderCount: Int { currentID == nil ? 0 : 1 }
        func forCaptureOperation() -> any ExternalIntegrationDailyRecordProviding {
            captureCalls += 1
            return Scope(root: self, authority: .init(connections: ["whoop": currentID]))
        }
        func forCaptureOperation(authority: ExternalProviderCaptureAuthority) throws -> any ExternalIntegrationDailyRecordProviding {
            Scope(root: self, authority: authority)
        }
        func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] { records(date, expected: currentID) }
        func fetchDailyRecords(for date: Date, providerIDs: Set<String>) async -> [ExternalDailyRecord] { await fetchDailyRecords(for: date) }
        func records(_ date: Date, expected: UUID?) -> [ExternalDailyRecord] {
            expectedIDs.append(expected)
            let available = expected != nil && expected == currentID
            let record = ExternalDailyRecord(provider: .whoop, date: APIExportClient.dayString(from: date, timeZone: .gmt),
                payloads: available ? [.init(name: "cycles", endpoint: "https://synthetic.invalid/cycles", statusCode: 200,
                    data: .object(["accepted_source": .bool(true)]))] : [],
                warnings: available ? [] : ["connection unavailable"])
            if expectedIDs.count == 1 { onFirstFetch?() }
            return [record]
        }
    }

    @MainActor private final class Scope: ExternalIntegrationDailyRecordProviding {
        let root: Provider
        let authority: ExternalProviderCaptureAuthority
        init(root: Provider, authority: ExternalProviderCaptureAuthority) { self.root = root; self.authority = authority }
        var captureAuthority: ExternalProviderCaptureAuthority? { authority }
        var connectedProviderCount: Int { authority.connections.count }
        func forCaptureOperation(authority: ExternalProviderCaptureAuthority) throws -> any ExternalIntegrationDailyRecordProviding {
            guard authority == self.authority else { throw ExternalProviderCaptureAuthority.RecoveryError.unavailable }
            return self
        }
        func beginExportAction() { root.beginCount += 1; root.onBegin?() }
        func endExportAction(succeeded: Bool) { root.endCount += 1 }
        func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] {
            root.records(date, expected: authority.connections["whoop"] ?? nil)
        }
        func fetchDailyRecords(for date: Date, providerIDs: Set<String>) async -> [ExternalDailyRecord] { await fetchDailyRecords(for: date) }
    }
}
