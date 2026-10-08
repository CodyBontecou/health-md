import Foundation
import HealthKit
import HealthMdCoreRust
import XCTest
@testable import HealthMd

/// Real application planner → packaged Rust → public artifact bytes.
/// Only HealthKit IPC and nondeterministic operation identity are substituted.
@MainActor
final class AppleWakeDateExportPlannerTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation
    // state that is unsafe during test teardown; see docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testMixedNativeMetricsRetainSourcePrecisionAndUnselectedMetricsDoNotBlockPlanning() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let owner = try XCTUnwrap(ExportDateFormatting.utcISO8601Formatter().date(from: "2026-11-01T04:00:00Z"))
        var day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.activity.steps = 0
        day.activity.walkingRunningDistance = 1_234.56789
        day.heart.averageHeartRate = 70.125
        day.vitals.bloodOxygenAvg = 0.975125
        day.body.weight = 72.123456
        day.nutrition.protein = 12.345678
        let selected: Set<String> = ["steps", "distance_walking_running", "heart_rate_avg", "blood_oxygen", "weight", "dietary_protein"]
        for selection in [selected, ["steps"]] {
            let snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: selection)
            let resolution = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot,
                surface: .localVaultWithoutSideEffects)
            guard case .planned(let operation) = resolution else {
                return XCTFail("Typed non-sleep metrics must reach the successor planner")
            }
            XCTAssertEqual(operation.artifacts.count, 4)
            for artifact in operation.artifacts where artifact.format == .markdown || artifact.format == .obsidianBases {
                let text = String(decoding: artifact.artifact.inlineData, as: UTF8.self)
                XCTAssertTrue(text.contains("steps: 0\n"))
                if selection == selected {
                    for (key, expected) in [("average_heart_rate", 70.125), ("blood_oxygen_avg", 97.5125),
                                            ("weight_kg", 72.123456), ("protein_g", 12.345678),
                                            ("walking_running_km", 1.23456789)] {
                        let line = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("\(key): ") }, key)
                        let value = try XCTUnwrap(Double(line.dropFirst(key.count + 2)), key)
                        XCTAssertEqual(value, expected, accuracy: 1e-12, key)
                    }
                } else {
                    XCTAssertFalse(text.contains("weight_kg:"))
                    XCTAssertFalse(text.contains("average_heart_rate:"))
                }
            }
        }
    }

    func testEveryDailyFormatSharesWakeDateAuthorityAndUnroundedSourceQuantities() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let owner = try XCTUnwrap(formatter.date(from: "2026-11-01T04:00:00Z"))
        let start = try XCTUnwrap(formatter.date(from: "2026-11-01T02:00:00Z")).addingTimeInterval(0.25)
        let end = try XCTUnwrap(formatter.date(from: "2026-11-01T17:30:00Z")).addingTimeInterval(0.75)
        var day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            sleep: SleepData(totalDuration: 55_800.5, coreSleep: 3_600.5, inBedTime: 55_800.5,
                sessionStart: start, sessionEnd: end))
        day.activity.steps = 1_234
        day.activity.activeCalories = 123.875
        let snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases))
        let resolution = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot,
            surface: .localVaultWithoutSideEffects)
        guard case .planned(let operation) = resolution else {
            return XCTFail("All successor formats must be planned under the same authority")
        }
        XCTAssertEqual(operation.artifacts.count, 4)
        XCTAssertEqual(operation.selectedPlan.artifactPlanVersion, 2)
        XCTAssertEqual(operation.selectedPlan.profile, .appleHealthDataV10)
        for planned in operation.artifacts {
            let text = try XCTUnwrap(String(data: planned.artifact.inlineData, encoding: .utf8))
            switch planned.format {
            case .json:
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: planned.artifact.inlineData) as? [String: Any])
                XCTAssertEqual(root["schema_version"] as? Int, 10)
                XCTAssertEqual((root["sleep"] as? [String: Any])?["totalDuration"] as? Double, 55_800.5)
                XCTAssertEqual((root["activity"] as? [String: Any])?["activeCalories"] as? Double, 123.875)
            case .markdown, .obsidianBases:
                XCTAssertTrue(text.contains("schema_version: 10\n"))
                XCTAssertTrue(text.contains("schema_profile: apple-v10\n"))
                XCTAssertTrue(text.contains("sleep_day_attribution: morning_ends\n"))
                XCTAssertTrue(text.contains("sleep_owner_day_rule: session_end_date\n"))
                XCTAssertTrue(text.contains("sleep_interval_clipping: none\n"))
                XCTAssertTrue(text.contains("calendar_timezone: America/New_York\n"))
                let total = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("sleep_total_hours: ") })
                let core = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("sleep_core_hours: ") })
                XCTAssertEqual(Double(total.dropFirst("sleep_total_hours: ".count)), 15.50013888888889)
                XCTAssertEqual(Double(core.dropFirst("sleep_core_hours: ".count)), 1.000138888888889)
                XCTAssertTrue(text.contains("active_calories: 123.875\n"))
                XCTAssertFalse(text.contains("sleep_light_hours"))
            case .csv:
                XCTAssertTrue(text.hasPrefix("Date,Category,Metric,Value,Unit,Timestamp\n"))
                XCTAssertTrue(text.contains("2026-11-01,Metadata,schema_version,10,,\n"))
                XCTAssertTrue(text.contains("2026-11-01,Metadata,schema_profile,apple-v10,,\n"))
                XCTAssertTrue(text.contains("2026-11-01,Metadata,time_context.sleep_owner_day_rule,session_end_date,,\n"))
                let row = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("2026-11-01,Sleep,Total Sleep,") })
                XCTAssertEqual(Double(row.components(separatedBy: ",")[3]), 15.50013888888889)
                XCTAssertTrue(text.contains(",123.875,kcal,\n"))
            }
        }
    }

    func testEmptySleepAndMetadataOffKeepOneAuthorityAcrossADateRange() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let first = try XCTUnwrap(formatter.date(from: "2026-11-01T04:00:00Z"))
        let second = try XCTUnwrap(formatter.date(from: "2026-11-02T05:00:00Z"))
        var emptySleep = HealthData(date: first, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        emptySleep.activity.steps = 0
        var populated = HealthData(date: second, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            sleep: SleepData(totalDuration: 3_600, coreSleep: 3_600, sessionStart: second.addingTimeInterval(-3_600), sessionEnd: second))
        populated.activity.steps = 1_234
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases))
        snapshot.includeMetadata = false
        let resolution = try await AppleLooseDailyExportPlanner().planRange(healthData: [populated, emptySleep],
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
        guard case .planned(let operation) = resolution else {
            return XCTFail("Empty sleep is not permission to drop successor authority")
        }
        XCTAssertEqual(operation.artifacts.count, 8)
        let json = operation.artifacts.filter { $0.format == .json }.map(\.artifact)
        XCTAssertEqual(json.count, 2)
        for artifact in json {
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: artifact.inlineData) as? [String: Any])
            XCTAssertEqual(root["schema_profile"] as? String, "apple-v10")
            XCTAssertEqual(root["schema_version"] as? Int, 10)
            XCTAssertEqual((root["time_context"] as? [String: String])?["sleep_interval_clipping"], "none")
            if root["date"] as? String == "2026-11-01" {
                XCTAssertNil(root["sleep"])
                XCTAssertEqual((root["activity"] as? [String: Any])?["steps"] as? Int, 0)
            } else {
                XCTAssertEqual(root["date"] as? String, "2026-11-02")
                XCTAssertEqual((root["sleep"] as? [String: Any])?["wakeTimeISO"] as? String, "2026-11-02T05:00:00.000000000Z")
            }
        }
        for markdown in operation.artifacts.filter({ $0.format == .markdown }) {
            let text = try XCTUnwrap(String(data: markdown.artifact.inlineData, encoding: .utf8))
            XCTAssertFalse(text.hasPrefix("---\n"))
            XCTAssertTrue(text.contains("Health.md sleep attribution: `morning_ends`"))
            XCTAssertTrue(text.contains("Profile: `apple-v10`; calendar timezone: `America/New_York`"))
            XCTAssertTrue(text.contains("owner rule: `session_end_date`; clipping: `none`"))
        }
        let emptyBases = try XCTUnwrap(operation.artifacts.first {
            $0.format == .obsidianBases && $0.artifact.relativePath.contains("2026-11-01")
        })
        XCTAssertTrue(String(decoding: emptyBases.artifact.inlineData, as: UTF8.self).contains("steps: 0\n"))
    }

    func testMissingDraftConflictingAndHistoricalPinsNeverRenderMorningAsLegacy() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let date = try XCTUnwrap(ExportDateFormatting.utcISO8601Formatter().date(from: "2026-11-01T04:00:00Z"))
        var day = HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.activity.steps = 1_234
        let accepted = try acceptedSnapshot(context: context, formats: [.json])
        let draft = try JSONDecoder().decode(AppleSleepCaptureContext.self, from: Data("""
            {"calendarTimeZoneIdentifier":"America/New_York","sleepDayAttribution":"morning_ends"}
            """.utf8))
        var missing = accepted
        missing.sleepCaptureContext = nil
        var unversioned = accepted
        unversioned.sleepCaptureContext = draft
        var wrongMode = accepted
        wrongMode.sleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
        var wrongClock = accepted
        wrongClock.calendarTimeZoneIdentifier = "Europe/Berlin"
        var missingPin = accepted
        missingPin.appleExportEnginePin = nil
        var historical = accepted
        let service = HealthMdCoreService()
        historical.appleExportEnginePin = try AppleExportEnginePin(engine: .rust, calendarTimeZoneIdentifier: zone.identifier,
            buildInfo: service.buildInfo(), registrySnapshot: service.metricRegistry(profile: .appleHealthDataV8))
        var defaultedPin = accepted
        let pinData = try JSONEncoder().encode(try XCTUnwrap(accepted.appleExportEnginePin))
        var pinObject = try XCTUnwrap(JSONSerialization.jsonObject(with: pinData) as? [String: Any])
        pinObject["render_input_version"] = 1
        defaultedPin.appleExportEnginePin = try JSONDecoder().decode(AppleExportEnginePin.self,
            from: JSONSerialization.data(withJSONObject: pinObject))
        for snapshot in [missing, unversioned, wrongMode, wrongClock, missingPin, historical, defaultedPin] {
            do {
                _ = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot,
                    surface: .localVaultWithoutSideEffects)
                XCTFail("Incompatible authority must fail, not return a historical resolution")
            } catch {
                XCTAssertEqual(error as? AppleLooseDailyExportPlannerError, .rustPlanningFailed)
            }
        }
        XCTAssertNil(unversioned.sleepCaptureContext?.exportProfileID)
        var night = HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone))
        night.activity = day.activity
        do {
            _ = try await AppleLooseDailyExportPlanner().plan(healthData: night, settingsSnapshot: accepted,
                surface: .localVaultWithoutSideEffects)
            XCTFail("A successor cannot relabel historical captured data")
        } catch {
            XCTAssertEqual(error as? AppleLooseDailyExportPlannerError, .rustPlanningFailed)
        }
    }

    private func acceptedSnapshot(
        context: AppleSleepCaptureContext, formats: Set<ExportFormat>, selectionIDs: Set<String>? = nil
    ) throws -> ExportSettingsSnapshot {
        let suite = "AppleWakeDatePlannerFixture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = formats
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.includeGranularData = false
        settings.generateRangeSummary = false
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        settings.exportTimeZoneOverride = context.timeZone
        settings.executionSleepCaptureContext = context
        settings.executionSleepCaptureContextIsFrozen = true
        settings.metricSelection.enabledMetrics = selectionIDs ?? [
            "sleep_total", "sleep_core", "sleep_in_bed", "sleep_bedtime", "sleep_wake", "steps", "active_energy",
        ]
        let encoded: [String: Any] = [
            "engine": "rust", "profile": "apple_health_data_v10", "public_schema": "healthmd.health_data",
            "public_schema_version": 10, "core_api_version": 4, "semantic_input_version": 2,
            "canonical_model_version": 2, "render_input_version": 2, "artifact_plan_version": 2,
            "registry_version": 2, "registry_sha256": "c1854454bee84b6d74cee1d7457d3fde1f484ef74963a656adba503c91cb9073",
            "semantic_profile_revision": 1, "render_profile_revision": 2,
            "core_source_revision": "synthetic-planner-contract", "calendar_time_zone": context.calendarTimeZoneIdentifier,
        ]
        let pin = try JSONDecoder().decode(AppleExportEnginePin.self,
            from: JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys]))
        return ExportSettingsSnapshot.from(settings, healthSubfolder: "Health", appleExportEnginePin: pin,
            calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier)
    }

    func testPinnedWholeSessionReachesNativeSuccessorJSONWithoutHistoricalFallback() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let ownerDate = try XCTUnwrap(formatter.date(from: "2026-11-01T04:00:00Z"))
        let start = try XCTUnwrap(formatter.date(from: "2026-11-01T02:00:00Z")).addingTimeInterval(0.25)
        let end = try XCTUnwrap(formatter.date(from: "2026-11-01T17:30:00Z")).addingTimeInterval(0.75)
        let foldStart = try XCTUnwrap(formatter.date(from: "2026-11-01T05:30:00Z")).addingTimeInterval(0.25)
        let foldEnd = try XCTUnwrap(formatter.date(from: "2026-11-01T06:30:00Z")).addingTimeInterval(0.75)
        let store = FakeHealthStore()
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                startDate: start, endDate: end),
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                startDate: foldStart, endDate: foldEnd,
                metadata: ["HKTimeZone": "America/New_York", "synthetic": "planner-fold-core"]),
        ]
        let suite = "AppleWakeDateExportPlannerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let sleep = try await manager.fetchSleepProjection(for: ownerDate, attribution: .morningEnds,
            timeZone: zone, includeDetailedTimeSeries: true)
        var day = HealthData(date: ownerDate,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds), sleep: sleep)
        day.activity.steps = 1_234
        day.activity.activeCalories = 123.875
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.includeGranularData = false
        settings.generateRangeSummary = false
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = context
        settings.executionSleepCaptureContextIsFrozen = true
        settings.metricSelection.enabledMetrics = [
            "sleep_total", "sleep_core", "sleep_in_bed", "sleep_bedtime", "sleep_wake", "steps", "active_energy",
        ]
        let pin = try JSONDecoder().decode(AppleExportEnginePin.self, from: Data("""
            {"engine":"rust","profile":"apple_health_data_v10","public_schema":"healthmd.health_data",
             "public_schema_version":10,"core_api_version":4,"semantic_input_version":2,
             "canonical_model_version":2,"render_input_version":2,"artifact_plan_version":2,
             "registry_version":2,"registry_sha256":"c1854454bee84b6d74cee1d7457d3fde1f484ef74963a656adba503c91cb9073",
             "semantic_profile_revision":1,"render_profile_revision":2,
             "core_source_revision":"synthetic-planner-contract","calendar_time_zone":"America/New_York"}
            """.utf8))
        let snapshot = ExportSettingsSnapshot.from(settings, healthSubfolder: "Health",
            appleExportEnginePin: pin, calendarTimeZoneIdentifier: zone.identifier)
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(injectedOverride: "legacy", userDefaults: nil, environment: [:]),
            identitySource: AppleExportOperationIdentitySource(makeRequestID: { "wake-request" },
                makeSessionID: { "wake-session" }, now: { Date(timeIntervalSince1970: 123) }))

        let resolution = try await planner.plan(healthData: day, settingsSnapshot: snapshot,
            surface: .localVaultWithoutSideEffects)

        guard case .planned(let operation) = resolution else {
            return XCTFail("An explicit successor cannot resolve to a historical exporter")
        }
        XCTAssertEqual(operation.authority, .rust)
        XCTAssertEqual(operation.pin, pin)
        XCTAssertEqual(operation.selectedPlan.profile, .appleHealthDataV10)
        XCTAssertEqual(operation.selectedPlan.artifactPlanVersion, 2)
        XCTAssertEqual(operation.artifacts.count, 1)
        let artifact = try XCTUnwrap(operation.artifacts.first?.artifact)
        XCTAssertEqual(artifact.relativePath, "Health/2026-11-01.json")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: artifact.inlineData) as? [String: Any])
        XCTAssertEqual(root["schema_version"] as? Int, 10)
        XCTAssertEqual(root["schema_profile"] as? String, "apple-v10")
        XCTAssertEqual(root["date"] as? String, "2026-11-01")
        XCTAssertEqual(root["time_context"] as? [String: String], [
            "calendar_timezone": "America/New_York", "timestamp_timezone": "UTC",
            "sleep_day_attribution": "morning_ends", "sleep_owner_day_rule": "session_end_date",
            "sleep_interval_clipping": "none",
        ])
        let renderedSleep = try XCTUnwrap(root["sleep"] as? [String: Any])
        XCTAssertEqual(renderedSleep["totalDuration"] as? Double, 55_800.5)
        XCTAssertEqual(renderedSleep["coreSleep"] as? Double, 3_600.5)
        XCTAssertEqual(renderedSleep["bedtimeISO"] as? String, "2026-11-01T02:00:00.250000000Z")
        XCTAssertEqual(renderedSleep["wakeTimeISO"] as? String, "2026-11-01T17:30:00.750000000Z")
        XCTAssertNil(renderedSleep["lightSleep"])
        let activity = try XCTUnwrap(root["activity"] as? [String: Any])
        XCTAssertEqual(activity["steps"] as? Int, 1_234)
        XCTAssertEqual(activity["activeCalories"] as? Double, 123.875)
        XCTAssertThrowsError(try context.requireShippedProfile(), "Planner qualification alone does not enable fresh capture")
    }
}
