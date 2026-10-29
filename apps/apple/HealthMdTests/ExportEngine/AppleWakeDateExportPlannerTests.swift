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
    private static var retainedManagers: [VaultManager] = []

    func testNativeStagesRejectInvalidBoundsAndKeepZeroLengthSourceFactsWithoutSummaries() async throws {
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let date = ExportFixtures.referenceDate
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["sleep_core"])
        snapshot.detailPolicy = .detailedTimeSeries
        let parentStart = date.addingTimeInterval(-3600), parentEnd = date.addingTimeInterval(7200)
        for invalid in ["missing-parent", "wrong-owner", "reversed", "outside-parent"] {
            let start = invalid == "outside-parent" ? parentStart.addingTimeInterval(-1) : date
            let end = invalid == "reversed" ? date.addingTimeInterval(-1) : date.addingTimeInterval(60)
            let sleep = SleepData(sessionStart: invalid == "missing-parent" ? nil : parentStart,
                sessionEnd: invalid == "missing-parent" ? nil : invalid == "wrong-owner" ? date.addingTimeInterval(86400) : parentEnd,
                stages: [SleepStageSample(stage: "core", startDate: start, endDate: end)])
            let day = HealthData(date: date, timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds), sleep: sleep)
            do {
                _ = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
                XCTFail("Invalid captured stage must reject before delivery: \(invalid)")
            } catch {}
        }
        let day = HealthData(date: date, timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds),
            sleep: SleepData(sessionStart: parentStart, sessionEnd: parentEnd,
                stages: [SleepStageSample(stage: "core", startDate: date, endDate: date, metadata: ["synthetic": "zero-source"])]))
        guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else { return XCTFail("Valid zero-length native source must not create a summary") }
        let json = try XCTUnwrap(operation.artifacts.first { $0.format == .json })
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json.artifact.content.materializedData()) as? [String: Any])
        let sleep = try XCTUnwrap(root["sleep"] as? [String: Any])
        XCTAssertNil(sleep["totalDuration"])
        let stage = try XCTUnwrap((sleep["sleepStages"] as? [[String: Any]])?.first)
        XCTAssertEqual(stage["durationSeconds"] as? Double, 0)
        XCTAssertEqual((stage["metadata"] as? [String: String])?["synthetic"], "zero-source")
    }

    func testDenseCapturedSleepStagesKeepWholeDSTSessionAcrossAllFormats() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let clock = ExportDateFormatting.utcISO8601Formatter()
        let owner = try XCTUnwrap(clock.date(from: "2026-11-01T04:00:00Z"))
        let start = try XCTUnwrap(clock.date(from: "2026-10-31T23:30:00Z")).addingTimeInterval(0.125)
        let end = start.addingTimeInterval(75_000)
        let store = FakeHealthStore()
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            CategorySampleValue(value: HKCategoryValueSleepAnalysis.inBed.rawValue, startDate: start, endDate: end)
        ] + (0..<2_000).map { index in
            CategorySampleValue(value: index.isMultiple(of: 2) ? HKCategoryValueSleepAnalysis.asleepCore.rawValue : HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                startDate: start.addingTimeInterval(Double(index) * 37.5),
                endDate: start.addingTimeInterval(Double(index + 1) * 37.5), metadata: ["synthetic": "dense-stage-\(index) | ` <source> &"])
        }
        let suite = "DenseSleepPlanner.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let sleep = try await manager.fetchSleepProjection(for: owner, attribution: .morningEnds, timeZone: zone, includeDetailedTimeSeries: true)
        XCTAssertEqual(sleep.stages.count, 2_001)
        XCTAssertEqual(sleep.totalDuration, 75_000)
        var day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds), sleep: sleep)
        day.heart.heartRateSamples = [TimeSample(timestamp: owner.addingTimeInterval(3600), value: 72.125.nextUp)]
        let native = try XCTUnwrap(try JSONSerialization.jsonObject(with: day.toJSONDataThrowing(captureContext: context)) as? [String: Any])
        let expectedStages = try XCTUnwrap((native["sleep"] as? [String: Any])?["sleepStages"] as? NSArray)
        for metadata in [true, false] {
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
                selectionIDs: ["sleep_total", "sleep_core", "sleep_rem", "sleep_in_bed", "sleep_bedtime", "sleep_wake", "heart_rate_avg"])
            snapshot.detailPolicy = .detailedTimeSeries
            snapshot.includeMetadata = metadata
            guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
                settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else { return XCTFail("Dense whole-session stages must remain exportable") }
            for artifact in operation.artifacts {
                let data = try artifact.artifact.content.materializedData()
                let text = String(decoding: data, as: UTF8.self)
                XCTAssertEqual(artifact.artifact.sha256, NativeExportArtifact.sha256(of: data))
                switch artifact.format {
                case .json:
                    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                    let stageData = try XCTUnwrap((root["sleep"] as? [String: Any])?["sleepStages"] as? [[String: Any]])
                    XCTAssertEqual(stageData as NSArray, expectedStages)
                    XCTAssertEqual(stageData.count, 2_001)
                    XCTAssertTrue(stageData.contains { $0["startDate"] as? String == "2026-10-31T23:30:00.125000000Z" })
                    XCTAssertTrue(stageData.contains { $0["endDate"] as? String == "2026-11-01T20:20:00.125000000Z" })
                case .csv:
                    XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.contains(",Sleep Detail,Sleep Stage,") }.count, 2_001)
                case .markdown:
                    XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.hasPrefix("| 2026-") }.count, 2_002)
                    XCTAssertTrue(text.contains("\\u007c"))
                case .obsidianBases:
                    XCTAssertEqual(text.components(separatedBy: "\"stage\":").count - 1, 2_001)
                    XCTAssertTrue(text.contains("native_quantity_details:"))
                }
                if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                    let output = URL(fileURLWithPath: directory).appendingPathComponent("apple-v11-dense-sleep-\(metadata)").appendingPathComponent(artifact.artifact.relativePath)
                    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: output)
                }
            }
        }
    }

    func testLargeNativeQuantityMetadataStaysFileBackedWithBoundedPreview() async throws {
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let payload = String(repeating: "x", count: 9 * 1024 * 1024)
        var day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds))
        day.heart.heartRateSamples = [TimeSample(timestamp: day.date.addingTimeInterval(0.125),
            value: 72.125.nextUp, metadata: ["synthetic": payload])]
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["heart_rate_avg"])
        snapshot.detailPolicy = .detailedTimeSeries
        guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else { return XCTFail("Large native sample must stay complete") }
        for artifact in operation.artifacts {
            XCTAssertNotNil(artifact.artifact.fileArtifact)
            if artifact.format == .json {
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: artifact.artifact.content.materializedData()) as? [String: Any])
                let samples = try XCTUnwrap((root["heart"] as? [String: Any])?["heartRateSamples"] as? [[String: Any]])
                XCTAssertTrue((samples.first?["metadata"] as? [String: String])?["synthetic"] == payload)
            }
            let preview = try ExportArtifactTextPreview.make(from: artifact.artifact)
            XCTAssertEqual(preview.originalByteCount, Int(artifact.artifact.byteCount))
            if artifact.format != .markdown {
                XCTAssertGreaterThan(artifact.artifact.byteCount, UInt64(payload.utf8.count))
                XCTAssertLessThanOrEqual(preview.head.utf8.count + preview.tail.utf8.count, 64 * 1024)
                XCTAssertGreaterThan(preview.omittedByteCount, 0)
            }
        }
    }

    func testInvalidNativeQuantityRejectsPlanWithoutSilentlyDroppingTheSample() async throws {
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["blood_oxygen"])
        var detailed = snapshot
        detailed.detailPolicy = .detailedTimeSeries
        for value in [Double.nan, Double.infinity, -0.01, 1.01] {
            var day = HealthData(date: ExportFixtures.referenceDate,
                timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds))
            day.vitals.bloodOxygenSamples = [TimeSample(timestamp: day.date, value: value)]
            do {
                _ = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: detailed,
                    surface: .localVaultWithoutSideEffects)
                XCTFail("Invalid sample must reject the complete artifact plan")
            } catch {}
        }
    }

    func testDenseSelectedQuantitySamplesSurviveAllLocalFormatsWithoutSummaries() async throws {
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let date = ExportFixtures.referenceDate
        let samples = (0..<2_000).map { index in TimeSample(timestamp: date.addingTimeInterval(Double(index) + 0.125),
            value: 72.125.nextUp, metadata: ["synthetic": "dense-\(index)"]) }
        var day = HealthData(date: date, timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds))
        day.heart.heartRateSamples = samples
        for metadata in [true, false] {
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["heart_rate_avg"])
            snapshot.detailPolicy = .detailedTimeSeries
            snapshot.includeMetadata = metadata
            guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
                settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else { return XCTFail("Dense selected source must remain exportable") }
            XCTAssertEqual(operation.artifacts.count, 4)
            for artifact in operation.artifacts {
                let data = try artifact.artifact.content.materializedData()
                XCTAssertEqual(artifact.artifact.sha256, NativeExportArtifact.sha256(of: data))
                let text = String(decoding: data, as: UTF8.self)
                if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                    let output = URL(fileURLWithPath: directory).appendingPathComponent("apple-v11-dense-quantities-\(metadata)")
                        .appendingPathComponent(artifact.artifact.relativePath)
                    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: output)
                }
                switch artifact.format {
                case .json:
                    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                    let heart = try XCTUnwrap(root["heart"] as? [String: Any])
                    let values = try XCTUnwrap(heart["heartRateSamples"] as? [[String: Any]])
                    XCTAssertEqual(values.count, samples.count)
                    XCTAssertEqual((values.last?["value"] as? Double)?.bitPattern, 72.125.nextUp.bitPattern)
                    XCTAssertEqual((values.last?["metadata"] as? [String: String])?["synthetic"], "dense-1999")
                    XCTAssertNil(heart["averageHeartRate"])
                case .csv:
                    XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.contains(",Native Detail,Quantity Sample,") }.count, samples.count)
                    XCTAssertTrue(text.contains("dense-1999"))
                case .markdown:
                    XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.hasPrefix("| 2026-") }.count, samples.count)
                    XCTAssertTrue(text.contains("| \(72.125.nextUp) | bpm |"))
                case .obsidianBases:
                    XCTAssertTrue(text.contains("native_quantity_details:"))
                    XCTAssertEqual(text.components(separatedBy: "\"metric\":\"heart_rate\"").count - 1, samples.count)
                    XCTAssertTrue(text.contains("dense-1999"))
                }
            }
        }
    }

    func testWHOOPLabelsCannotIntroduceFrontmatterKeysOrBreakNativeJSONCells() async throws {
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let label = "run | ` <&\n---\nforged: true 🌙"
        var root = try XCTUnwrap(ExportFixtures.whoopDay.providers).foundationJSONObject()
        var whoop = try XCTUnwrap(root["whoop"] as? [String: Any])
        var workouts = try XCTUnwrap(whoop["workouts"] as? [[String: Any]])
        workouts[0]["sport_name"] = label
        whoop["workouts"] = workouts
        root["whoop"] = whoop
        let providers = try JSONDecoder().decode(HealthProviderSections.self, from: JSONSerialization.data(withJSONObject: root))
        let day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 1), providers: providers)
        var snapshot = try acceptedSnapshot(context: context, formats: [.markdown, .obsidianBases], selectionIDs: ["steps"])
        guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else { return XCTFail("Expected provider label projection") }
        for artifact in operation.artifacts {
            let text = String(decoding: try artifact.artifact.content.materializedData(), as: UTF8.self)
            let lines = text.components(separatedBy: "\n")
            let field = try XCTUnwrap(lines.first { $0.hasPrefix("whoop_workout_sport_name: ") })
            let decoded = try JSONSerialization.jsonObject(with: Data(field.dropFirst("whoop_workout_sport_name: ".count).utf8), options: .fragmentsAllowed) as? String
            XCTAssertEqual(decoded, label)
            XCTAssertFalse(lines.contains("forged: true 🌙"))
            let row = try XCTUnwrap(lines.first { $0.hasPrefix("| `{") && $0.contains("healthmd.provider.whoop_daily") })
            XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(row.dropFirst(3).dropLast(3).utf8)) as? NSDictionary, root as NSDictionary)
            XCTAssertEqual(lines.filter { $0.hasPrefix("  whoop_hrv_rmssd_ms:") }.count, 1)
        }
        snapshot.formatCustomization.frontmatterConfig.customFields["whoop_hrv_rmssd_ms"] = "999"
        do {
            _ = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot,
                surface: .localVaultWithoutSideEffects)
            XCTFail("Conflicting user keys must not shadow provider facts")
        } catch {}
    }

    func testLocalWHOOPNotRequestedAndSuccessfulEmptyRemainDistinct() async throws {
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        for status in [WHOOPCaptureStatus.notRequested, .complete] {
            let providers = HealthProviderSections(whoop: WHOOPDailyProviderSection(captureStatus: status,
                fetchedAt: status == .notRequested ? nil : "2026-03-15T18:00:00Z",
                resources: status == .notRequested ? [] : [WHOOPResourceResult(resource: .cycles, status: .success, recordCount: 0, error: nil)],
                cycles: [], recoveries: [], sleep: [], workouts: [], body: nil, warnings: []))
            let day = HealthData(date: ExportFixtures.referenceDate,
                timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds),
                activity: ActivityData(steps: 1), providers: providers)
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["steps"])
            snapshot.includeMetadata = false
            guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
                settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else { return XCTFail("Expected explicit provider capture state") }
            for artifact in operation.artifacts {
                let data = try artifact.artifact.content.materializedData()
                let text = String(decoding: data, as: UTF8.self)
                let root: [String: Any]
                if artifact.format == .json {
                    let document = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                    root = try XCTUnwrap(document["providers"] as? [String: Any])
                } else if artifact.format == .csv {
                    XCTAssertTrue(text.contains(",WHOOP Capture,Capture Status,\(status.rawValue),"))
                    continue
                } else {
                    let row = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("| `{") && $0.contains("healthmd.provider.whoop_daily") })
                    root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(row.dropFirst(3).dropLast(3).utf8)) as? [String: Any])
                }
                let whoop = try XCTUnwrap(root["whoop"] as? [String: Any])
                XCTAssertEqual(whoop["capture_status"] as? String, status.rawValue)
                XCTAssertEqual((whoop["resources"] as? [Any])?.count, status == .notRequested ? 0 : 1)
                if status == .notRequested { XCTAssertTrue(whoop["fetched_at"] is NSNull) }
            }
        }
    }

    func testTypedWHOOPFactsReachAllLocalMorningFormatsWithoutChangingAppleMetrics() async throws {
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 1), providers: ExportFixtures.whoopDay.providers)
        let expected = try XCTUnwrap(day.providers).foundationJSONObject() as NSDictionary
        for policy: AppleExportDetailPolicy in [.summary, .detailedTimeSeries, .archiveOnly, .lossless] {
            for metadata in [true, false] {
                var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["steps"])
                snapshot.detailPolicy = policy
                snapshot.includeMetadata = metadata
                guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
                    settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else {
                    return XCTFail("Typed provider facts must not force historical fallback")
                }
                XCTAssertEqual(operation.artifacts.count, 4)
                for planned in operation.artifacts {
                    let data = try planned.artifact.content.materializedData()
                    XCTAssertEqual(planned.artifact.sha256, NativeExportArtifact.sha256(of: data))
                    let text = String(decoding: data, as: UTF8.self)
                    if policy == .summary,
                       let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                        let output = URL(fileURLWithPath: directory).appendingPathComponent("apple-v11-whoop-\(metadata)")
                            .appendingPathComponent(planned.artifact.relativePath)
                        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: output)
                    }
                    switch planned.format {
                    case .json:
                        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                        XCTAssertEqual(root["providers"] as? NSDictionary, expected)
                        XCTAssertEqual((root["activity"] as? [String: Any])?["steps"] as? Int, 1)
                        XCTAssertNil((root["heart"] as? [String: Any])?["hrv"])
                    case .csv:
                        XCTAssertTrue(text.contains(",WHOOP Cycle,Cycle Record,"))
                        XCTAssertTrue(text.contains(",WHOOP Recovery,HRV (RMSSD),54.3,ms,"))
                    case .markdown, .obsidianBases:
                        let row = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("| `{") && $0.contains("healthmd.provider.whoop_daily") })
                        let object = try JSONSerialization.jsonObject(with: Data(row.dropFirst(3).dropLast(3).utf8)) as? NSDictionary
                        XCTAssertEqual(object, expected)
                        XCTAssertEqual(text.contains("whoop_hrv_rmssd_ms: 54.3"), metadata)
                    }
                }
            }
        }
    }

    func testNativeStateOfMindRecordsReachEverySuccessorFormatWithoutLosingSourceFacts() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let owner = ExportFixtures.referenceDate
        let instant = owner.addingTimeInterval(3600.125)
        let entry = StateOfMindEntry(id: UUID(uuidString: "622C563B-D30C-4C45-A02B-20E45894377A")!,
            timestamp: instant, endDate: instant.addingTimeInterval(0.5), kind: .momentaryEmotion,
            valence: -0.123456789, labels: ["Calm|alert", "quoted \"label\""], associations: ["Work <test>"],
            metadata: ["synthetic": "mind, source"])
        let day = HealthData(date: owner,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            mindfulness: MindfulnessData(stateOfMind: [entry]))
        for includeMetadata in [true, false] {
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
                selectionIDs: ["state_of_mind_entries"])
            snapshot.detailPolicy = .detailedTimeSeries
            snapshot.includeMetadata = includeMetadata
            let result = try await AppleLooseDailyExportPlanner().plan(healthData: day,
                settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
            guard case .planned(let operation) = result else { return XCTFail("State of Mind source records require successor planning") }
            XCTAssertEqual(operation.artifacts.count, 4)
            for artifact in operation.artifacts {
                let text = String(decoding: artifact.artifact.inlineData, as: UTF8.self)
                XCTAssertTrue(text.contains("-0.123456789"))
                XCTAssertTrue(text.contains("622C563B-D30C-4C45-A02B-20E45894377A"))
                XCTAssertTrue(text.contains("mind, source"))
                if artifact.format == .csv { XCTAssertTrue(text.contains(",Native Detail,Mindfulness Record,")) }
                if artifact.format == .markdown {
                    XCTAssertTrue(text.contains("State of Mind Details"))
                    let row = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("| `{") })
                    XCTAssertTrue(row.hasSuffix("}` |"))
                    let json = String(row.dropFirst(3).dropLast(3))
                    let record = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
                    let sample = try XCTUnwrap(record["sample"] as? [String: Any])
                    XCTAssertEqual(sample["labels"] as? [String], entry.labels)
                    XCTAssertEqual(sample["metadata"] as? [String: String], entry.metadata)
                }
                if artifact.format == .obsidianBases { XCTAssertTrue(text.contains("native_mindfulness_details:")) }
                if artifact.format == .json {
                    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: artifact.artifact.inlineData) as? [String: Any])
                    let mood = try XCTUnwrap(root["mindfulness"] as? [String: Any])
                    let source = try XCTUnwrap((mood["stateOfMindEntries"] as? [[String: Any]])?.first)
                    XCTAssertEqual(source["timestamp"] as? String, CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: instant))
                    XCTAssertEqual(source["valence"] as? Double, entry.valence)
                    XCTAssertEqual(source["labels"] as? [String], entry.labels)
                    XCTAssertNil(mood["averageValence"])
                }
                if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                    let output = URL(fileURLWithPath: directory).appendingPathComponent("apple-v11-mindfulness-\(includeMetadata)")
                        .appendingPathComponent(artifact.artifact.relativePath)
                    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try artifact.artifact.inlineData.write(to: output)
                }
            }
        }
    }

    func testUnselectedOrInvalidStateOfMindRecordsNeverEnterSuccessorArtifacts() async throws {
        let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)
        let instant = ExportFixtures.referenceDate.addingTimeInterval(0.1255)
        var day = HealthData(date: instant, timeContext: ExportTimeContext(timeZone: .gmt, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 1), mindfulness: MindfulnessData(stateOfMind: [
                StateOfMindEntry(timestamp: instant, kind: .dailyMood, valence: 0.5,
                    labels: ["disabled-source-marker"], associations: [])]))
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["steps"])
        snapshot.detailPolicy = .detailedTimeSeries
        guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else { return XCTFail("Disabled source records must not block selected steps") }
        for artifact in operation.artifacts {
            XCTAssertFalse(String(decoding: artifact.artifact.inlineData, as: UTF8.self).contains("disabled-source-marker"))
        }
        snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["state_of_mind_entries"])
        snapshot.detailPolicy = .detailedTimeSeries
        for (end, valence) in [(instant.addingTimeInterval(-1), 0.5), (instant.addingTimeInterval(-0.0001), 0.5), (instant, 1.25)] {
            day.mindfulness.stateOfMind = [StateOfMindEntry(timestamp: instant, endDate: end,
                kind: .dailyMood, valence: valence, labels: [], associations: [])]
            do {
                _ = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot,
                    surface: .localVaultWithoutSideEffects)
                XCTFail("Invalid native mood records must reject the complete plan")
            } catch { XCTAssertEqual(error as? AppleLooseDailyExportPlannerError, .rustPlanningFailed) }
        }
    }

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
                startDate: coreStart, endDate: coreEnd, metadata: ["synthetic": "core, \"quoted\" | ` <source> &"]),
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
        for includeMetadata in [false, true] {
            for selection: Set<String> in [["sleep_total", "sleep_core", "sleep_in_bed", "sleep_bedtime", "sleep_wake"], ["sleep_total"]] {
                var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: selection)
                snapshot.detailPolicy = .detailedTimeSeries
                snapshot.includeMetadata = includeMetadata
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
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
                let sleep = try XCTUnwrap(root["sleep"] as? [String: Any])
                let expectedRecords = try XCTUnwrap(sleep["sleepStages"] as? [[String: Any]])
                let records = try markdown.components(separatedBy: "\n").filter { $0.contains("| `{") }.map { row in
                    let cell = try XCTUnwrap(row.components(separatedBy: "|").dropLast().last).trimmingCharacters(in: .whitespaces)
                    XCTAssertTrue(cell.hasPrefix("`{") && cell.hasSuffix("}`"))
                    return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(cell.dropFirst().dropLast().utf8)) as? [String: Any])
                }
                XCTAssertEqual(records as NSArray, expectedRecords as NSArray)
                let expected = try prepared.filteredData.toJSONDataThrowing(customization: settings.formatCustomization, captureContext: context)
                XCTAssertEqual(try JSONSerialization.jsonObject(with: json) as? NSDictionary,
                    try JSONSerialization.jsonObject(with: expected) as? NSDictionary)
                if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                    for artifact in operation.artifacts {
                        let output = URL(fileURLWithPath: directory).appendingPathComponent(selection.contains("sleep_core") ? "apple-v11-sleep-source-selected-\(includeMetadata)" : "apple-v11-sleep-source-total-\(includeMetadata)")
                            .appendingPathComponent(artifact.artifact.relativePath)
                        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try artifact.artifact.inlineData.write(to: output)
                    }
                }
            }
        }
    }

    func testSelectedQuantityDetailsWithoutSummariesReachEveryFormat() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let owner = ExportFixtures.referenceDate
        let timestamp = owner.addingTimeInterval(3600.125)
        let metadata = ["synthetic": "quantity, \"source\""]
        var day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.heart.heartRateSamples = [TimeSample(timestamp: timestamp, value: 72.125, metadata: metadata)]
        day.heart.hrvSamples = [TimeSample(timestamp: timestamp, value: 31.875, metadata: metadata)]
        day.vitals.bloodOxygenSamples = [TimeSample(timestamp: timestamp, value: 0.97125, metadata: metadata)]
        day.vitals.bloodGlucoseSamples = [TimeSample(timestamp: timestamp, value: 101.875, metadata: metadata)]
        day.vitals.respiratoryRateSamples = [TimeSample(timestamp: timestamp, value: 16.125, metadata: metadata)]
        XCTAssertFalse(day.hasSummaryData)
        for selection: Set<String> in [["heart_rate_avg", "hrv", "blood_oxygen", "blood_glucose", "respiratory_rate"], ["heart_rate_avg"]] {
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: selection)
            snapshot.detailPolicy = .detailedTimeSeries
            let result = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
            guard case .planned(let operation) = result else { return XCTFail("Selected quantities must reach all four native/core formats without summaries") }
            XCTAssertEqual(operation.artifacts.count, 4)
            let csv = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .csv }).artifact.inlineData, as: UTF8.self)
            XCTAssertEqual(csv.components(separatedBy: "\n").filter { $0.contains(",Native Detail,Quantity Sample,") }.count, selection.count)
            XCTAssertTrue(csv.contains("72.125"))
            XCTAssertTrue(csv.contains("quantity"))
            let markdown = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .markdown }).artifact.inlineData, as: UTF8.self)
            XCTAssertTrue(markdown.contains("Heart Rate Sample Details"))
            XCTAssertTrue(markdown.contains("| 72.125 | bpm |"))
            XCTAssertFalse(markdown.contains("average_heart_rate:"))
            let bases = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .obsidianBases }).artifact.inlineData, as: UTF8.self)
            XCTAssertTrue(bases.contains("native_quantity_details:"))
            XCTAssertEqual(bases.contains("hrv_sdnn"), selection.contains("hrv"))
            XCTAssertFalse(bases.contains("hrv_rmssd"))
            let json = try XCTUnwrap(operation.artifacts.first { $0.format == .json }).artifact.inlineData
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
            let heart = try XCTUnwrap(root["heart"] as? [String: Any])
            XCTAssertNil(heart["averageHeartRate"])
            XCTAssertEqual((heart["heartRateSamples"] as? [[String: Any]])?.first?["timestamp"] as? String, CanonicalRFC3339UTC.string(from: timestamp))
            if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                for artifact in operation.artifacts {
                    let output = URL(fileURLWithPath: directory).appendingPathComponent(selection.count == 5 ? "apple-v11-quantities" : "apple-v11-heart-only")
                        .appendingPathComponent(artifact.artifact.relativePath)
                    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try artifact.artifact.inlineData.write(to: output)
                }
            }
        }
    }

    func testSelectedBloodPressurePairWithoutSummariesReachesEveryFormat() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let owner = ExportFixtures.referenceDate
        let start = owner.addingTimeInterval(3600.125)
        let end = start.addingTimeInterval(0.75)
        let sample = BloodPressureSample(correlationUUID: UUID(uuidString: "00000000-0000-4000-8000-000000000104"),
            systolic: 120.125, diastolic: 80.875, startDate: start, endDate: end,
            sourceRevision: HealthKitSourceRevision(name: "Synthetic, \"source\"", bundleIdentifier: "example.synthetic.bp"),
            device: HealthKitDeviceProvenance(model: "Synthetic cuff"), metadata: ["synthetic": "paired-pressure"])
        let day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 0), vitals: VitalsData(bloodPressureSamples: [sample]))
        for selection: Set<String> in [["blood_pressure_systolic", "blood_pressure_diastolic"], ["blood_pressure_systolic", "steps"]] {
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: selection)
            snapshot.detailPolicy = .detailedTimeSeries
            let result = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
            guard case .planned(let operation) = result else { return XCTFail("Paired selected correlations must reach native/core formats") }
            XCTAssertEqual(operation.artifacts.count, 4)
            let json = try XCTUnwrap(operation.artifacts.first { $0.format == .json }).artifact.inlineData
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
            let vitals = root["vitals"] as? [String: Any]
            XCTAssertNil(vitals?["bloodPressureSystolicAvg"])
            XCTAssertNil(vitals?["bloodPressureDiastolicAvg"])
            XCTAssertEqual((vitals?["bloodPressureSamples"] as? [[String: Any]])?.count ?? 0, selection.contains("blood_pressure_diastolic") ? 1 : 0)
            for artifact in operation.artifacts where artifact.format != .json {
                let text = String(decoding: artifact.artifact.inlineData, as: UTF8.self)
                XCTAssertEqual(text.contains("120.125"), selection.contains("blood_pressure_diastolic"))
                XCTAssertEqual(text.contains("80.875"), selection.contains("blood_pressure_diastolic"))
                XCTAssertFalse(text.contains("blood_pressure_systolic:"))
                if selection.contains("blood_pressure_diastolic") && artifact.format != .markdown {
                    XCTAssertTrue(text.contains("example.synthetic.bp"))
                    XCTAssertTrue(text.contains("00000000-0000-4000-8000-000000000104"))
                }
            }
            if selection.contains("blood_pressure_diastolic"), let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                for artifact in operation.artifacts {
                    let output = URL(fileURLWithPath: directory).appendingPathComponent("apple-v11-blood-pressure").appendingPathComponent(artifact.artifact.relativePath)
                    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try artifact.artifact.inlineData.write(to: output)
                }
            }
        }
    }

    func testSelectedStageWithoutSummaryRetainsSourceIntervalAcrossEveryFormat() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let owner = ExportFixtures.referenceDate
        let start = owner.addingTimeInterval(3600.25)
        let end = owner.addingTimeInterval(7200.75)
        let day = HealthData(date: owner,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            sleep: SleepData(sessionStart: start, sessionEnd: end,
                stages: [SleepStageSample(stage: "core", startDate: start, endDate: end,
                    metadata: ["synthetic": "detail-without-summary"])]))
        XCTAssertFalse(day.sleep.hasData)
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["sleep_core"])
        snapshot.detailPolicy = .detailedTimeSeries
        let result = try await AppleLooseDailyExportPlanner().plan(healthData: day,
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
        guard case .planned(let operation) = result else { return XCTFail("Selected source detail must not require a fabricated summary") }
        XCTAssertEqual(operation.artifacts.count, 4)
        let json = try XCTUnwrap(operation.artifacts.first { $0.format == .json }).artifact.inlineData
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let sleep = try XCTUnwrap(root["sleep"] as? [String: Any])
        XCTAssertNil(sleep["coreSleep"])
        XCTAssertNil(sleep["totalDuration"])
        XCTAssertNil(sleep["bedtimeISO"])
        XCTAssertNil(sleep["wakeTimeISO"])
        XCTAssertEqual((sleep["sleepStages"] as? [[String: Any]])?.count, 1)
        for artifact in operation.artifacts where artifact.format != .json {
            let text = String(decoding: artifact.artifact.inlineData, as: UTF8.self)
            XCTAssertFalse(text.contains("sleep_core_hours:"))
            XCTAssertFalse(text.contains(",Core Sleep,"))
            XCTAssertTrue(text.contains(artifact.format == .markdown ? "| core |" : "detail-without-summary"))
        }
    }

    func testLargePartialFailureStaysOutsideBoundedHandoffAndProducesFileBackedOutput() async throws {
        let context = AppleSleepCaptureContext(timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")), sleepDayAttribution: .morningEnds)
        let day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: context.timeZone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 42), partialFailures: [ExportPartialFailure(
                date: ExportFixtures.referenceDate, dataType: "synthetic source", dateRangeDescription: "one day",
                errorDescription: String(repeating: "x", count: 9 * 1024 * 1024))])
        var snapshot = try acceptedSnapshot(context: context, formats: [.json], selectionIDs: ["steps"])
        snapshot.detailPolicy = .summary
        let settings = snapshot.makeAdvancedExportSettings()
        Self.retainedSettings.append(settings)
        let aggregate = try day.aggregateJSONDataThrowing(customization: settings.formatCustomization, captureContext: context)
        XCTAssertLessThan(aggregate.count, 64 * 1024)
        XCTAssertFalse(String(decoding: aggregate, as: UTF8.self).contains("partial_failures"))
        guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else {
            return XCTFail("Large native diagnostics must not cross the bounded aggregate boundary")
        }
        let artifact = try XCTUnwrap(operation.artifacts.first?.artifact)
        XCTAssertGreaterThan(artifact.byteCount, 9 * 1024 * 1024)
        try XCTUnwrap(artifact.fileArtifact).validateIntegrity()
        let preview = try await AppleLooseDailyExportPreviewPlanner.textPreviews(for: [artifact])
        XCTAssertEqual(preview.first?.originalByteCount, Int(artifact.byteCount))
        XCTAssertGreaterThan(preview.first?.omittedByteCount ?? 0, 8 * 1024 * 1024)
    }

    func testWakeDatePartialFailureFactsSurviveEveryDetailPolicyFormatAndMetadataChoice() async throws {
        let context = AppleSleepCaptureContext(timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")), sleepDayAttribution: .morningEnds)
        let date = ExportFixtures.referenceDate
        let failures = [ExportPartialFailure(date: date.addingTimeInterval(0.1255), dataType: "sleep | <source>",
            dateRangeDescription: "synthetic range", errorDescription: "synthetic `failure` & quote \"kept\"\n🌙")]
        for policy: AppleExportDetailPolicy in [.summary, .detailedTimeSeries, .archiveOnly, .lossless] {
            for metadata in [true, false] {
                let archive = policy.includesCanonicalArchive ? HealthKitRecordArchive(captureStatus: .partial,
                    dailyOwnership: HealthKitDailyOwnershipMetadata(ownerDate: "2026-03-15", intervalStart: date,
                        intervalEnd: date.addingTimeInterval(86400), calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier)) : nil
                let day = HealthData(date: date,
                    timeContext: ExportTimeContext(timeZone: context.timeZone, sleepDayAttribution: .morningEnds),
                    activity: ActivityData(steps: 42), partialFailures: failures, healthKitRecordArchive: archive)
                var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["steps"])
                snapshot.detailPolicy = policy
                snapshot.includeMetadata = metadata
                guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(healthData: day,
                    settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else {
                    return XCTFail("Partial capture requires successor artifacts, not a historical fallback")
                }
                XCTAssertEqual(operation.artifacts.count, 4)
                for planned in operation.artifacts {
                    let data = try planned.artifact.content.materializedData()
                    XCTAssertEqual(planned.artifact.sha256, NativeExportArtifact.sha256(of: data))
                    XCTAssertNotNil(planned.artifact.fileArtifact)
                    let text = String(decoding: data, as: UTF8.self)
                    let expected = try ExportDiagnosticSerializer.jsonObject(for: failures[0]) as NSDictionary
                    switch planned.format {
                    case .json:
                        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                        let actual = try XCTUnwrap(((root["diagnostics"] as? [String: Any])?["partial_failures"] as? [NSDictionary])?.first)
                        XCTAssertEqual(actual, expected)
                        XCTAssertEqual(root["healthkit_record_archive"] != nil, policy.includesCanonicalArchive)
                    case .csv:
                        XCTAssertTrue(text.contains(",Diagnostics,Partial Failure," + CSVFieldEscaper.escape(try ExportDiagnosticSerializer.string(for: failures[0])) + ",json,"))
                    case .markdown, .obsidianBases:
                        XCTAssertTrue(text.contains("Capture Diagnostics"))
                        let row = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("| `{") && $0.contains("error_description") })
                        let actual = try JSONSerialization.jsonObject(with: Data(row.dropFirst(3).dropLast(3).utf8)) as? NSDictionary
                        XCTAssertEqual(actual, expected)
                    }
                }
            }
        }
    }

    func testWakeDateRangeRetainsEachDaysArchiveCaptureStatus() async throws {
        let context = AppleSleepCaptureContext(timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            sleepDayAttribution: .morningEnds)
        let statuses: [HealthKitRecordCaptureStatus] = [.complete, .partial]
        let days = statuses.enumerated().map { index, status in
            let date = ExportFixtures.referenceDate.addingTimeInterval(Double(index) * 86400)
            return HealthData(date: date,
                timeContext: ExportTimeContext(timeZone: context.timeZone, sleepDayAttribution: .morningEnds),
                healthKitRecordArchive: HealthKitRecordArchive(captureStatus: status,
                    dailyOwnership: HealthKitDailyOwnershipMetadata(
                        ownerDate: HealthKitDailyOwnershipMetadata.ownerDate(for: date,
                            calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier),
                        intervalStart: date, intervalEnd: date.addingTimeInterval(86400),
                        calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier)),
                healthKitRecordCaptureStatus: status)
        }
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["steps"])
        snapshot.detailPolicy = .archiveOnly
        guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().planRange(
            healthData: days, dailyOutputOwnerDates: ["2026-03-15", "2026-03-16"], requestedRange: nil,
            settingsSnapshot: snapshot, surface: .localVaultRangeWithoutSideEffects, operationIdentity: nil) else {
            return XCTFail("Mixed archive statuses must retain independent daily evidence")
        }
        XCTAssertEqual(operation.artifacts.count, 8)
        for planned in operation.artifacts {
            let expected = planned.artifact.relativePath.contains("2026-03-15") ? "complete" : "partial"
            let text = String(decoding: try planned.artifact.content.materializedData(), as: UTF8.self)
            switch planned.format {
            case .csv: XCTAssertTrue(text.contains(",Raw HealthKit,Raw Capture Status,\(expected),status,"))
            case .json:
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
                XCTAssertEqual(root["raw_capture_status"] as? String, expected)
            case .markdown, .obsidianBases: XCTAssertTrue(text.contains("raw_capture_status: \(expected)"))
            }
        }
    }

    func testWakeDateLargeFileBackedArchiveCommitsThroughRealVaultWithoutInlinePlanLimit() async throws {
        let context = AppleSleepCaptureContext(timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            sleepDayAttribution: .morningEnds)
        let owner = ExportFixtures.referenceDate
        let bytes = Data(repeating: 0x7a, count: 7 * 1024 * 1024)
        let attachmentFile = try ExportArtifactIO.renderTemporary(prefix: "synthetic-wake-attachment",
            mediaType: "application/octet-stream") { try $0.write(bytes) }
        let external = ClinicalDocumentVisionHealthKitRecordMapper.attachment(HealthKitAttachmentValue(
            identifier: UUID(uuidString: "20000000-0000-0000-0000-000000000099")!,
            filename: "synthetic.bin", uniformTypeIdentifier: "public.data", byteCount: Int64(bytes.count),
            creationDate: owner, data: nil, fileBackedData: HealthKitFileBackedBlob(artifact: attachmentFile),
            sha256: attachmentFile.descriptor.sha256),
            parentUUID: UUID(uuidString: "10000000-0000-0000-0000-000000000099")!,
            parentObjectTypeIdentifier: "HKClinicalRecord", selectedMetricIDs: ["heart_rate_avg"])
        let archive = HealthKitRecordArchive(captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(ownerDate: "2026-03-15", intervalStart: owner,
                intervalEnd: owner.addingTimeInterval(86400),
                calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier), externalRecords: [external])
        let day = HealthData(date: owner,
            timeContext: ExportTimeContext(timeZone: context.timeZone, sleepDayAttribution: .morningEnds),
            healthKitRecordArchive: archive, healthKitRecordCaptureStatus: .complete)
        var snapshot = try acceptedSnapshot(context: context, formats: [.json, .csv], selectionIDs: ["heart_rate_avg"])
        snapshot.detailPolicy = .archiveOnly
        guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(
            healthData: day, settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else {
            return XCTFail("Large source archives require a final file-backed plan")
        }
        XCTAssertEqual(operation.artifacts.count, 2)
        for planned in operation.artifacts {
            let file = try XCTUnwrap(planned.artifact.fileArtifact)
            XCTAssertGreaterThan(file.descriptor.byteCount, 8 * 1024 * 1024)
            try file.validateIntegrity()
        }
        let optionalPreviews = try await AppleLooseDailyExportPreviewPlanner.artifacts(
            healthData: day, settingsSnapshot: snapshot, planner: AppleLooseDailyExportPlanner())
        let previews = try XCTUnwrap(optionalPreviews)
        XCTAssertEqual(previews.count, 2)
        for preview in previews {
            let original = try XCTUnwrap(operation.artifacts.first { $0.artifact.relativePath == preview.relativePath })
            XCTAssertEqual(UInt64(preview.preview.originalByteCount), original.artifact.byteCount)
            XCTAssertGreaterThan(preview.preview.omittedByteCount, 8 * 1024 * 1024)
            XCTAssertLessThanOrEqual(preview.preview.head.utf8.count + preview.preview.tail.utf8.count, 64 * 1024)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyntheticWakeVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bookmarks = FakeBookmarkResolver()
        bookmarks.accessGranted = true
        let vault = VaultManager(defaults: FakeUserDefaults(), fileSystem: SystemFileSystem(), bookmarkResolver: bookmarks)
        vault.healthSubfolder = "Health"
        vault.setVaultFolder(root)
        Self.retainedManagers.append(vault)
        let result = try await vault.exportHealthDataRange([day], settingsSnapshot: snapshot,
            operationSurface: .localVaultRangeWithoutSideEffects, writeDataDictionary: false)
        XCTAssertEqual(result?.dailyFileCount, 2)
        for planned in operation.artifacts {
            let destination = root.appendingPathComponent(planned.artifact.relativePath)
            let committed = try Data(contentsOf: destination)
            XCTAssertEqual(UInt64(committed.count), planned.artifact.byteCount)
            XCTAssertEqual(NativeExportArtifact.sha256(of: committed), planned.artifact.sha256)
        }
    }

    func testWakeDateCanonicalArchiveRemainsIndependentAndFileBackedAcrossFormats() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let source = try XCTUnwrap(ExportFixtures.losslessDay.healthKitRecordArchive)
        let archive = HealthKitRecordArchive(captureStatus: source.captureStatus,
            dailyOwnership: HealthKitDailyOwnershipMetadata(ownerDate: source.dailyOwnership.ownerDate,
                intervalStart: source.dailyOwnership.intervalStart, intervalEnd: source.dailyOwnership.intervalEnd,
                calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier),
            records: source.records, externalRecords: source.externalRecords,
            queryManifest: source.queryManifest, integrityWarnings: source.integrityWarnings,
            medicationInventoryRecords: source.medicationInventoryRecords)
        let day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 42), healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: archive.captureStatus)
        let selected: Set<String> = ["steps", "heart_rate_avg", "heart_rate_max"]
        let selectedArchive = archive.filtered(enabledMetricIDs: selected)
        XCTAssertFalse(selectedArchive.records.isEmpty)
        for policy: AppleExportDetailPolicy in [.archiveOnly, .lossless] {
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: selected)
            snapshot.detailPolicy = policy
            guard case .planned(let operation) = try await AppleLooseDailyExportPlanner().plan(
                healthData: day, settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects) else {
                return XCTFail("Canonical archives require the successor plan")
            }
            XCTAssertEqual(operation.artifacts.count, 4)
            for planned in operation.artifacts {
                let artifact = planned.artifact
                let data = try artifact.content.materializedData()
                XCTAssertEqual(artifact.sha256, NativeExportArtifact.sha256(of: data))
                let text = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(text.contains("morning_ends"))
                switch planned.format {
                case .json:
                    XCTAssertNotNil(artifact.fileArtifact)
                    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                    let actual = try XCTUnwrap(root["healthkit_record_archive"] as? NSDictionary)
                    let expected = try XCTUnwrap(try JSONSerialization.jsonObject(with:
                        HealthKitRecordArchiveSerializer.data(for: selectedArchive)) as? NSDictionary)
                    XCTAssertEqual(actual, expected)
                    XCTAssertTrue(text.contains("18446744073709551615"))
                    XCTAssertTrue(text.contains("record_start_in_half_open_day_interval"))
                case .csv:
                    XCTAssertNotNil(artifact.fileArtifact)
                    let sink = MemoryExportByteSink(mediaType: "text/csv")
                    try HealthKitArchiveCSVProjection.write(archive: selectedArchive,
                        ownerDate: archive.dailyOwnership.ownerDate, to: sink)
                    _ = try sink.finish()
                    XCTAssertTrue(data.suffix(sink.data.count).elementsEqual(sink.data))
                case .markdown:
                    XCTAssertNotNil(artifact.fileArtifact)
                    XCTAssertTrue(text.contains("Lossless Health Records"))
                    XCTAssertFalse(text.contains("canonical_record_json"))
                case .obsidianBases:
                    XCTAssertTrue(text.contains("raw_record_count:"))
                }
            }
        }
    }

    func testWakeDateDetailsAdmitArchivePoliciesAndRejectRemoteSurfacesAndInvalidPairs() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
            selectionIDs: ["sleep_total", "blood_pressure_systolic", "blood_pressure_diastolic"])
        snapshot.detailPolicy = .detailedTimeSeries
        XCTAssertTrue(AppleLooseDailyExportPlanner.supports(settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects))
        XCTAssertFalse(AppleLooseDailyExportPlanner.supports(settingsSnapshot: snapshot, surface: .directGeneratedFilesWithoutSideEffects))
        XCTAssertFalse(AppleLooseDailyExportPlanner.supports(settingsSnapshot: snapshot, surface: .connectedReceivedFilesWithoutSideEffects))
        for policy: AppleExportDetailPolicy in [.archiveOnly, .lossless] {
            var accepted = snapshot
            accepted.detailPolicy = policy
            XCTAssertTrue(AppleLooseDailyExportPlanner.supports(settingsSnapshot: accepted, surface: .localVaultWithoutSideEffects))
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
                sessionEnd: owner.addingTimeInterval(7200)), vitals: VitalsData(bloodPressureSamples: [
                BloodPressureSample(systolic: 120, diastolic: 80, startDate: owner.addingTimeInterval(1), endDate: owner)]))
        XCTAssertTrue(day.sleep.stages.isEmpty)
        do {
            _ = try await AppleLooseDailyExportPlanner().plan(healthData: day, settingsSnapshot: snapshot,
                surface: .localVaultWithoutSideEffects)
            XCTFail("Invalid correlation bounds must reject even without sleep stages")
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

    func testSelectedNativeQuantityFamiliesKeepPrecisionAndCanonicalUnits() async throws {
        let suite = "WakeDateQuantityMatrix.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        var day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.activity.swimmingDistance = 12.345678
        day.activity.wheelchairDistance = 12_345.678
        day.activity.downhillSnowSportsDistance = 12_345.678
        day.activity.standTimeMinutes = 12.345678
        day.heart.atrialFibrillationBurden = 0.12345678
        day.vitals.bodyTemperatureAvg = 36.123456
        day.vitals.basalBodyTemperature = 36.234567
        day.vitals.wristTemperature = 36.345678
        day.vitals.forcedVitalCapacity = 3.123456
        day.vitals.forcedExpiratoryVolume1 = 2.123456
        day.vitals.peakExpiratoryFlowRate = 123.456789
        day.body.bodyFatPercentage = 0.12345678
        day.body.waistCircumference = 0.92345678
        day.mobility.walkingStepLength = 0.72345678
        day.mobility.walkingDoubleSupportPercentage = 0.12345678
        day.mobility.walkingAsymmetryPercentage = 0.02345678
        day.mobility.walkingSteadiness = 0.92345678
        day.mobility.runningVerticalOscillation = 7.123456
        day.cyclingPerformance.cyclingSpeed = 7.123456
        day.vitamins.vitaminA = 123.456789
        day.vitamins.vitaminB12 = 2.123456
        day.minerals.iodine = 123.456789
        day.nutrition.water = 2.123456
        // Independently stated canonical values: source ratios become percentages,
        // source metres become centimetres/kilometres, and temperatures stay Celsius.
        let cases: [(selection: String, key: String, value: Double)] = [
            ("distance_swimming", "swimming_m", 12.345678),
            ("distance_wheelchair", "wheelchair_km", 12.345678),
            ("distance_downhill_snow", "downhill_snow_km", 12.345678),
            ("stand_time", "stand_time_minutes", 12.345678),
            ("afib_burden", "afib_burden_percent", 12.345678),
            ("body_temperature", "body_temperature_avg", 36.123456),
            ("basal_body_temperature", "basal_body_temperature", 36.234567),
            ("wrist_temperature", "wrist_temperature", 36.345678),
            ("forced_vital_capacity", "forced_vital_capacity_l", 3.123456),
            ("fev1", "fev1_l", 2.123456),
            ("peak_expiratory_flow", "peak_expiratory_flow", 123.456789),
            ("body_fat", "body_fat_percent", 12.345678),
            ("waist_circumference", "waist_circumference_cm", 92.345678),
            ("walking_step_length", "step_length_cm", 72.345678),
            ("walking_double_support", "double_support_percent", 12.345678),
            ("walking_asymmetry", "walking_asymmetry_percent", 2.345678),
            ("walking_steadiness", "walking_steadiness_percent", 92.345678),
            ("running_vertical_oscillation", "running_vertical_oscillation_cm", 7.123456),
            ("cycling_speed", "cycling_speed", 7.123456),
            ("vitamin_a", "vitamin_a_ug", 123.456789),
            ("vitamin_b12", "vitamin_b12_ug", 2.123456),
            ("iodine", "iodine_ug", 123.456789),
            ("dietary_water", "water_l", 2.123456),
        ]
        for units: UnitPreference in [.metric, .imperial] {
            for item in cases {
                var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
                    selectionIDs: [item.selection], unitPreference: units)
                // The native field ledger is explicit: less common quantities are
                // absent from the default list. Request this field before testing it.
                if !snapshot.formatCustomization.frontmatterConfig.fields.contains(where: { $0.originalKey == item.key }) {
                    snapshot.formatCustomization.frontmatterConfig.fields.append(CustomFrontmatterField(originalKey: item.key))
                }
                let result = try await AppleLooseDailyExportPlanner().plan(healthData: day,
                    settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
                guard case .planned(let operation) = result else {
                    XCTFail("Selected native quantity must reach every format: \(item.selection)")
                    continue
                }
                XCTAssertEqual(operation.artifacts.count, 4, item.selection)
                let settings = snapshot.makeAdvancedExportSettings(userDefaults: defaults)
                Self.retainedSettings.append(settings)
                let expectedJSON = try day.preparedExport(settings: settings).filteredData
                    .toJSONDataThrowing(customization: settings.formatCustomization, captureContext: context)
                let json = try XCTUnwrap(operation.artifacts.first { $0.format == .json }).artifact.inlineData
                XCTAssertEqual(try JSONSerialization.jsonObject(with: json) as? NSDictionary,
                    try JSONSerialization.jsonObject(with: expectedJSON) as? NSDictionary, item.selection)
                let csv = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .csv }).artifact.inlineData, as: UTF8.self)
                let csvValues = csv.components(separatedBy: "\n").compactMap { line -> Double? in
                    let fields = line.components(separatedBy: ",")
                    guard fields.count == 6, fields[1] != "Metadata" else { return nil }
                    return Double(fields[3])
                }
                XCTAssertTrue(csvValues.contains { abs($0 - item.value) < 1e-10 }, "CSV quantity \(item.selection), \(units)")
                for artifact in operation.artifacts where artifact.format == .markdown || artifact.format == .obsidianBases {
                    let text = String(decoding: artifact.artifact.inlineData, as: UTF8.self)
                    let line = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("\(item.key): ") }, "\(item.selection), \(units), \(artifact.format)")
                    let value = try XCTUnwrap(Double(line.dropFirst(item.key.count + 2)), item.selection)
                    XCTAssertEqual(value, item.value, accuracy: 1e-10, "\(item.selection), \(units)")
                    for other in cases where other.selection != item.selection {
                        XCTAssertFalse(text.contains("\n\(other.key): "), "Unselected quantity leaked: \(other.key)")
                    }
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
        var baselineSummaryBytes: [ExportFormat: Data] = [:]
        for summaryOnly in [false, true] {
            var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
                selectionIDs: ["sleep_total", "sleep_core"], rangeSummary: true)
            snapshot.summaryOnlyExport = summaryOnly
            let resolution = try await AppleLooseDailyExportPlanner().planRange(healthData: [populated, empty],
                dailyOutputOwnerDates: ["2026-11-01"], requestedRange: requested,
                settingsSnapshot: snapshot, surface: .localVaultRangeWithoutSideEffects,
                operationIdentity: AppleExportOperationIdentity(requestID: "sleep-range-request", sessionID: "sleep-range-session",
                    capturedAt: try XCTUnwrap(formatter.date(from: "2026-11-04T12:00:00Z")),
                    calendarTimeZoneIdentifier: zone.identifier))
            guard case .planned(let operation) = resolution else { return XCTFail("The successor range must not fall back to a historical writer") }
            let summaries = operation.artifacts.filter { $0.kind == .rollup }
            XCTAssertEqual(summaries.count, 4)
            XCTAssertEqual(operation.artifacts.count, summaryOnly ? 4 : 8)
            if summaryOnly {
                XCTAssertTrue(operation.artifacts.allSatisfy { $0.kind == .rollup })
            }
            for planned in summaries {
                let bytes = planned.artifact.inlineData
                if summaryOnly {
                    XCTAssertEqual(bytes, baselineSummaryBytes[planned.format], "Summary-only must preserve exact range bytes")
                } else {
                    baselineSummaryBytes[planned.format] = bytes
                }
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
    }

    func testDormantSummaryOnlyPreferenceKeepsDailyOutputWhenRangeSummaryIsDisabled() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 123))
        var snapshot = try acceptedSnapshot(context: context, formats: [.json], selectionIDs: ["steps"])
        snapshot.summaryOnlyExport = true
        let result = try await AppleLooseDailyExportPlanner().planRange(healthData: [day],
            settingsSnapshot: snapshot, surface: .localVaultRangeWithoutSideEffects)
        guard case .planned(let operation) = result else { return XCTFail("A dormant summary-only preference must retain daily output") }
        XCTAssertEqual(operation.artifacts.count, 1)
        XCTAssertEqual(operation.artifacts.first?.kind, .daily)
        let bytes = try XCTUnwrap(operation.artifacts.first).artifact.inlineData
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(root["schema_version"] as? Int, 11)
        XCTAssertEqual((root["activity"] as? [String: Any])?["steps"] as? Int, 123)
    }

    func testWorkoutsReachEverySuccessorFormatWithExactNativeQuantities() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let owner = ExportFixtures.referenceDate
        let first = WorkoutData(sourceUUID: UUID(uuidString: "00000000-0000-4000-8000-000000000135"),
            workoutType: .running, startTime: owner.addingTimeInterval(0.125),
            actualEndDate: owner.addingTimeInterval(1900.875),
            metadata: ["synthetic": "workout, source"], duration: 1800.5, calories: 320.125, distance: 5000.875,
            avgHeartRate: 160.125, maxHeartRate: 179.875, minHeartRate: 91.125,
            avgRunningCadence: 178.625, avgStrideLength: 1.1875, avgGroundContactTime: 245.125,
            avgVerticalOscillation: 8.4375, avgPower: 240.125, maxPower: 312.875)
        let second = WorkoutData(sourceUUID: UUID(uuidString: "00000000-0000-4000-8000-000000000136"),
            workoutType: .cycling, startTime: owner.addingTimeInterval(7200.25),
            duration: 3600.25, calories: 540.875, distance: 25000.125,
            avgHeartRate: 140.875, maxHeartRate: 172.125, minHeartRate: 100.875,
            avgCyclingCadence: 85.625, avgPower: 195.875, maxPower: 410.125)
        let day = HealthData(date: owner,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 0), workouts: [first, second])
        for preference in [UnitPreference.metric, .imperial] {
            for (detailName, detail) in [("summary", AppleExportDetailPolicy.summary), ("detailed", .detailedTimeSeries)] {
                var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
                    selectionIDs: ["workouts", "steps"], unitPreference: preference)
                snapshot.detailPolicy = detail
                let resolution = try await AppleLooseDailyExportPlanner().plan(healthData: day,
                    settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
                guard case .planned(let operation) = resolution else {
                    return XCTFail("Selected workouts must reach the concrete successor planner")
                }
                XCTAssertEqual(operation.artifacts.count, 4)
                let json = try XCTUnwrap(operation.artifacts.first { $0.format == .json }).artifact.inlineData
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
                XCTAssertEqual(root["schema_profile"] as? String, "apple-v11")
                let workouts = try XCTUnwrap(root["workouts"] as? [[String: Any]])
                XCTAssertEqual(workouts.count, 2)
                XCTAssertEqual(workouts[0]["avgHeartRate"] as? Double, 160.125)
                XCTAssertEqual(workouts[0]["avgRunningCadence"] as? Double, 178.625)
                XCTAssertEqual(workouts[0]["avgGroundContactTime"] as? Double, 245.125)
                XCTAssertEqual(workouts[1]["avgPower"] as? Double, 195.875)
                XCTAssertEqual(workouts[0]["duration"] as? Double, 1800.5)
                XCTAssertEqual(workouts[0]["elapsedDuration"] as? Double, 1900.75)
                XCTAssertEqual(workouts[0]["startTimeISO"] as? String, CanonicalRFC3339UTC.string(from: first.startTime))
                XCTAssertEqual(workouts[0]["endTimeISO"] as? String, CanonicalRFC3339UTC.string(from: first.endTime))
                let csv = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .csv }).artifact.inlineData, as: UTF8.self)
                XCTAssertEqual(csv.components(separatedBy: "\n").filter { $0.contains(",Native Detail,Workout,") }.count, 2)
                let expectedSummary: [String: Double] = [
                    "Workout Count": 2, "Workout Minutes": 5400.75 / 60, "Workout Calories": 861,
                    "Workout Distance Km": 30001.0 / 1000, "Workout Distance Mi": 30001.0 / 1609.344,
                    "Workout Avg Heart Rate": (160.125 * 1800.5 + 140.875 * 3600.25) / 5400.75,
                    "Workout Max Heart Rate": 179.875, "Workout Min Heart Rate": 91.125,
                    "Workout Running Cadence": 178.625, "Workout Running Stride Length": 1.1875,
                    "Workout Running Ground Contact": 245.125, "Workout Running Vertical Oscillation": 8.4375,
                    "Workout Cycling Cadence": 85.625,
                    "Workout Avg Power": (240.125 * 1800.5 + 195.875 * 3600.25) / 5400.75,
                    "Workout Max Power": 410.125,
                ]
                for (label, expected) in expectedSummary {
                    let row = try XCTUnwrap(csv.components(separatedBy: "\n").first { $0.contains(",Workouts,\(label),") })
                    let actual = try XCTUnwrap(Double(row.components(separatedBy: ",")[3]))
                    XCTAssertEqual(actual, expected, accuracy: 0.0000000001, label)
                }
                XCTAssertTrue(csv.contains("160.125"))
                XCTAssertTrue(csv.contains("00000000-0000-4000-8000-000000000135"))
                let markdown = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .markdown }).artifact.inlineData, as: UTF8.self)
                XCTAssertTrue(markdown.contains("Workout Details"))
                XCTAssertTrue(markdown.contains("160.125"))
                let bases = String(decoding: try XCTUnwrap(operation.artifacts.first { $0.format == .obsidianBases }).artifact.inlineData, as: UTF8.self)
                XCTAssertTrue(bases.contains("native_workout_details:"))
                XCTAssertTrue(bases.contains("195.875"))
                if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                    for artifact in operation.artifacts {
                        let output = URL(fileURLWithPath: directory)
                            .appendingPathComponent("apple-v11-workouts-\(preference.rawValue)-\(detailName)")
                            .appendingPathComponent(artifact.artifact.relativePath)
                        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try artifact.artifact.inlineData.write(to: output)
                    }
                }
            }
        }
    }

    func testSDKWorkoutProjectionKeepsStartDayOwnershipAndCompleteDetailsThroughEveryFormat() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let clock = ExportDateFormatting.utcISO8601Formatter()
        let owner = try XCTUnwrap(clock.date(from: "2026-11-01T04:00:00Z"))
        let start = try XCTUnwrap(clock.date(from: "2026-11-01T05:30:00Z")).addingTimeInterval(0.123456789)
        let end = try XCTUnwrap(clock.date(from: "2026-11-01T06:30:00Z")).addingTimeInterval(0.987654321)
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let store = FakeHealthStore()
        let sourceID = try XCTUnwrap(UUID(uuidString: "00000000-0000-4000-8000-000000000137"))
        let source = HealthKitSourceRevision(name: "Synthetic workout source", bundleIdentifier: "example.synthetic.workout")
        let series = WorkoutTimeSeries(heartRate: [TimeSeriesSample(timestamp: start, value: 160.125, metadata: ["synthetic": "sample"])],
            speed: [TimeSeriesSample(timestamp: start, value: 3.125)], power: [TimeSeriesSample(timestamp: start, value: 240.125)],
            cadence: [TimeSeriesSample(timestamp: start, value: 178.625)], strideLength: [TimeSeriesSample(timestamp: start, value: 1.1875)],
            groundContactTime: [TimeSeriesSample(timestamp: start, value: 245.125)],
            verticalOscillation: [TimeSeriesSample(timestamp: start, value: 8.4375)], altitude: [TimeSeriesSample(timestamp: start, value: 35.125)])
        store.workoutResults = [
            WorkoutValue(sourceUUID: sourceID, activityType: HKWorkoutActivityType.running.rawValue,
                duration: 1800.5, startDate: start, endDate: end, sourceRevision: source,
                metadata: ["synthetic": "captured | workout"], totalEnergyBurned: 320.125, totalDistance: 5000.875,
                avgHeartRate: 160.125, avgPower: 240.125,
                laps: [WorkoutLap(startDate: start, endDate: start.addingTimeInterval(600.75), duration: 600.75, distanceMeters: 1000.125)],
                splits: [WorkoutSplit(index: 1, startDate: start, duration: 600.75, distanceMeters: 1000.125, avgHeartRate: 160.125)],
                route: [RoutePoint(timestamp: start, latitude: 0.125, longitude: 0.375, altitudeMeters: 35.125,
                    speedMps: 3.125, courseDegrees: 45.125, horizontalAccuracyMeters: 1.125)], timeSeries: series),
            // A workout starting before this owner date must not be reassigned by its end, unlike sleep.
            WorkoutValue(activityType: HKWorkoutActivityType.running.rawValue, duration: 120,
                startDate: owner.addingTimeInterval(-60), endDate: owner.addingTimeInterval(60),
                totalEnergyBurned: 1, totalDistance: 1),
        ]
        let manager = HealthKitManager(store: store)
        let captured = try await manager.fetchWorkoutProjection(for: owner, calendar: calendar)
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].sourceUUID, sourceID)
        XCTAssertEqual(captured[0].sourceRevision, source)
        XCTAssertEqual(captured[0].endTime, end)
        XCTAssertEqual(captured[0].duration, 1800.5)
        XCTAssertEqual(captured[0].timeSeries, series)
        let day = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds), workouts: captured)
        var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["workouts"])
        snapshot.detailPolicy = .detailedTimeSeries
        snapshot.includeMetadata = false
        let resolution = try await AppleLooseDailyExportPlanner().plan(healthData: day,
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
        guard case .planned(let operation) = resolution else { return XCTFail("SDK workout projection must reach the successor planner") }
        XCTAssertEqual(operation.artifacts.count, 4)
        let json = try XCTUnwrap(operation.artifacts.first { $0.format == .json }).artifact.inlineData
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let workout = try XCTUnwrap((root["workouts"] as? [[String: Any]])?.first)
        XCTAssertEqual(workout["elapsedDuration"] as? Double, end.timeIntervalSince(start))
        XCTAssertEqual(workout["duration"] as? Double, 1800.5)
        XCTAssertEqual((workout["splits"] as? [[String: Any]])?.first?["avgHeartRate"] as? Double, 160.125)
        XCTAssertEqual((workout["route"] as? [[String: Any]])?.first?["timestamp"] as? String, CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: start))
        let heartSamples = (workout["timeSeries"] as? [String: Any])?["heartRate"] as? [[String: Any]]
        XCTAssertEqual(heartSamples?.first?["timestamp"] as? String, CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: start))
        XCTAssertEqual(heartSamples?.first?["value"] as? Double, 160.125)
        for artifact in operation.artifacts {
            let text = String(decoding: artifact.artifact.inlineData, as: UTF8.self)
            XCTAssertTrue(text.contains("160.125"))
            XCTAssertTrue(text.contains("240.125"))
        }
        if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
            for artifact in operation.artifacts {
                let output = URL(fileURLWithPath: directory).appendingPathComponent("apple-v11-workouts-sdk")
                    .appendingPathComponent(artifact.artifact.relativePath)
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try artifact.artifact.inlineData.write(to: output)
            }
        }
    }

    func testUnselectedWorkoutDoesNotLeakIntoSuccessorArtifacts() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let workout = WorkoutData(sourceUUID: UUID(uuidString: "00000000-0000-4000-8000-000000000138"),
            workoutType: .running, startTime: ExportFixtures.referenceDate, duration: 1800.5,
            calories: 320.125, distance: 5000.875, avgHeartRate: 160.125)
        let day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 0), workouts: [workout])
        let snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases), selectionIDs: ["steps"])
        let resolution = try await AppleLooseDailyExportPlanner().plan(healthData: day,
            settingsSnapshot: snapshot, surface: .localVaultWithoutSideEffects)
        guard case .planned(let operation) = resolution else { return XCTFail("Unselected workouts must not block selected steps") }
        XCTAssertEqual(operation.artifacts.count, 4)
        for artifact in operation.artifacts {
            let text = String(decoding: artifact.artifact.inlineData, as: UTF8.self)
            XCTAssertFalse(text.contains("00000000-0000-4000-8000-000000000138"))
            XCTAssertFalse(text.contains("native_workout_details"))
            XCTAssertFalse(text.contains("workout_count"))
            XCTAssertFalse(text.contains("160.125"))
        }
    }

    func testExplicitWorkoutRangeAuthorityUsesMeasuredDurationsAndTrueExtremaAcrossAllFormats() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let firstDate = ExportFixtures.referenceDate
        let secondDate = firstDate.addingTimeInterval(86400)
        let days = [
            HealthData(date: firstDate, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds), workouts: [
                WorkoutData(workoutType: .running, startTime: firstDate, duration: 600, calories: nil, distance: nil,
                    avgHeartRate: 100, maxHeartRate: 260, minHeartRate: 50,
                    avgRunningCadence: 180, avgStrideLength: 1, avgGroundContactTime: 200,
                    avgVerticalOscillation: 6, avgPower: 100, maxPower: 400),
                WorkoutData(workoutType: .cycling, startTime: firstDate.addingTimeInterval(1200), duration: 1200, calories: nil, distance: nil, avgCyclingCadence: 80, avgPower: 100),
                WorkoutData(workoutType: .running, startTime: firstDate.addingTimeInterval(3600), duration: 1800, calories: nil, distance: nil),
            ]),
            HealthData(date: secondDate, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds), workouts: [
                WorkoutData(workoutType: .running, startTime: secondDate, duration: 1800, calories: nil, distance: nil,
                    avgHeartRate: 200, maxHeartRate: 250, minHeartRate: 55,
                    avgRunningCadence: 200, avgStrideLength: 2, avgGroundContactTime: 300,
                    avgVerticalOscillation: 10, maxPower: 900),
                WorkoutData(workoutType: .cycling, startTime: secondDate.addingTimeInterval(3600), duration: 600, calories: nil, distance: nil, avgCyclingCadence: 100, avgPower: 300),
                WorkoutData(workoutType: .running, startTime: secondDate.addingTimeInterval(7200), duration: 4800, calories: nil, distance: nil),
            ]),
        ]
        for preference in [UnitPreference.metric, .imperial] {
            for visibleDuration in [false, true] {
                for summaryOnly in [false, true] {
                    var snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
                        selectionIDs: ["workouts"], rangeSummary: true, unitPreference: preference, registryVersion: 3)
                    snapshot.summaryOnlyExport = summaryOnly
                    if !visibleDuration {
                        for index in snapshot.formatCustomization.frontmatterConfig.fields.indices {
                            if ["workout_count", "workout_minutes", "workouts"].contains(snapshot.formatCustomization.frontmatterConfig.fields[index].originalKey) {
                                snapshot.formatCustomization.frontmatterConfig.fields[index].isEnabled = false
                            }
                        }
                    }
                    let resolution = try await AppleLooseDailyExportPlanner().planRange(healthData: days,
                        settingsSnapshot: snapshot, surface: .localVaultRangeWithoutSideEffects)
                    guard case .planned(let operation) = resolution else { return XCTFail("Registry 3 must qualify workout ranges") }
                    XCTAssertEqual(operation.pin.registryVersion, 3)
                    XCTAssertEqual(operation.pin, snapshot.appleExportEnginePin)
                    let ranges = operation.artifacts.filter { $0.kind == .rollup }
                    XCTAssertEqual(ranges.count, 4)
                    XCTAssertEqual(operation.artifacts.filter { $0.kind == .daily }.count, summaryOnly ? 0 : 8)
                    let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(ranges.first { $0.format == .json }).artifact.inlineData) as? [String: Any])
                    XCTAssertEqual(root["schema_version"] as? Int, 11)
                    XCTAssertEqual(root["rollup_rules_version"] as? Int, 12)
                    let metrics = try XCTUnwrap(root["metrics"] as? [[String: Any]])
                    for (key, expected, rule) in [("workout_avg_heart_rate", 175.0, "weighted_average"), ("workout_avg_power", 150.0, "weighted_average"),
                                                  ("workout_max_heart_rate", 260.0, "maximum"), ("workout_min_heart_rate", 50.0, "minimum"), ("workout_max_power", 900.0, "maximum"), ("workout_running_cadence", 195.0, "weighted_average"),
                                                  ("workout_running_stride_length", 1.75, "weighted_average"), ("workout_running_ground_contact", 275.0, "weighted_average"),
                                                  ("workout_running_vertical_oscillation", 9.0, "weighted_average"), ("workout_cycling_cadence", 260.0 / 3.0, "weighted_average")] {
                        let metric = try XCTUnwrap(metrics.first { $0["key"] as? String == key })
                        let value = try XCTUnwrap(metric["primary_value"] as? String)
                        XCTAssertEqual(try XCTUnwrap(Double(value)), expected, accuracy: 1e-9, key)
                        XCTAssertEqual(metric["rule"] as? String, rule)
                        XCTAssertNotEqual(metric["display_name"] as? String, "Workouts")
                        if rule == "weighted_average" {
                            XCTAssertTrue((metric["notes"] as? String)?.contains("workouts with this measurement") == true)
                        }
                    }
                    XCTAssertEqual(metrics.contains { $0["key"] as? String == "workout_minutes" }, visibleDuration)
                    for item in ranges where item.format != .json {
                        let text = String(decoding: item.artifact.inlineData, as: UTF8.self)
                        XCTAssertTrue(text.contains(item.format == .csv ? "healthmd.rollup_summary,11,healthmd.health_data,11,12," : "rollup_rules_version: 12"))
                    }
                    if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_WORKOUT_RANGE_FIXTURE_DIR"], !directory.isEmpty {
                        let variant = "apple-v11-workout-range-\(preference.rawValue)-\(visibleDuration)-\(summaryOnly)"
                        for item in operation.artifacts {
                            let output = URL(fileURLWithPath: directory).appendingPathComponent(variant).appendingPathComponent(item.artifact.relativePath)
                            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try item.artifact.inlineData.write(to: output)
                        }
                    }
                }
            }
        }
    }

    func testWorkoutRangePinsResumeOnlyUnderTheirExactRegistryAndKeepVersionTwoAvailable() async throws {
        let executor = SystemAppleLooseDailyCoreExecutor()
        let oldContext = try await executor.loadContext(profile: .appleHealthDataV11)
        let newContext = try await executor.loadContext(profile: .appleHealthDataV11, expectedRegistryVersion: 3)
        XCTAssertEqual(oldContext.registry.registryVersion, 2)
        XCTAssertEqual(newContext.registry.registryVersion, 3)
        let oldPin = try AppleExportEnginePin(engine: .rust, calendarTimeZoneIdentifier: "UTC",
            buildInfo: oldContext.buildInfo, registrySnapshot: oldContext.registry)
        let newPin = try AppleExportEnginePin(engine: .rust, calendarTimeZoneIdentifier: "UTC",
            buildInfo: newContext.buildInfo, registrySnapshot: newContext.registry)
        XCTAssertTrue(oldPin.hasExplicitWakeDateContracts)
        XCTAssertTrue(newPin.hasExplicitWakeDateContracts)
        XCTAssertNoThrow(try oldPin.validateCompatibility(buildInfo: oldContext.buildInfo, registrySnapshot: oldContext.registry))
        XCTAssertNoThrow(try newPin.validateCompatibility(buildInfo: newContext.buildInfo, registrySnapshot: newContext.registry))
        XCTAssertThrowsError(try oldPin.validateCompatibility(buildInfo: newContext.buildInfo, registrySnapshot: newContext.registry))
        XCTAssertThrowsError(try newPin.validateCompatibility(buildInfo: oldContext.buildInfo, registrySnapshot: oldContext.registry))
        let recovered = try JSONDecoder().decode(AppleExportEnginePin.self, from: JSONEncoder().encode(newPin))
        XCTAssertEqual(recovered, newPin)
        XCTAssertTrue(recovered.hasExplicitWakeDateContracts)
        XCTAssertFalse(AppleExportEnginePin.isSupportedWakeDateRegistry(version: 3, sha256: oldPin.registrySHA256))
        XCTAssertFalse(AppleExportEnginePin.isSupportedWakeDateRegistry(version: 2, sha256: newPin.registrySHA256))
    }

    func testRegistryTwoWorkoutRangeDoesNotPublishUnqualifiedExtremaRules() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let date = ExportFixtures.referenceDate
        let day = HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            workouts: [WorkoutData(workoutType: .running, startTime: date, duration: 1800.5,
                calories: 320.125, distance: 5000.875, maxHeartRate: 179.875, minHeartRate: 91.125, maxPower: 312.875)])
        let snapshot = try acceptedSnapshot(context: context, formats: Set(ExportFormat.allCases),
            selectionIDs: ["workouts"], rangeSummary: true)
        do {
            _ = try await AppleLooseDailyExportPlanner().planRange(healthData: [day],
                settingsSnapshot: snapshot, surface: .localVaultRangeWithoutSideEffects)
            XCTFail("Registry 2's original sum folds must not become newly approved workout maxima/minima")
        } catch {
            XCTAssertEqual(error as? AppleLooseDailyExportPlannerError, .rustPlanningFailed)
        }
    }

    private func acceptedSnapshot(
        context: AppleSleepCaptureContext, formats: Set<ExportFormat>, selectionIDs: Set<String>? = nil,
        rangeSummary: Bool = false, unitPreference: UnitPreference = .metric, registryVersion: UInt32 = 2
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
            "registry_version": registryVersion, "registry_sha256": registryVersion == 3
                ? HealthMdWorkoutRangeRegistryContract.registrySHA256 : HealthMdSleepProfileContract.registrySHA256,
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
        XCTAssertNoThrow(try context.requireShippedProfile())
    }
}
