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

    func testCapturedWakeDateSleepDetailsReachConcretePlannerAcrossEveryFormat() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let owner = try XCTUnwrap(formatter.date(from: "2026-11-01T04:00:00Z"))
        let start = try XCTUnwrap(formatter.date(from: "2026-11-01T02:00:00Z")).addingTimeInterval(0.25)
        let coreStart = try XCTUnwrap(formatter.date(from: "2026-11-01T05:30:00Z")).addingTimeInterval(0.25)
        let coreEnd = try XCTUnwrap(formatter.date(from: "2026-11-01T06:30:00Z")).addingTimeInterval(0.75)
        let end = try XCTUnwrap(formatter.date(from: "2026-11-01T17:30:00Z")).addingTimeInterval(0.75)
        let store = FakeHealthStore()
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.inBed.rawValue, startDate: start, endDate: end),
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                startDate: coreStart, endDate: coreEnd, metadata: ["synthetic": "core, \"quoted\""]),
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                startDate: coreEnd, endDate: end, metadata: ["synthetic": "unspecified-source"]),
        ]
        let suite = "AppleConcreteSleepDetails.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let sleep = try await manager.fetchSleepProjection(for: owner, attribution: .morningEnds,
            timeZone: zone, includeDetailedTimeSeries: true)
        let day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds), sleep: sleep)
        XCTAssertEqual(day.sleep.stages.count, 3)
        for selection: Set<String> in [["sleep_total", "sleep_core", "sleep_in_bed", "sleep_bedtime", "sleep_wake"], ["sleep_total"]] {
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: selection)
            snapshot.detailPolicy = .detailedTimeSeries
            let planner = AppleLooseDailyExportPlanner()
            let resolution = try await planner.plan(healthData: day, settingsSnapshot: snapshot,
                surface: .localVaultWithoutSideEffects)
            guard case .planned(let operation) = resolution else { return XCTFail("Captured sleep details must reach the concrete successor planner") }
            XCTAssertEqual(operation.artifacts.count, 4)
            let csv = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .csv }).artifact.inlineData, as: UTF8.self)
            XCTAssertTrue(csv.contains("2026-11-01,Sleep Detail,Sleep Stage,"))
            XCTAssertTrue(csv.contains("unspecified-source"))
            XCTAssertTrue(csv.contains("2026-11-01T17:30:00.750000000Z"))
            let markdown = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .markdown }).artifact.inlineData, as: UTF8.self)
            XCTAssertTrue(markdown.contains("Sleep Stage Details"))
            XCTAssertTrue(markdown.contains("| unspecified |"))
            let bases = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .obsidianBases }).artifact.inlineData, as: UTF8.self)
            XCTAssertTrue(bases.contains("sleep_stage_details:"))
            XCTAssertEqual(csv.contains("core,"), selection.contains("sleep_core"))
            XCTAssertFalse(bases.contains("sleep_session_details:"))
            let settings = snapshot.makeAdvancedExportSettings(userDefaults: defaults)
            Self.retainedSettings.append(settings)
            let prepared = day.preparedExport(settings: settings)
            XCTAssertEqual(prepared.filteredData.sleep.stages.count, selection.contains("sleep_core") ? 3 : 1)
            let json = try XCTUnwrap(operation.artifacts.first { $0.format == .json }).artifact.inlineData
            let expected = try prepared.filteredData.toJSONDataThrowing(customization: settings.formatCustomization, captureContext: context)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: json) as? NSDictionary,
                try JSONSerialization.jsonObject(with: expected) as? NSDictionary)
            if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                for artifact in operation.artifacts {
                    let output = URL(fileURLWithPath: directory).appendingPathComponent(selection.contains("sleep_core") ? "apple-v11-concrete-stages" : "apple-v11-concrete-total")
                        .appendingPathComponent(artifact.artifact.relativePath)
                    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try artifact.artifact.inlineData.write(to: output)
                }
            }
        }
    }

    func testWakeDateDetailsRejectArchivesRemoteSurfacesAndNonSleepArrays() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
            selectionIDs: ["sleep_total", "heart_rate_avg"])
        snapshot.detailPolicy = .detailedTimeSeries
        XCTAssertTrue(AppleLooseDailyExportPlanner.supports(settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects))
        XCTAssertFalse(AppleLooseDailyExportPlanner.supports(settingsSnapshot: snapshot, surface: .directGeneratedFilesWithoutSideEffects))
        XCTAssertFalse(AppleLooseDailyExportPlanner.supports(settingsSnapshot: snapshot, surface: .connectedReceivedFilesWithoutSideEffects))
        for policy: AppleExportDetailPolicy in [.archiveOnly, .lossless] {
            var rejected = snapshot
            rejected.detailPolicy = policy
            XCTAssertFalse(AppleLooseDailyExportPlanner.supports(settingsSnapshot: rejected, surface: .localVaultWithoutSideEffects))
        }
        var noContext = snapshot
        noContext.sleepCaptureContext = nil
        XCTAssertFalse(AppleLooseDailyExportPlanner.supports(settingsSnapshot: noContext, surface: .localVaultWithoutSideEffects))
        var noPin = snapshot
        noPin.appleExportEnginePin = nil
        XCTAssertFalse(AppleLooseDailyExportPlanner.supports(settingsSnapshot: noPin, surface: .localVaultWithoutSideEffects))
        let owner = ExportFixtures.referenceDate
        let day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            sleep: SleepData(totalDuration: 3600, sessionStart: owner.addingTimeInterval(3600),
                sessionEnd: owner.addingTimeInterval(7200)), heart: ExportFixtures.fullDayGranular.heart)
        XCTAssertTrue(day.sleep.stages.isEmpty)
        do {
            _ = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot,
                surface: .localVaultWithoutSideEffects)
            XCTFail("Non-sleep detail arrays must reject even without sleep stages")
        } catch {
            XCTAssertEqual(error as? AppleLooseDailyExportPlannerError, .rustPlanningFailed)
        }
    }

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

    func testRequestedHumanUnitsKeepAllFourMachineArtifactsCanonical() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let owner = try XCTUnwrap(ExportDateFormatting.utcISO8601Formatter().date(from: "2026-11-01T04:00:00Z"))
        var day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.body.weight = 72.125
        day.body.height = 1.75125
        day.activity.walkingRunningDistance = 1_234.125
        day.vitals.bodyTemperatureAvg = 36.8125
        day.nutrition.water = 1.375
        var jsonDocuments: [Data] = []
        for preference in [UnitPreference.metric, .imperial] {
            let snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
                selectionIDs: ["weight", "height", "distance_walking_running", "body_temperature", "dietary_water"],
                unitPreference: preference)
            let resolution = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot,
                surface: .localVaultWithoutSideEffects)
            guard case .planned(let operation) = resolution else {
                return XCTFail("Both unit preferences must reach successor native preparation")
            }
            XCTAssertEqual(operation.artifacts.count, 4)
            for artifact in operation.artifacts where artifact.format == .markdown || artifact.format == .obsidianBases {
                let text = String(decoding: artifact.artifact.inlineData, as: UTF8.self)
                XCTAssertTrue(text.contains("weight_kg: 72.125\n"))
                XCTAssertTrue(text.contains("height_m: 1.75125\n"))
                XCTAssertTrue(text.contains("water_l: 1.375\n"))
            }
            let markdown = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .markdown }).artifact.inlineData, as: UTF8.self)
            for expected in preference == .imperial
                ? ["159.0 lbs", "5'8\"", "0.77 mi", "98.3°F", "46.5 oz"]
                : ["72.1 kg", "175.1 cm", "1.23 km", "36.8°C", "1.38 L"] {
                XCTAssertTrue(markdown.contains(expected), expected)
            }
            let csv = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .csv }).artifact.inlineData, as: UTF8.self)
            XCTAssertTrue(csv.contains(",Weight,72.125,kg,"))
            XCTAssertTrue(csv.contains(",Height,1.75125,m,"))
            XCTAssertTrue(csv.contains(",unit_system,metric,"))
            let bytes = try XCTUnwrap(operation.artifacts.first { $0.format == .json }).artifact.inlineData
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual((root["body"] as? [String: Any])?["weight"] as? Double, 72.125)
            XCTAssertEqual((root["body"] as? [String: Any])?["height"] as? Double, 1.75125)
            XCTAssertEqual(root["unit_system"] as? String, "metric")
            jsonDocuments.append(bytes)
        }
        XCTAssertEqual(jsonDocuments[0], jsonDocuments[1])
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
        XCTAssertEqual(operation.selectedPlan.profile, .appleHealthDataV11)
        if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
            for planned in operation.artifacts {
                let output = URL(fileURLWithPath: directory).appendingPathComponent("apple-v11-dst")
                    .appendingPathComponent(planned.artifact.relativePath)
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try planned.artifact.inlineData.write(to: output)
            }
        }
        for planned in operation.artifacts {
            let text = try XCTUnwrap(String(data: planned.artifact.inlineData, encoding: .utf8))
            switch planned.format {
            case .json:
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: planned.artifact.inlineData) as? [String: Any])
                XCTAssertEqual(root["schema_version"] as? Int, 11)
                XCTAssertEqual((root["sleep"] as? [String: Any])?["totalDuration"] as? Double, 55_800.5)
                XCTAssertEqual((root["activity"] as? [String: Any])?["activeCalories"] as? Double, 123.875)
            case .markdown, .obsidianBases:
                XCTAssertTrue(text.contains("schema_version: 11\n"))
                XCTAssertTrue(text.contains("schema_profile: apple-v11\n"))
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
                XCTAssertTrue(text.contains("2026-11-01,Metadata,schema_version,11,,\n"))
                XCTAssertTrue(text.contains("2026-11-01,Metadata,schema_profile,apple-v11,,\n"))
                XCTAssertTrue(text.contains("2026-11-01,Metadata,time_context.sleep_owner_day_rule,session_end_date,,\n"))
                let row = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("2026-11-01,Sleep,Total Sleep,") })
                XCTAssertEqual(Double(row.components(separatedBy: ",")[3]), 15.50013888888889)
                XCTAssertTrue(text.contains(",123.875,kcal,\n"))
                XCTAssertTrue(text.contains(",Sleep,Bedtime,"))
                XCTAssertTrue(text.contains(",Sleep,Wake Time,"))
                XCTAssertTrue(text.contains(",time,2026-11-01T02:00:00.250000000Z\n"))
                XCTAssertTrue(text.contains(",time,2026-11-01T17:30:00.750000000Z\n"))
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
            XCTAssertEqual(root["schema_profile"] as? String, "apple-v11")
            XCTAssertEqual(root["schema_version"] as? Int, 11)
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
            XCTAssertTrue(text.contains("Profile: `apple-v11`; calendar timezone: `America/New_York`"))
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

    func testWakeDateRangeSummaryPreservesFailedBoundsAndSuccessfulEmptyDay() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let first = try XCTUnwrap(formatter.date(from: "2026-11-01T04:00:00Z"))
        let second = try XCTUnwrap(formatter.date(from: "2026-11-02T05:00:00Z"))
        var populated = HealthData(date: first, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        populated.sleep = SleepData(totalDuration: 29_700, coreSleep: 15_300,
            sessionStart: try XCTUnwrap(formatter.date(from: "2026-11-01T02:00:00Z")),
            sessionEnd: try XCTUnwrap(formatter.date(from: "2026-11-01T10:15:00Z")))
        let empty = HealthData(date: second, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        let requested = try HealthRollupRangeRequest(
            startDate: XCTUnwrap(formatter.date(from: "2026-10-31T04:00:00Z")),
            endDate: XCTUnwrap(formatter.date(from: "2026-11-03T05:00:00Z")),
            calendarTimeZoneIdentifier: zone.identifier)
        let snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
            selectionIDs: ["sleep_total", "sleep_core"], rangeSummary: true)
        let resolution = try await AppleLooseDailyExportPlanner().planRange(healthData: [populated, empty],
            dailyOutputOwnerDates: ["2026-11-01"], requestedRange: requested,
            settingsSnapshot: snapshot, surface: .localVaultRangeWithoutSideEffects,
            operationIdentity: AppleExportOperationIdentity(requestID: "sleep-range-request", sessionID: "sleep-range-session",
                capturedAt: try XCTUnwrap(formatter.date(from: "2026-11-04T12:00:00Z")),
                calendarTimeZoneIdentifier: zone.identifier))
        guard case .planned(let operation) = resolution else { return XCTFail("The successor range must not fall back to a historical writer") }
        let summaries = operation.artifacts.filter { $0.kind == .rollup }
        XCTAssertEqual(summaries.count, 4)
        for planned in summaries {
            let bytes = planned.artifact.inlineData
            let text = String(decoding: bytes, as: UTF8.self)
            XCTAssertTrue(text.contains("morning_ends"))
            XCTAssertTrue(text.contains("apple-v11"))
            if planned.format == .json {
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                XCTAssertEqual(root["schema_version"] as? Int, 11)
                XCTAssertEqual(root["source_schema_version"] as? Int, 11)
                XCTAssertEqual(root["rollup_rules_version"] as? Int, 11)
                XCTAssertEqual(root["period_id"] as? String, "2026-10-31_to_2026-11-03")
                XCTAssertEqual(root["days_expected"] as? Int, 4)
                XCTAssertEqual(root["days_counted"] as? Int, 2)
                XCTAssertEqual(root["source_dates"] as? [String], ["2026-11-01", "2026-11-02"])
                XCTAssertEqual(root["coverage_percent"] as? Double, 50)
            }
            if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_RANGE_FIXTURE_DIR"], !directory.isEmpty {
                let output = URL(fileURLWithPath: directory).appendingPathComponent("native-apple-v11")
                    .appendingPathComponent(planned.artifact.relativePath)
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: output)
            }
        }
    }

    private func acceptedSnapshot(
        context: AppleSleepCaptureContext, formats: Set<ExportFormat>, selectionIDs: Set<String>? = nil,
        rangeSummary: Bool = false, unitPreference: UnitPreference = .metric
    ) throws -> ExportSettingsSnapshot {
        let suite = "AppleWakeDatePlannerFixture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = formats
        settings.formatCustomization.unitPreference = unitPreference
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.includeGranularData = false
        settings.generateRangeSummary = rangeSummary
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        settings.exportTimeZoneOverride = context.timeZone
        settings.executionSleepCaptureContext = context
        settings.executionSleepCaptureContextIsFrozen = true
        settings.metricSelection.enabledMetrics = selectionIDs ?? [
            "sleep_total", "sleep_core", "sleep_in_bed", "sleep_bedtime", "sleep_wake", "steps", "active_energy",
        ]
        let encoded: [String: Any] = [
            "engine": "rust", "profile": "apple_health_data_v11", "public_schema": "healthmd.health_data",
            "public_schema_version": 11, "core_api_version": 4, "semantic_input_version": 2,
            "canonical_model_version": 2, "render_input_version": 2, "artifact_plan_version": 2,
            "registry_version": 2, "registry_sha256": "709df0ae9f583e82627bc5439c4385905a5d85000e4322a0384cfe96b35a8f78",
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
            {"engine":"rust","profile":"apple_health_data_v11","public_schema":"healthmd.health_data",
             "public_schema_version":11,"core_api_version":4,"semantic_input_version":2,
             "canonical_model_version":2,"render_input_version":2,"artifact_plan_version":2,
             "registry_version":2,"registry_sha256":"709df0ae9f583e82627bc5439c4385905a5d85000e4322a0384cfe96b35a8f78",
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
        XCTAssertEqual(operation.selectedPlan.profile, .appleHealthDataV11)
        XCTAssertEqual(operation.selectedPlan.artifactPlanVersion, 2)
        XCTAssertEqual(operation.artifacts.count, 1)
        let artifact = try XCTUnwrap(operation.artifacts.first?.artifact)
        XCTAssertEqual(artifact.relativePath, "Health/2026-11-01.json")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: artifact.inlineData) as? [String: Any])
        XCTAssertEqual(root["schema_version"] as? Int, 11)
        XCTAssertEqual(root["schema_profile"] as? String, "apple-v11")
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
