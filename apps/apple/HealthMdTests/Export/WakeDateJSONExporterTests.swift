import HealthKit
import XCTest
@testable import HealthMd

/// Native HealthStore-facade capture → real streamed JSON. Only HealthKit IPC
/// is substituted; this is not real-provider, production-routing or device QA.
final class WakeDateJSONExporterTests: XCTestCase {
    private static let customization = FormatCustomization()
    private static let imperialCustomization: FormatCustomization = {
        let customization = FormatCustomization()
        customization.unitPreference = .imperial
        customization.dateFormat = .usShort
        customization.timeFormat = .hour12
        return customization
    }()

    func testEmptyDayKeepsOneAuthorityAndNativeGrammarAcrossBufferedAndStreamingEntrypoints() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let date = try XCTUnwrap(ExportDateFormatting.utcISO8601Formatter().date(from: "2026-11-01T04:00:00Z"))
        var day = HealthData(date: date,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.body.weight = 72.125
        let expected = try day.toJSONDataThrowing(customization: Self.imperialCustomization, captureContext: context)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: expected) as? [String: Any])
        XCTAssertEqual(root["schema_version"] as? Int, 11)
        XCTAssertEqual(root["schema_profile"] as? String, "apple-v11")
        XCTAssertEqual(root["date"] as? String, "2026-11-01")
        XCTAssertEqual(root["type"] as? String, "health-data")
        XCTAssertEqual(root["unit_system"] as? String, "metric")
        XCTAssertEqual((root["body"] as? [String: Any])?["weight"] as? Double, 72.125)
        XCTAssertEqual((root["units"] as? [String: String])?["weight_kg"], "kg")
        XCTAssertNil(root["sleep"])
        XCTAssertEqual((root["time_context"] as? [String: String])?["sleep_day_attribution"], "morning_ends")
        XCTAssertEqual((root["time_context"] as? [String: String])?["sleep_owner_day_rule"], "session_end_date")
        XCTAssertEqual((root["time_context"] as? [String: String])?["sleep_interval_clipping"], "none")
        let snapshot = day.exportSnapshot(customization: Self.imperialCustomization)
        XCTAssertEqual(try day.bufferedJSONDataForParityTesting(snapshot: snapshot,
            config: Self.imperialCustomization, captureContext: context), expected)
        XCTAssertEqual(try day.toJSONThrowing(customization: Self.imperialCustomization,
            captureContext: context).data(using: .utf8), expected)
        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }
        XCTAssertEqual(try day.writeJSONThrowing(to: stream, customization: Self.imperialCustomization,
            captureContext: context), expected.count)
        XCTAssertEqual(stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data, expected)
    }

    func testMissingDraftConflictingClockAndHistoricalAttributionNeverBecomeSuccessorDocuments() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let morning = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let date = try XCTUnwrap(ExportDateFormatting.utcISO8601Formatter().date(from: "2026-11-01T04:00:00Z"))
        let draft = try JSONDecoder().decode(AppleSleepCaptureContext.self, from: Data("""
            {"calendarTimeZoneIdentifier":"America/New_York","sleepDayAttribution":"morning_ends"}
            """.utf8))
        XCTAssertNil(draft.exportProfileID)
        let day = HealthData(date: date,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        let invalidContexts: [AppleSleepCaptureContext?] = [nil, draft,
            AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins),
            AppleSleepCaptureContext(timeZone: TimeZone(identifier: "Europe/Berlin")!, sleepDayAttribution: .morningEnds)]
        for context in invalidContexts {
            let sink = MemoryExportByteSink(mediaType: "application/json")
            XCTAssertThrowsError(try day.writeJSONThrowing(to: sink,
                customization: Self.customization, captureContext: context)) {
                XCTAssertEqual($0 as? AppleWakeDateJSONError, .incompatibleCaptureAuthority)
                XCTAssertEqual($0.localizedDescription, "wake-date JSON capture authority is incompatible")
            }
            XCTAssertTrue(sink.data.isEmpty)
        }
        let historical = HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone))
        XCTAssertThrowsError(try historical.toJSONDataThrowing(customization: Self.customization, captureContext: morning)) {
            XCTAssertEqual($0 as? AppleWakeDateJSONError, .incompatibleCaptureAuthority)
        }
        XCTAssertThrowsError(try morning.requireShippedProfile(), "Native preparation does not open production acceptance")
    }

    func testExplicitNightAuthorityRetainsExactHistoricalBytesAndDoesNotAddSuccessorMetadata() throws {
        let day = ExportFixtures.fullDay
        let context = AppleSleepCaptureContext(timeZone: day.timeContext.calendarTimeZone, sleepDayAttribution: .nightBegins)
        let expected = try day.toJSONDataThrowing(customization: Self.customization)
        XCTAssertEqual(try day.toJSONDataThrowing(customization: Self.customization, captureContext: context), expected)
        let sink = MemoryExportByteSink(mediaType: "application/json")
        try day.writeJSONThrowing(to: sink, customization: Self.customization, captureContext: context)
        _ = try sink.finish()
        XCTAssertEqual(sink.data, expected)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: expected) as? [String: Any])
        XCTAssertEqual(root["schema_version"] as? Int, 8)
        XCTAssertNil(root["schema_profile"])
        XCTAssertNil((root["time_context"] as? [String: String])?["sleep_day_attribution"])
        XCTAssertEqual(HealthMdExportSchema.version, 8)
    }

    func testMidnightWakeBelongsOnlyToNewCapturedCalendarDate() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-11-02T04:00:00Z"))
        let end = try XCTUnwrap(formatter.date(from: "2026-11-02T05:00:00Z"))
        let sleep = SleepData(totalDuration: 3_600, coreSleep: 3_600, sessionStart: start, sessionEnd: end)
        let timeContext = ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let previous = HealthData(date: start, timeContext: timeContext, sleep: sleep)
        let sink = MemoryExportByteSink(mediaType: "application/json")
        XCTAssertThrowsError(try previous.writeJSONThrowing(to: sink, customization: Self.customization, captureContext: context)) {
            XCTAssertEqual($0 as? AppleWakeDateJSONError, .incompatibleSessionOwner)
        }
        XCTAssertTrue(sink.data.isEmpty)
        let owned = HealthData(date: end, timeContext: timeContext, sleep: sleep)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: owned.toJSONDataThrowing(
            customization: Self.customization, captureContext: context)) as? [String: Any])
        XCTAssertEqual(root["date"] as? String, "2026-11-02")
        XCTAssertEqual((root["sleep"] as? [String: Any])?["wakeTimeISO"] as? String, "2026-11-02T05:00:00.000000000Z")
    }

    func testSuccessorStreamingRetainsTheIndependentLosslessArchiveWithoutReassigningRawRecords() throws {
        let historical = ExportFixtures.losslessDay
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        var day = HealthData(date: historical.date,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.healthKitRecordArchive = historical.healthKitRecordArchive
        day.healthKitRecordCaptureStatus = historical.healthKitRecordCaptureStatus
        let expected = try historical.toJSONDataThrowing(customization: Self.customization)
        let actual = try day.toJSONDataThrowing(customization: Self.customization, captureContext: context)
        let oldRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: expected) as? [String: Any])
        let newRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: actual) as? [String: Any])
        let oldArchive = try XCTUnwrap(oldRoot["healthkit_record_archive"] as? NSDictionary)
        let newArchive = try XCTUnwrap(newRoot["healthkit_record_archive"] as? NSDictionary)
        XCTAssertTrue(oldArchive.isEqual(newArchive))
        XCTAssertEqual(newArchive["schema"] as? String, "healthmd.healthkit_records")
        XCTAssertEqual(newArchive["schema_version"] as? Int, 1)
        let snapshot = day.exportSnapshot(customization: Self.customization)
        XCTAssertEqual(try day.bufferedJSONDataForParityTesting(snapshot: snapshot,
            config: Self.customization, captureContext: context), actual)
        XCTAssertEqual(newRoot["raw_capture_status"] as? String, oldRoot["raw_capture_status"] as? String)
    }

    func testSummaryWithoutSessionAuthorityFailsBeforeAnyStreamBytesAreWritten() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        var day = HealthData(date: Date(timeIntervalSince1970: 1_793_505_600),
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.sleep = SleepData(totalDuration: 3_600, coreSleep: 3_600)
        let sink = MemoryExportByteSink(mediaType: "application/json")
        XCTAssertThrowsError(try day.writeJSONThrowing(to: sink,
            customization: Self.customization, captureContext: context)) {
            XCTAssertEqual($0 as? AppleWakeDateJSONError, .incompatibleSessionOwner)
        }
        XCTAssertTrue(sink.data.isEmpty, "Unowned native summaries cannot produce a partial successor artifact")
    }

    func testSelectedSleepTotalsKeepSourceOwnershipWithoutExportingDisabledClocks() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let date = try XCTUnwrap(formatter.date(from: "2026-11-01T04:00:00Z"))
        var day = HealthData(date: date,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.sleep = SleepData(totalDuration: 29_700, coreSleep: 15_300,
            sessionStart: try XCTUnwrap(formatter.date(from: "2026-11-01T02:00:00Z")),
            sessionEnd: try XCTUnwrap(formatter.date(from: "2026-11-01T10:15:00Z")))
        var selection = MetricSelectionState()
        selection.enabledMetrics = ["sleep_total", "sleep_core"]
        let filtered = day.filtered(by: selection).filtered(by: selection)
        XCTAssertNil(filtered.sleep.sessionStart)
        XCTAssertNil(filtered.sleep.sessionEnd)
        let bytes = try filtered.toJSONDataThrowing(customization: Self.customization, captureContext: context)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let sleep = try XCTUnwrap(root["sleep"] as? [String: Any])
        XCTAssertEqual(sleep["totalDuration"] as? Double, 29_700)
        XCTAssertEqual(sleep["coreSleep"] as? Double, 15_300)
        for key in ["bedtime", "bedtimeISO", "wakeTime", "wakeTimeISO", "sourceSessionBounds"] {
            XCTAssertNil(sleep[key], "Disabled clocks and internal bounds must not become public fields")
        }
        let encoded = try JSONEncoder().encode(filtered.sleep)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("sourceSessionBounds"))
        var wrongDay = day
        wrongDay.sleep.sessionEnd = formatter.date(from: "2026-11-02T10:15:00Z")
        var stepsOnly = MetricSelectionState()
        stepsOnly.enabledMetrics = ["steps"]
        wrongDay.activity.steps = 0
        let activity = wrongDay.filtered(by: stepsOnly)
        XCTAssertNil(activity.sleep.sourceSessionBounds, "Unselected sleep must not block an unrelated export")
        XCTAssertNoThrow(try activity.toJSONDataThrowing(customization: Self.customization, captureContext: context))
        var missingBounds = day
        missingBounds.sleep.sessionEnd = nil
        var contradictory = filtered
        contradictory.sleep.sessionEnd = formatter.date(from: "2026-11-01T11:15:00Z")
        for invalid in [wrongDay.filtered(by: selection), missingBounds.filtered(by: selection), contradictory] {
            let sink = MemoryExportByteSink(mediaType: "application/json")
            XCTAssertThrowsError(try invalid.writeJSONThrowing(to: sink,
                customization: Self.customization, captureContext: context)) {
                XCTAssertEqual($0 as? AppleWakeDateJSONError, .incompatibleSessionOwner)
            }
            XCTAssertTrue(sink.data.isEmpty)
        }
    }

    @MainActor
    func testWholeNoonSpanningSessionReachesSuccessorJSONWithNativeCoreAndOriginalFoldClocks() async throws {
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
                metadata: ["HKTimeZone": "America/New_York", "synthetic": "fold-core"]),
        ]
        let suite = "WakeDateJSONExporterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let sleep = try await manager.fetchSleepProjection(for: ownerDate, attribution: .morningEnds,
            timeZone: zone, includeDetailedTimeSeries: true)
        var day = HealthData(date: ownerDate,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds), sleep: sleep)
        day.activity.steps = 1_234
        day.activity.activeCalories = 123.875

        let bytes = try day.toJSONDataThrowing(customization: Self.customization, captureContext: context)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(root["schema"] as? String, "healthmd.health_data")
        XCTAssertEqual(root["schema_version"] as? Int, 11)
        XCTAssertEqual(root["schema_profile"] as? String, "apple-v11")
        XCTAssertEqual(root["date"] as? String, "2026-11-01")
        XCTAssertEqual(root["type"] as? String, "health-data")
        XCTAssertEqual(root["time_context"] as? [String: String], [
            "calendar_timezone": "America/New_York", "timestamp_timezone": "UTC",
            "sleep_day_attribution": "morning_ends", "sleep_owner_day_rule": "session_end_date",
            "sleep_interval_clipping": "none",
        ])
        let renderedSleep = try XCTUnwrap(root["sleep"] as? [String: Any])
        XCTAssertEqual(renderedSleep["totalDuration"] as? Double, 55_800.5)
        XCTAssertEqual(renderedSleep["inBedTime"] as? Double, 55_800.5)
        XCTAssertEqual(renderedSleep["coreSleep"] as? Double, 3_600.5)
        XCTAssertNil(renderedSleep["lightSleep"])
        XCTAssertEqual(renderedSleep["bedtimeISO"] as? String, "2026-11-01T02:00:00.250000000Z")
        XCTAssertEqual(renderedSleep["wakeTimeISO"] as? String, "2026-11-01T17:30:00.750000000Z")
        let stages = try XCTUnwrap(renderedSleep["sleepStages"] as? [[String: Any]])
        let core = try XCTUnwrap(stages.first { $0["stage"] as? String == "core" })
        XCTAssertEqual(core["startDate"] as? String, "2026-11-01T05:30:00.250000000Z")
        XCTAssertEqual(core["endDate"] as? String, "2026-11-01T06:30:00.750000000Z")
        XCTAssertEqual(core["durationSeconds"] as? Double, 3_600.5)
        XCTAssertEqual(core["metadata"] as? [String: String],
            ["HKTimeZone": "America/New_York", "synthetic": "fold-core"])
        let activity = try XCTUnwrap(root["activity"] as? [String: Any])
        XCTAssertEqual(activity["steps"] as? Int, 1_234)
        XCTAssertEqual(activity["activeCalories"] as? Double, 123.875)
        let units = try XCTUnwrap(root["units"] as? [String: String])
        XCTAssertEqual(units["active_calories"], "kcal")
        XCTAssertEqual(units["sleep_core_hours"], "hours")
    }
}
