import XCTest
@testable import HealthMd

/// #353: in "Morning ends" Bases notes each native frontmatter block follows the Format → Custom
/// switches of the fields that own its records. The records stay in the body formats. Android
/// applies the same table in `HealthMdRenderInputAdapter.kt`.
final class WakeDateNativeFrontmatterOwnershipTests: XCTestCase {
    private let owner = ExportFixtures.referenceDate
    private let context = AppleSleepCaptureContext(timeZone: .gmt, sleepDayAttribution: .morningEnds)

    private func frontmatter(_ write: (ExportByteSink) throws -> Void) rethrows -> String {
        let sink = MemoryExportByteSink(mediaType: "text/markdown")
        try write(sink)
        return String(decoding: sink.data, as: UTF8.self)
    }

    private func allOn(_: String) -> Bool { true }
    private func off(_ keys: [String]) -> (String) -> Bool { { !keys.contains($0) } }

    private var workoutKeys: [String] {
        FrontmatterConfiguration.defaultFields.map(\.originalKey).filter(WakeDateNativeFrontmatterOwners.isWorkoutField)
    }

    /// The workout rule picks exactly the Workouts group: the "workouts" metric's keys plus
    /// `workout_details`, and no field from another group.
    func testWorkoutRuleMatchesTheWorkoutsGroup() {
        XCTAssertEqual(Set(workoutKeys), Set(HealthMetricExportMapping.frontmatterKeys(for: "workouts") + ["workout_details"]))
        XCTAssertEqual(Set(workoutKeys.map(FrontmatterFieldGroup.group(for:))), [.workouts])
    }

    /// A workout field added later owns the block without an edit to the owner table.
    func testANewWorkoutFieldOwnsTheBlockAutomatically() {
        let keys = workoutKeys + ["workout_future_metric"]
        XCTAssertTrue(WakeDateNativeFrontmatterOwners.showsWorkouts(fieldKeys: keys) { $0 == "workout_future_metric" })
        XCTAssertFalse(WakeDateNativeFrontmatterOwners.showsWorkouts(fieldKeys: keys) { _ in false })
        // Keys from other groups never own it.
        XCTAssertFalse(WakeDateNativeFrontmatterOwners.showsWorkouts(fieldKeys: ["steps", "active_calories"]) { _ in true })
    }

    /// Apple and Android tables share packages/contracts/sleep-attribution/v1/native-frontmatter-owners.json.
    func testOwnerTablesMatchTheSharedContractAndNameRealFields() throws {
        let contract = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("packages/contracts/sleep-attribution/v1/native-frontmatter-owners.json")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: contract)) as? [String: Any])
        let shared = try XCTUnwrap(root["shared"] as? [String: Any])
        let apple = try XCTUnwrap(root["apple"] as? [String: Any])
        XCTAssertEqual(shared["quantity"] as? [String: [String]], WakeDateNativeFrontmatterOwners.quantity)
        XCTAssertEqual(shared["correlation"] as? [String], WakeDateNativeFrontmatterOwners.correlation)
        XCTAssertEqual(apple["sleep_stage"] as? [String: String], WakeDateNativeFrontmatterOwners.sleepStage)
        XCTAssertEqual(apple["mindfulness"] as? [String], WakeDateNativeFrontmatterOwners.mindfulness)
        XCTAssertEqual(apple["workouts"] as? [String], ["workouts", "workout_*"])

        // Every owner is a field Format → Custom lists, so its switch exists.
        let listed = Set(FrontmatterConfiguration.defaultFields.map(\.originalKey))
        let owners = WakeDateNativeFrontmatterOwners.quantity.values.flatMap { $0 } + WakeDateNativeFrontmatterOwners.correlation
            + Array(WakeDateNativeFrontmatterOwners.sleepStage.values) + WakeDateNativeFrontmatterOwners.mindfulness
            + workoutKeys
        XCTAssertEqual(Set(owners).subtracting(listed), [])
    }

    func testQuantityLinesFollowEachSeriesOwners() throws {
        var data = HealthData(date: owner)
        data.heart.heartRateSamples = [TimeSample(timestamp: owner, value: 61.5)]
        data.vitals.bloodOxygenSamples = [TimeSample(timestamp: owner, value: 0.75)]
        let heartRate = WakeDateNativeFrontmatterOwners.quantity["heartRateSamples"]!

        let shown = AppleWakeDateQuantityProjection(data: data, isFrontmatterFieldEnabled: allOn)
        let text = try frontmatter(shown.writeFrontmatterBlock)
        XCTAssertTrue(text.contains("native_quantity_details:"))
        XCTAssertTrue(text.contains("61.5"))
        XCTAssertTrue(text.contains("0.75"))

        // One heart rate field still on keeps the series.
        let oneOn = AppleWakeDateQuantityProjection(data: data, isFrontmatterFieldEnabled: off(Array(heartRate.dropFirst())))
        XCTAssertTrue(try frontmatter(oneOn.writeFrontmatterBlock).contains("61.5"))

        // Every heart rate field off drops only the heart rate lines.
        let heartOff = AppleWakeDateQuantityProjection(data: data, isFrontmatterFieldEnabled: off(heartRate))
        let partial = try frontmatter(heartOff.writeFrontmatterBlock)
        XCTAssertFalse(partial.contains("61.5"))
        XCTAssertTrue(partial.contains("0.75"))

        // Every owner off drops the block; the records stay for JSON, CSV and the body.
        let allOff = AppleWakeDateQuantityProjection(data: data, isFrontmatterFieldEnabled: { _ in false })
        XCTAssertFalse(allOff.writesFrontmatterBlock)
        XCTAssertEqual(try frontmatter(allOff.writeFrontmatterBlock), "")
        XCTAssertTrue(allOff.hasRecords)
        XCTAssertTrue(try frontmatter { try allOff.writeMarkdown(headerPrefix: "##", to: $0) }.contains("61.5"))
    }

    func testSleepStageLinesFollowTheirStageField() throws {
        var data = HealthData(date: owner)
        data.sleep.sessionStart = owner
        data.sleep.sessionEnd = owner.addingTimeInterval(3600)
        data.sleep.stages = [
            SleepStageSample(stage: "deep", startDate: owner, endDate: owner.addingTimeInterval(600)),
            SleepStageSample(stage: "rem", startDate: owner.addingTimeInterval(600), endDate: owner.addingTimeInterval(1200)),
        ]
        let shown = try frontmatter(AppleWakeDateSleepStageProjection(data: data, isFrontmatterFieldEnabled: allOn).writeFrontmatterBlock)
        XCTAssertTrue(shown.contains("\"stage\":\"deep\""))
        XCTAssertTrue(shown.contains("\"stage\":\"rem\""))

        let deepOff = try frontmatter(AppleWakeDateSleepStageProjection(data: data,
            isFrontmatterFieldEnabled: off(["sleep_deep_hours"])).writeFrontmatterBlock)
        XCTAssertTrue(deepOff.contains("sleep_stage_details:"))
        XCTAssertFalse(deepOff.contains("\"stage\":\"deep\""))
        XCTAssertTrue(deepOff.contains("\"stage\":\"rem\""))

        let bothOff = AppleWakeDateSleepStageProjection(data: data,
            isFrontmatterFieldEnabled: off(["sleep_deep_hours", "sleep_rem_hours"]))
        XCTAssertFalse(bothOff.writesFrontmatterBlock)
        XCTAssertEqual(try frontmatter(bothOff.writeFrontmatterBlock), "")
    }

    func testBloodPressurePairNeedsBothFields() throws {
        var data = HealthData(date: owner)
        data.vitals.bloodPressureSamples = [BloodPressureSample(systolic: 118, diastolic: 76, startDate: owner, endDate: owner)]
        XCTAssertTrue(try frontmatter(AppleWakeDateCorrelationProjection(data: data, isFrontmatterFieldEnabled: allOn)
            .writeFrontmatterBlock).contains("native_correlation_details:"))
        for key in WakeDateNativeFrontmatterOwners.correlation {
            let projection = AppleWakeDateCorrelationProjection(data: data, isFrontmatterFieldEnabled: off([key]))
            XCTAssertFalse(projection.writesFrontmatterBlock, key)
            XCTAssertEqual(try frontmatter(projection.writeFrontmatterBlock), "", key)
            XCTAssertTrue(try frontmatter { try projection.writeMarkdown(headerPrefix: "##", to: $0) }.contains("118"))
        }
    }

    func testMindfulnessAndWorkoutBlocksShowWhileAnyOwnerIsOn() {
        var data = HealthData(date: owner)
        data.workouts = [WorkoutData(workoutType: .running, startTime: owner, duration: 1800, calories: nil, distance: nil)]
        data.mindfulness.stateOfMind = [StateOfMindEntry(timestamp: owner, kind: .dailyMood, valence: 0.5,
            labels: [], associations: [], metadata: [:])]
        let selected: Set<String> = ["workout_count", "mood_entries"]
        func workouts(_ enabled: @escaping (String) -> Bool) -> AppleWakeDateWorkoutProjection {
            AppleWakeDateWorkoutProjection(data: data, captureContext: context, timeFormatIdentifier: TimeFormatPreference.hour24.rawValue,
                selectedOutputKeys: selected, frontmatterFieldKeys: workoutKeys, isFrontmatterFieldEnabled: enabled)
        }
        func mood(_ enabled: @escaping (String) -> Bool) -> AppleWakeDateMindfulnessProjection {
            AppleWakeDateMindfulnessProjection(data: data, captureContext: context, timeFormatIdentifier: TimeFormatPreference.hour24.rawValue,
                selectedOutputKeys: selected, isFrontmatterFieldEnabled: enabled)
        }
        // One rule on both platforms: any Workouts field on keeps the block; all off drops it.
        XCTAssertTrue(workouts(allOn).writesFrontmatterBlock)
        XCTAssertTrue(workouts(off(["workout_details"])).writesFrontmatterBlock)
        XCTAssertTrue(workouts(off(workoutKeys.filter { $0 != "workout_count" })).writesFrontmatterBlock)
        XCTAssertFalse(workouts(off(workoutKeys)).writesFrontmatterBlock)
        XCTAssertTrue(workouts(off(workoutKeys)).hasRecords)

        XCTAssertTrue(mood(allOn).writesFrontmatterBlock)
        XCTAssertTrue(mood(off(["mood_entries", "mood_labels"])).writesFrontmatterBlock)
        XCTAssertFalse(mood(off(WakeDateNativeFrontmatterOwners.mindfulness)).writesFrontmatterBlock)
    }
}
