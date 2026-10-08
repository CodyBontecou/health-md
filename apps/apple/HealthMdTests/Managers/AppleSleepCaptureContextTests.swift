import Foundation
import XCTest
import HealthMdCoreRust
@testable import HealthMd

@MainActor
final class AppleSleepCaptureContextTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    func testBothPreferenceMutationDirectionsRetainOperationAuthorityAtEveryDailyResolution() async throws {
        let changes: [(SleepDayAttribution, SleepDayAttribution)] = [(.nightBegins, .morningEnds), (.morningEnds, .nightBegins)]
        for (initial, changed) in changes {
            var preference = initial
            let context = AppleSleepCaptureContext.resolve(timeZone: zone, attribution: preference)
            try await AppleSleepCaptureContext.pinned.withValue(context) {
                let first = AppleSleepCaptureContext.resolve(attribution: preference)
                await Task.yield()
                preference = changed
                let second = AppleSleepCaptureContext.resolve(attribution: preference)
                XCTAssertEqual(first, context)
                XCTAssertEqual(second, context, "A daily fetch must not shadow the operation pin")
                if initial == .nightBegins {
                    XCTAssertNoThrow(try second.requireShippedProfile())
                } else {
                    XCTAssertThrowsError(try second.requireShippedProfile()) {
                        XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .unapprovedAttribution)
                    }
                }
            }
        }
    }

    func testConcurrentOperationsDoNotBorrowEachOthersContext() async {
        let first = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
        let second = AppleSleepCaptureContext(timeZone: TimeZone(identifier: "Europe/Berlin")!, sleepDayAttribution: .morningEnds)
        async let a = resolveRepeatedly(in: first)
        async let b = resolveRepeatedly(in: second)
        let results = await (a, b)
        XCTAssertTrue(results.0.allSatisfy { $0 == first })
        XCTAssertTrue(results.1.allSatisfy { $0 == second })
    }

    func testDurableRoundTripPreservesUnavailableAttributionAndMissingAuthorityNeverUsesPreference() throws {
        let pending = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(pending)
        let restored = try JSONDecoder().decode(AppleSleepCaptureContext.self, from: bytes)
        XCTAssertEqual(restored, pending)
        XCTAssertThrowsError(try AppleSleepCaptureContext.recovered(restored))
        XCTAssertEqual(try encoder.encode(restored), bytes, "Do not coerce or rewrite pending authority")
        let night = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
        XCTAssertThrowsError(try AppleSleepCaptureContext.pinned.withValue(night) {
            try AppleSleepCaptureContext.recovered(nil)
        }) {
            XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .missingDurableAttribution)
        }
        XCTAssertEqual(try AppleSleepCaptureContext.recovered(night), night)
    }

    func testCurrentWriterProfilesRejectMorningEndsWithoutCoercingContext() {
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        XCTAssertThrowsError(try context.requireShippedProfile())
        XCTAssertEqual(context.sleepDayAttribution, .morningEnds)
        XCTAssertNoThrow(try AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins).requireShippedProfile())
    }

    func testFreshWakeDateAuthorityCarriesAnExplicitSuccessorProfile() throws {
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
        XCTAssertEqual(object["exportProfileID"] as? String, "apple-v11",
                       "A draft-era attribution value alone is not approval for a new profile")
    }

    func testDraftMorningRecoveryNeverInventsSuccessorAuthority() throws {
        let bytes = Data(#"{"calendarTimeZoneIdentifier":"GMT","sleepDayAttribution":"morning_ends"}"#.utf8)
        let restored = try JSONDecoder().decode(AppleSleepCaptureContext.self, from: bytes)
        XCTAssertEqual(restored.sleepDayAttribution, .morningEnds)
        XCTAssertNil(restored.exportProfileID)
        XCTAssertThrowsError(try AppleSleepCaptureContext.recovered(restored)) {
            XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .unversionedAttribution)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(restored), bytes, "Do not upgrade or rewrite a draft pending context")
    }

    func testRetiredV10DraftAuthorityIsPreservedWithoutUpgrading() throws {
        let bytes = Data(#"{"calendarTimeZoneIdentifier":"GMT","exportProfileID":"apple-v10","sleepDayAttribution":"morning_ends"}"#.utf8)
        let restored = try JSONDecoder().decode(AppleSleepCaptureContext.self, from: bytes)
        XCTAssertEqual(restored.exportProfileID, "apple-v10")
        XCTAssertThrowsError(try restored.requireShippedProfile()) {
            XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .unversionedAttribution)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(restored), bytes)
        let day = HealthData(date: Date(timeIntervalSince1970: 1_700_000_000),
            timeContext: ExportTimeContext(timeZone: restored.timeZone, sleepDayAttribution: .morningEnds))
        XCTAssertThrowsError(try day.toJSONDataThrowing(captureContext: restored))
    }

    func testHistoricalNightAuthorityRetainsItsExactEncoding() throws {
        let bytes = Data(#"{"calendarTimeZoneIdentifier":"GMT","sleepDayAttribution":"night_begins"}"#.utf8)
        let restored = try JSONDecoder().decode(AppleSleepCaptureContext.self, from: bytes)
        XCTAssertNil(restored.exportProfileID)
        XCTAssertEqual(try AppleSleepCaptureContext.recovered(restored), restored)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(restored), bytes)
        XCTAssertEqual(try encoder.encode(AppleSleepCaptureContext(timeZone: TimeZone(identifier: "UTC")!, sleepDayAttribution: .nightBegins)), bytes)
    }

    func testAttributionProfileMismatchFailsWithABoundedError() throws {
        for (mode, profile) in [("night_begins", "apple-v11"), ("morning_ends", "apple-v8"), ("morning_ends", "private-invalid-profile")] {
            let object = ["calendarTimeZoneIdentifier": "UTC", "sleepDayAttribution": mode, "exportProfileID": profile]
            let bytes = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(AppleSleepCaptureContext.self, from: bytes)) {
                guard case DecodingError.dataCorrupted(let context) = $0 else {
                    return XCTFail("Expected bounded profile validation error")
                }
                XCTAssertEqual(context.debugDescription, "Invalid capture export profile")
                XCTAssertFalse(context.debugDescription.contains(profile))
            }
        }
    }

    func testPendingRecoveryRejectsSavedRendererClockMismatchWithoutChangingJournal() throws {
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
        let suite = "SleepAuthorityPairTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        var snapshot = ExportSettingsSnapshot.from(settings)
        snapshot.sleepCaptureContext = context
        snapshot.calendarTimeZoneIdentifier = zone.identifier
        snapshot.appleExportEngineAuthorityIsFrozen = true
        snapshot.appleExportEnginePin = try makeSyntheticAppleExportEnginePin(calendarTimeZoneIdentifier: "Europe/Berlin")
        let store = PendingExportStore(userDefaults: defaults)
        let request = PendingExportRequest(dates: [Date(timeIntervalSince1970: 1_793_505_600)],
            source: .shortcut, settingsSnapshot: snapshot)
        try store.upsert(request)
        let saved = try XCTUnwrap(store.loadAll().first)
        let originalBytes = try XCTUnwrap(defaults.data(forKey: PendingExportStore.storageKey))
        XCTAssertThrowsError(try saved.recoveredSleepCaptureContext(), "Saved renderer and capture clocks must agree before capture")
        XCTAssertEqual(try store.loadAll(), [saved], "Validation must retain the saved authority for explicit recovery")
        XCTAssertEqual(defaults.data(forKey: PendingExportStore.storageKey), originalBytes)
    }

    func testSavedSuccessorAuthorityRequiresAnExplicitFrozenCompatiblePairAndKeepsProductionGate() throws {
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let suite = "SleepSuccessorAuthorityTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let service = HealthMdCoreService()
        let registry = try service.metricRegistry(profile: .appleHealthDataV11,
            expectedRegistryVersion: HealthMdSleepProfileContract.registryVersion)
        let pin = try AppleExportEnginePin(engine: .rust, calendarTimeZoneIdentifier: zone.identifier,
            buildInfo: service.buildInfo(), registrySnapshot: registry)
        var snapshot = ExportSettingsSnapshot.from(settings, appleExportEnginePin: pin,
            appleExportEngineAuthorityIsFrozen: true, calendarTimeZoneIdentifier: zone.identifier)
        snapshot.sleepCaptureContext = context
        let encoder = JSONEncoder()
        encoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        let restored = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: encoder.encode(snapshot))
        let opposite = AppleSleepCaptureContext(timeZone: TimeZone(identifier: "Europe/Berlin")!, sleepDayAttribution: .nightBegins)
        try AppleSleepCaptureContext.pinned.withValue(opposite) {
            XCTAssertEqual(try restored.validatedSleepCaptureContext(), context)
            XCTAssertThrowsError(try restored.recoveredSleepCaptureContext()) {
                XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .unapprovedAttribution)
            }
        }
        var missingPin = restored
        missingPin.appleExportEnginePin = nil
        var mutableEngine = restored
        mutableEngine.appleExportEngineAuthorityIsFrozen = false
        var missingClock = restored
        missingClock.calendarTimeZoneIdentifier = nil
        var wrongClock = restored
        wrongClock.calendarTimeZoneIdentifier = "Europe/Berlin"
        var historicalPin = restored
        historicalPin.appleExportEnginePin = try makeSyntheticAppleExportEnginePin(calendarTimeZoneIdentifier: zone.identifier)
        var historicalContext = restored
        historicalContext.sleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
        var downgradedPin = restored
        var pinObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pin)) as? [String: Any])
        pinObject["render_input_version"] = 1
        downgradedPin.appleExportEnginePin = try JSONDecoder().decode(AppleExportEnginePin.self,
            from: JSONSerialization.data(withJSONObject: pinObject))
        for invalid in [missingPin, mutableEngine, missingClock, wrongClock, historicalPin, historicalContext, downgradedPin] {
            XCTAssertThrowsError(try invalid.validatedSleepCaptureContext()) {
                XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .incompatibleDurableAuthority)
            }
        }
        XCTAssertEqual(restored.sleepCaptureContext, context)
        XCTAssertEqual(restored.appleExportEnginePin, pin)
        XCTAssertThrowsError(try restored.validatedSleepCaptureContext(captureContext: opposite))
    }

    private func resolveRepeatedly(in context: AppleSleepCaptureContext) async -> [AppleSleepCaptureContext] {
        await AppleSleepCaptureContext.pinned.withValue(context) {
            var values: [AppleSleepCaptureContext] = []
            for _ in 0..<20 {
                await Task.yield()
                values.append(AppleSleepCaptureContext.resolve(attribution: .nightBegins))
            }
            return values
        }
    }
}
