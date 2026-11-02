import XCTest
@testable import HealthMd

/// Per-category compatibility detail on Apple: legacy byte stability, durable round-trips,
/// fail-closed decoding, preset independence, capture sanitizing, and Mac capability gating.
final class ExportDetailOverridesTests: XCTestCase {
    private let sleepDetailedOnly = AppleExportDetailPolicy.summary
        .settingCompatibilityDetail(.detailed, for: .sleep)

    func testMissingOverridesReproduceTheUniformPolicy() {
        for policy in [AppleExportDetailPolicy.summary, .detailedTimeSeries, .archiveOnly, .lossless] {
            for group in ExportDetailGroup.appleSupported {
                XCTAssertEqual(
                    policy.includesSelectedTimeSeries(for: group),
                    policy.compatibilityDetail.includesSelectedTimeSeries
                )
            }
            XCTAssertFalse(policy.hasDetailOverrides)
        }
    }

    func testMixedPolicySelectsSleepWithoutHeartOrVitals() {
        XCTAssertTrue(sleepDetailedOnly.includesSelectedTimeSeries(for: .sleep))
        XCTAssertFalse(sleepDetailedOnly.includesSelectedTimeSeries(for: .heart))
        XCTAssertFalse(sleepDetailedOnly.includesSelectedTimeSeries(for: .vitals))
        XCTAssertTrue(sleepDetailedOnly.includesSelectedTimeSeries)
        XCTAssertFalse(sleepDetailedOnly.includesCanonicalArchive)

        let heartSummaryUnderDetail = AppleExportDetailPolicy.detailedTimeSeries
            .settingCompatibilityDetail(.summary, for: .heart)
        XCTAssertFalse(heartSummaryUnderDetail.includesSelectedTimeSeries(for: .heart))
        XCTAssertTrue(heartSummaryUnderDetail.includesSelectedTimeSeries(for: .vitals))
    }

    func testUnsupportedAppleChoicesAreNeverStored() {
        // HealthKit has no source sleep sessions, and Apple gates only sleep/heart/vitals/workouts.
        XCTAssertFalse(AppleExportDetailPolicy.summary.settingCompatibilityDetail(.sessions, for: .sleep).hasDetailOverrides)
        XCTAssertFalse(AppleExportDetailPolicy.summary.settingCompatibilityDetail(.sessions, for: .workouts).hasDetailOverrides)
        XCTAssertFalse(AppleExportDetailPolicy.summary.settingCompatibilityDetail(.detailed, for: .activity).hasDetailOverrides)
    }

    func testPresetsDescribeTheDefaultAndKeepExplicitChoices() {
        XCTAssertEqual(AppleExportDetailPreset(policy: sleepDetailedOnly), .summary)
        let lossless = sleepDetailedOnly.replacingBase(with: .lossless)
        XCTAssertEqual(AppleExportDetailPreset(policy: lossless), .losslessHealthRecords)
        XCTAssertEqual(lossless.compatibilityDetailOverrides, [.sleep: .detailed])
        XCTAssertFalse(lossless.isLegacyRepresentable)
        // Old decoders see the safe Summary bridge rather than an approximated Lossless.
        XCTAssertFalse(lossless.legacyIncludeGranularData)
        XCTAssertEqual(lossless.historyDetailLevelToken, "custom_with_archive")
        XCTAssertEqual(sleepDetailedOnly.historyDetailLevelToken, "custom")
        XCTAssertEqual(AppleExportDetailPolicy.lossless.historyDetailLevelToken, "lossless")
    }

    func testSnapshotWithoutOverridesKeepsHistoricalBytes() throws {
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: try isolatedDefaults()))
        settings.detailPolicy = .detailedTimeSeries
        let encoded = try JSONEncoder().encode(ExportSettingsSnapshot.from(settings))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["compatibilityDetailOverrides"])
        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.detailPolicy, .detailedTimeSeries)
    }

    func testSnapshotRoundTripsOverridesForProfilesAndPendingJobs() throws {
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: try isolatedDefaults()))
        settings.detailPolicy = sleepDetailedOnly
        let snapshot = ExportSettingsSnapshot.from(settings)
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["compatibilityDetailOverrides"] as? [String: String], ["sleep": "detailed"])
        // The compatibility Boolean bridge stays false for split/override states.
        XCTAssertEqual(object["includeGranularData"] as? Bool, false)

        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.detailPolicy, sleepDetailedOnly)
        // Recovery rebuilds request-scoped settings from the frozen snapshot, not live defaults.
        let restored = LifecycleHarness.retain(AdvancedExportSettings(snapshot: decoded, userDefaults: try isolatedDefaults()))
        XCTAssertEqual(restored.detailPolicy, sleepDetailedOnly)
    }

    func testUnknownOrUnsupportedSnapshotOverridesFailDecoding() throws {
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: try isolatedDefaults()))
        settings.detailPolicy = sleepDetailedOnly
        let encoded = try JSONEncoder().encode(ExportSettingsSnapshot.from(settings))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for tampered in [["sleep": "sessions"], ["activity": "detailed"], ["workouts": "sessions"], ["future": "detailed"], ["sleep": "verbose"]] {
            object["compatibilityDetailOverrides"] = tampered
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(ExportSettingsSnapshot.self, from: data))
        }
    }

    func testLiveSettingsPersistOverridesAcrossLaunches() throws {
        let defaults = try isolatedDefaults()
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        settings.setCompatibilityDetail(.detailed, for: .sleep)
        settings.setCompatibilityDetail(.summary, for: .heart)
        settings.compatibilityDetail = .selectedTimeSeries

        let reloaded = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        XCTAssertEqual(reloaded.compatibilityDetailOverrides, [.sleep: .detailed, .heart: .summary])
        XCTAssertFalse(reloaded.detailPolicy.includesSelectedTimeSeries(for: .heart))
        XCTAssertTrue(reloaded.detailPolicy.includesSelectedTimeSeries(for: .vitals))

        reloaded.setCompatibilityDetail(nil, for: .sleep)
        reloaded.setCompatibilityDetail(nil, for: .heart)
        XCTAssertNil(defaults.object(forKey: "advancedExportSettings.compatibilityDetailOverrides"))
    }

    func testPreOverrideInstallsLoadWithNoOverrides() throws {
        let defaults = try isolatedDefaults()
        defaults.set(true, forKey: "advancedExportSettings.includeGranularData")
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        XCTAssertEqual(settings.detailPolicy, .lossless)
        XCTAssertTrue(settings.compatibilityDetailOverrides.isEmpty)
    }

    func testSanitizerAppliesEachGroupIndependently() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var record = HealthData(date: start)
        record.sleep.stages = [SleepStageSample(stage: "deep", startDate: start, endDate: start.addingTimeInterval(3600))]
        record.heart.heartRateSamples = [TimeSample(timestamp: start, value: 61)]
        record.heart.hrvSamples = [TimeSample(timestamp: start, value: 40)]
        record.vitals.bloodOxygenSamples = [TimeSample(timestamp: start, value: 0.97)]

        let sanitized = ConnectedExportDetailPolicy.sanitized(record, detailPolicy: sleepDetailedOnly)
        XCTAssertEqual(sanitized.sleep.stages.count, 1)
        XCTAssertTrue(sanitized.heart.heartRateSamples.isEmpty)
        XCTAssertTrue(sanitized.heart.hrvSamples.isEmpty)
        XCTAssertTrue(sanitized.vitals.bloodOxygenSamples.isEmpty)
    }

    func testWorkoutOverrideSelectsWorkoutDetailIndependently() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var record = HealthData(date: start)
        record.heart.heartRateSamples = [TimeSample(timestamp: start, value: 61)]
        record.workouts = [WorkoutData(
            workoutType: .running,
            startTime: start,
            duration: 600,
            calories: 100,
            distance: 1_000,
            route: [RoutePoint(
                timestamp: start, latitude: 1, longitude: 2, altitudeMeters: nil,
                speedMps: nil, courseDegrees: nil, horizontalAccuracyMeters: nil
            )],
            timeSeries: WorkoutTimeSeries(heartRate: [TimeSeriesSample(timestamp: start, value: 120)])
        )]

        let workoutsOnly = AppleExportDetailPolicy.summary.settingCompatibilityDetail(.detailed, for: .workouts)
        let detailed = ConnectedExportDetailPolicy.sanitized(record, detailPolicy: workoutsOnly)
        XCTAssertEqual(detailed.workouts.first?.route.count, 1)
        XCTAssertFalse(try XCTUnwrap(detailed.workouts.first).timeSeries.isEmpty)
        XCTAssertTrue(detailed.heart.heartRateSamples.isEmpty)

        let workoutsSummary = AppleExportDetailPolicy.detailedTimeSeries.settingCompatibilityDetail(.summary, for: .workouts)
        let summarized = ConnectedExportDetailPolicy.sanitized(record, detailPolicy: workoutsSummary)
        let workout = try XCTUnwrap(summarized.workouts.first)
        XCTAssertTrue(workout.route.isEmpty && workout.timeSeries.isEmpty)
        // Per-workout totals never change with detail.
        XCTAssertEqual(workout.calories, 100)
        XCTAssertEqual(workout.distance, 1_000)
        XCTAssertEqual(summarized.heart.heartRateSamples.count, 1)
    }

    func testMacPeersWithoutPerGroupSupportAreRefused() throws {
        let current = SyncPeerCapabilities.current(platform: .macOS, installationID: UUID())
        XCTAssertTrue(current.supportsPerGroupExportDetail)
        // A peer from before this capability omits the key and decodes as unsupported.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        object.removeValue(forKey: "supportsPerGroupExportDetail")
        let old = try JSONDecoder().decode(SyncPeerCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.supportsPerGroupExportDetail)

        XCTAssertTrue(current.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false, detailPolicy: sleepDetailedOnly))
        XCTAssertFalse(old.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false, detailPolicy: sleepDetailedOnly))
        XCTAssertTrue(old.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false, detailPolicy: .detailedTimeSeries))
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "healthmd.tests.export-detail-overrides.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
