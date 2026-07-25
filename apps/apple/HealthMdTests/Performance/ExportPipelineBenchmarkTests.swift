import XCTest
@testable import HealthMd

@MainActor
final class ExportPipelineBenchmarkTests: XCTestCase {
    func testRepresentativeOneThirtyAndYearSerializationBaselines() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HEALTHMD_RUN_EXPORT_BENCHMARKS"] == "1",
            "Set HEALTHMD_RUN_EXPORT_BENCHMARKS=1 in the test action to run export baselines."
        )

        let suiteName = "ExportPipelineBenchmarkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = Set(ExportFormat.allCases)

        let calendar = Calendar(identifier: .gregorian)
        let endDate = calendar.startOfDay(for: Date())
        let records = (0..<365).map { offset in
            representativeRecord(
                date: calendar.date(byAdding: .day, value: offset - 364, to: endDate)!
            )
        }

        for dayCount in [1, 30, 365] {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            var outputBytes = 0
            var outputFiles = 0
            for record in records.suffix(dayCount) {
                let prepared = record.preparedExport(settings: settings)
                for format in ExportFormat.allCases {
                    let content = try prepared.content(format: format, settings: settings)
                    outputBytes += content.utf8.count
                    outputFiles += 1
                }
            }
            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
            let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
            let report: [String: Any] = [
                "days": dayCount,
                "elapsed_ms": (elapsedMilliseconds * 100).rounded() / 100,
                "output_bytes": outputBytes,
                "output_files": outputFiles,
                "formats": ExportFormat.allCases.count
            ]
            let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("HEALTHMD_EXPORT_BENCHMARK \(String(decoding: reportData, as: UTF8.self))")

            XCTAssertEqual(outputFiles, dayCount * ExportFormat.allCases.count)
            XCTAssertGreaterThan(outputBytes, dayCount * 100)
        }
    }

    private func representativeRecord(date: Date) -> HealthData {
        let heartRateSamples = (0..<288).map { index in
            TimeSample(
                timestamp: date.addingTimeInterval(Double(index * 300)),
                value: 58 + Double(index % 65),
                metadata: ["source": "benchmark"]
            )
        }
        let workoutSamples = (0..<120).map { index in
            TimeSeriesSample(
                timestamp: date.addingTimeInterval(43_200 + Double(index * 5)),
                value: 120 + Double(index % 45)
            )
        }
        let sleepStart = date.addingTimeInterval(-28_800)
        let sleepEnd = date.addingTimeInterval(-1_800)

        var record = HealthData(date: date)
        record.sleep = SleepData(
            totalDuration: 27_000,
            deepSleep: 5_400,
            remSleep: 6_300,
            coreSleep: 14_400,
            awakeTime: 900,
            inBedTime: 28_800,
            sessionStart: sleepStart,
            sessionEnd: sleepEnd,
            stages: [
                SleepStageSample(stage: "core", startDate: sleepStart, endDate: sleepStart.addingTimeInterval(7_200)),
                SleepStageSample(stage: "deep", startDate: sleepStart.addingTimeInterval(7_200), endDate: sleepStart.addingTimeInterval(12_600)),
                SleepStageSample(stage: "rem", startDate: sleepStart.addingTimeInterval(12_600), endDate: sleepEnd)
            ]
        )
        record.activity.steps = 10_234
        record.activity.activeCalories = 612
        record.activity.exerciseMinutes = 54
        record.activity.walkingRunningDistance = 8_420
        record.heart.averageHeartRate = 78
        record.heart.restingHeartRate = 56
        record.heart.heartRateMin = 49
        record.heart.heartRateMax = 172
        record.heart.hrv = 48
        record.heart.heartRateSamples = heartRateSamples
        record.vitals.respiratoryRateAvg = 15.2
        record.vitals.bloodOxygenAvg = 97.4
        record.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: date.addingTimeInterval(43_200),
                duration: 1_800,
                calories: 320,
                distance: 5_000,
                avgHeartRate: 148,
                maxHeartRate: 172,
                minHeartRate: 112,
                timeSeries: WorkoutTimeSeries(heartRate: workoutSamples)
            )
        ]
        return record
    }
}
