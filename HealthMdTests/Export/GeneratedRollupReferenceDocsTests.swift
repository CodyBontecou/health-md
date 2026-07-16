import CryptoKit
import Foundation
import XCTest
@testable import HealthMd

#if os(macOS)
final class GeneratedRollupReferenceDocsTests: XCTestCase {
    @MainActor
    func testGeneratedRollupReferenceDocsMatchProductionOutput() throws {
        let artifacts = try GeneratedRollupReferenceDocs.makeArtifacts()
        let environment = ProcessInfo.processInfo.environment
        let updateMarker = Self.repositoryRoot
            .appendingPathComponent("HealthMdTests/.update-generated-rollup-reference-docs")
        let shouldUpdate = environment["UPDATE_GENERATED_ROLLUP_REFERENCE_DOCS"] == "1"
            || FileManager.default.fileExists(atPath: updateMarker.path)

        if shouldUpdate {
            let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent(GeneratedRollupReferenceDocs.updateOutputDirectoryName, isDirectory: true)
            try GeneratedRollupReferenceDocs.write(artifacts, to: outputDirectory)
            return
        }

        let committedDirectory = Self.repositoryRoot
            .appendingPathComponent("docs/reference/generated/rollups", isDirectory: true)
        let fileManager = FileManager.default
        let expectedNames = artifacts.keys.sorted()
        let committedNames = try fileManager.contentsOfDirectory(
            at: committedDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        .map(\.lastPathComponent)
        .sorted()

        XCTAssertEqual(committedNames, expectedNames, """
        Generated roll-up reference artifact inventory drifted.
        Run: scripts/generated-rollup-reference-docs.sh update
        """)

        for name in expectedNames {
            let generated = try XCTUnwrap(artifacts[name])
            let committedURL = committedDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: committedURL.path) else { continue }
            let committed = try Data(contentsOf: committedURL)
            XCTAssertEqual(
                committed,
                generated,
                """
                Generated roll-up reference drifted: docs/reference/generated/rollups/\(name)
                committed sha256: \(Self.sha256(committed))
                generated sha256: \(Self.sha256(generated))
                Run: scripts/generated-rollup-reference-docs.sh update
                """
            )
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Export
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // repository root
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private enum GeneratedRollupReferenceDocs {
    static let updateOutputDirectoryName = "healthmd-generated-rollup-reference-docs-current"

    private static let generatedAt = utcDate(2026, 7, 13, hour: 12)
    private static let selectedMetricIDs: Set<String> = [
        "heart_rate_avg",
        "heart_rate_max",
        "heart_rate_min",
        "menstrual_flow",
        "sleep_bedtime",
        "sleep_total",
        "sleep_wake",
        "steps",
        "vo2_max",
        "weight",
        "workouts"
    ]

    private static let behaviorEvidence: [BehaviorEvidence] = [
        .init(label: "sum", dailyAggregation: "sum", primary: "sum", key: "steps"),
        .init(label: "duration sum", dailyAggregation: "duration_sum", primary: "sum", key: "sleep_total_hours"),
        .init(label: "count", dailyAggregation: "count", primary: "sum", key: "workout_count"),
        .init(label: "average", dailyAggregation: "average", primary: "average", key: "average_heart_rate"),
        .init(label: "weighted average", dailyAggregation: "weighted_average", primary: "weighted_average", key: "workout_avg_heart_rate"),
        .init(label: "minimum", dailyAggregation: "minimum", primary: "minimum", key: "heart_rate_min"),
        .init(label: "maximum", dailyAggregation: "maximum", primary: "maximum", key: "heart_rate_max"),
        .init(label: "latest numeric", dailyAggregation: "latest", primary: "latest", key: "weight_kg"),
        .init(label: "latest identity", dailyAggregation: "latest", primary: "latest", key: "vo2_max_source_uuid"),
        .init(label: "list union and value counts", dailyAggregation: "list", primary: "union", key: "workouts"),
        .init(label: "category histogram", dailyAggregation: "category_latest", primary: "histogram", key: "menstrual_flow"),
        .init(label: "first time", dailyAggregation: "first_time", primary: "time_of_day", key: "sleep_bedtime"),
        .init(label: "last time", dailyAggregation: "last_time", primary: "time_of_day", key: "sleep_wake")
    ]

    static func makeArtifacts() throws -> [String: Data] {
        let settings = makeSettings()
        let dictionaryEntries = HealthMetricDataDictionary.entries(using: settings.formatCustomization)
        let snapshots = HealthRollupGenerator.generate(
            from: syntheticDailySummaries(),
            settings: settings,
            periods: [.weekly],
            generatedAt: generatedAt,
            calendar: utcCalendar
        )
        guard snapshots.count == 1, let snapshot = snapshots.first else {
            throw GenerationError.invalidFixture("Expected exactly one weekly roll-up; generated \(snapshots.count).")
        }

        try validate(snapshot: snapshot, dictionaryEntries: dictionaryEntries)

        var artifacts: [String: Data] = [
            "aggregation-behavior.md": Data(aggregationBehaviorMatrix(
                entries: dictionaryEntries,
                snapshot: snapshot
            ).utf8),
            "weekly-bases.md": Data(snapshot.toRollupObsidianBases().utf8),
            "weekly.csv": Data(snapshot.toRollupCSV().utf8),
            "weekly.json": Data(snapshot.toRollupJSON().utf8),
            "weekly.md": Data(snapshot.toRollupMarkdown().utf8)
        ]
        artifacts["manifest.json"] = Data(manifest(for: artifacts, snapshot: snapshot, entryCount: dictionaryEntries.count).utf8)
        return artifacts
    }

    static func write(_ artifacts: [String: Data], to outputDirectory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.removeItem(at: outputDirectory)
        }
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, data) in artifacts {
            try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
        }
    }

    private static func makeSettings() -> AdvancedExportSettings {
        let suiteName = "healthmd.tests.generated-rollup-reference-docs"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.metricSelection.enabledMetrics = selectedMetricIDs
        settings.metricSelection.enabledCategories = []
        settings.formatCustomization.unitPreference = .metric
        settings.formatCustomization.timeFormat = .hour24
        settings.formatCustomization.dateFormat = .iso8601
        return LifecycleHarness.retain(settings)
    }

    private static func syntheticDailySummaries() -> [HealthData] {
        [
            makeDay(
                day: 6,
                bedtimeHour: 22,
                bedtimeMinute: 30,
                wakeHour: 6,
                wakeMinute: 30,
                sleepHours: 8,
                steps: 4_000,
                averageHeartRate: 70,
                minimumHeartRate: 50,
                maximumHeartRate: 160,
                weightKg: 70.4,
                vo2Max: 42.1,
                vo2SourceUUID: "00000000-0000-0000-0000-000000000006",
                menstrualFlow: "light",
                workoutID: "10000000-0000-0000-0000-000000000006",
                workoutType: .running,
                workoutMinutes: 30,
                workoutCalories: 240,
                workoutDistanceMeters: 5_000,
                workoutAverageHeartRate: 100,
                workoutMinimumHeartRate: 90,
                workoutMaximumHeartRate: 160
            ),
            makeDay(
                day: 8,
                bedtimeHour: 23,
                bedtimeMinute: 15,
                wakeHour: 7,
                wakeMinute: 0,
                sleepHours: 7.75,
                steps: 7_500,
                averageHeartRate: nil,
                minimumHeartRate: 48,
                maximumHeartRate: 175,
                weightKg: nil,
                vo2Max: nil,
                vo2SourceUUID: nil,
                menstrualFlow: "medium",
                workoutID: "10000000-0000-0000-0000-000000000008",
                workoutType: .cycling,
                workoutMinutes: 60,
                workoutCalories: 510,
                workoutDistanceMeters: 24_000,
                workoutAverageHeartRate: 140,
                workoutMinimumHeartRate: 100,
                workoutMaximumHeartRate: 175
            ),
            makeDay(
                day: 11,
                bedtimeHour: 21,
                bedtimeMinute: 45,
                wakeHour: 6,
                wakeMinute: 0,
                sleepHours: 8.25,
                steps: 6_000,
                averageHeartRate: 76,
                minimumHeartRate: 52,
                maximumHeartRate: 165,
                weightKg: 69.8,
                vo2Max: 43.2,
                vo2SourceUUID: "00000000-0000-0000-0000-000000000011",
                menstrualFlow: "light",
                workoutID: "10000000-0000-0000-0000-000000000011",
                workoutType: .running,
                workoutMinutes: 15,
                workoutCalories: 130,
                workoutDistanceMeters: 2_500,
                workoutAverageHeartRate: 120,
                workoutMinimumHeartRate: 95,
                workoutMaximumHeartRate: 165
            )
        ]
    }

    private static func makeDay(
        day: Int,
        bedtimeHour: Int,
        bedtimeMinute: Int,
        wakeHour: Int,
        wakeMinute: Int,
        sleepHours: Double,
        steps: Int,
        averageHeartRate: Double?,
        minimumHeartRate: Double,
        maximumHeartRate: Double,
        weightKg: Double?,
        vo2Max: Double?,
        vo2SourceUUID: String?,
        menstrualFlow: String,
        workoutID: String,
        workoutType: WorkoutType,
        workoutMinutes: Double,
        workoutCalories: Double,
        workoutDistanceMeters: Double,
        workoutAverageHeartRate: Double,
        workoutMinimumHeartRate: Double,
        workoutMaximumHeartRate: Double
    ) -> HealthData {
        let date = utcDate(2026, 7, day, hour: 12)
        let bedtime = utcDate(2026, 7, day, hour: bedtimeHour, minute: bedtimeMinute)
        let wake = utcCalendar.date(byAdding: .day, value: 1, to: utcDate(
            2026,
            7,
            day,
            hour: wakeHour,
            minute: wakeMinute
        ))!
        var data = HealthData(
            date: date,
            timeContext: ExportTimeContext(timeZone: utcTimeZone)
        )
        data.sleep = SleepData(
            totalDuration: sleepHours * 3_600,
            sessionStart: bedtime,
            sessionEnd: wake
        )
        data.activity.steps = steps
        data.activity.vo2Max = vo2Max
        data.activity.vo2MaxSourceUUID = vo2SourceUUID.flatMap(UUID.init(uuidString:))
        data.activity.vo2MaxSourceStartDate = vo2Max.map { _ in date.addingTimeInterval(-3_600) }
        data.activity.vo2MaxSourceEndDate = vo2Max.map { _ in date.addingTimeInterval(-3_540) }
        data.activity.vo2MaxCarriedForward = vo2Max.map { _ in day == 11 }
        data.activity.vo2MaxAgeSeconds = vo2Max.map { _ in day == 11 ? 172_800 : 0 }
        data.heart.averageHeartRate = averageHeartRate
        data.heart.heartRateMin = minimumHeartRate
        data.heart.heartRateMax = maximumHeartRate
        data.body.weight = weightKg
        data.reproductiveHealth.menstrualFlow = menstrualFlow
        data.workouts = [
            WorkoutData(
                id: UUID(uuidString: workoutID)!,
                workoutType: workoutType,
                healthKitActivityType: workoutType.healthKitActivityTypeName,
                startTime: date.addingTimeInterval(3_600),
                actualEndDate: date.addingTimeInterval(3_600 + workoutMinutes * 60),
                duration: workoutMinutes * 60,
                calories: workoutCalories,
                distance: workoutDistanceMeters,
                avgHeartRate: workoutAverageHeartRate,
                maxHeartRate: workoutMaximumHeartRate,
                minHeartRate: workoutMinimumHeartRate
            )
        ]
        return data
    }

    private static func validate(
        snapshot: RollupDataSnapshot,
        dictionaryEntries: [HealthMetricDataDictionaryEntry]
    ) throws {
        guard snapshot.period == .weekly,
              snapshot.periodID == "2026-W28",
              snapshot.daysExpected == 7,
              snapshot.daysCounted == 3,
              abs(snapshot.coveragePercent - (300.0 / 7.0)) < 0.000_001 else {
            throw GenerationError.invalidFixture("Weekly fixture must expose three of seven UTC source days and partial coverage.")
        }

        let entriesByKey = Dictionary(uniqueKeysWithValues: dictionaryEntries.map { ($0.key, $0) })
        let summariesByKey = Dictionary(uniqueKeysWithValues: snapshot.metrics.map { ($0.key, $0) })
        for evidence in behaviorEvidence {
            guard let entry = entriesByKey[evidence.key] else {
                throw GenerationError.invalidFixture("Behavior evidence key is absent from the data dictionary: \(evidence.key).")
            }
            guard entry.dailyAggregation == evidence.dailyAggregation,
                  entry.rollup.primary == evidence.primary else {
                throw GenerationError.invalidFixture(
                    "Behavior evidence \(evidence.key) expected \(evidence.dailyAggregation) → \(evidence.primary), " +
                    "found \(entry.dailyAggregation) → \(entry.rollup.primary)."
                )
            }
            guard let summary = summariesByKey[evidence.key], summary.rule == evidence.primary else {
                throw GenerationError.invalidFixture("Synthetic summaries did not generate \(evidence.label) evidence at \(evidence.key).")
            }
        }

        let dictionaryPrimaryRules = Set(dictionaryEntries.map { $0.rollup.primary })
        let fixturePrimaryRules = Set(snapshot.metrics.map(\.rule))
        let missingRules = dictionaryPrimaryRules.subtracting(fixturePrimaryRules).sorted()
        guard missingRules.isEmpty else {
            throw GenerationError.invalidFixture(
                "Synthetic summaries do not exercise every HealthMetricRollupRule primary behavior: \(missingRules.joined(separator: ", "))."
            )
        }

        guard summariesByKey["average_heart_rate"]?.daysCounted == 2,
              summariesByKey["weight_kg"]?.daysCounted == 2 else {
            throw GenerationError.invalidFixture("Fixture must expose missing per-metric daily values independently of period coverage.")
        }
    }

    private static func aggregationBehaviorMatrix(
        entries: [HealthMetricDataDictionaryEntry],
        snapshot: RollupDataSnapshot
    ) -> String {
        let groups = Dictionary(grouping: entries) { MatrixGroupKey(entry: $0) }
        let generatedKeys = Set(snapshot.metrics.map(\.key))
        let sortedGroups = groups.keys.sorted()

        var lines = [
            "# Health.md roll-up aggregation behavior matrix",
            "",
            "Generated deterministically from production `HealthMetricDataDictionary.entries(using:)` at schema v\(HealthMdExportSchema.version).",
            "The weekly evidence is fixed synthetic UTC data, contains no PHI, and is rendered by the production roll-up generator and exporters.",
            "",
            "- Dictionary entries: \(entries.count)",
            "- Distinct rule groups: \(sortedGroups.count)",
            "- Primary behaviors: \(Set(entries.map { $0.rollup.primary }).sorted().joined(separator: ", "))",
            "- Evidence period: `\(snapshot.periodID)` with \(snapshot.daysCounted)/\(snapshot.daysExpected) source days (\(HealthRollupFormatting.number(snapshot.coveragePercent))% coverage)",
            "",
            "| Daily aggregation | Roll-up primary | Period behavior | Statistics | Preferred source | Weighted by | Null handling | Periods | Generated example keys | All dictionary keys |",
            "|---|---|---|---|---|---|---|---|---|---|"
        ]

        for group in sortedGroups {
            let groupEntries = (groups[group] ?? []).sorted { $0.key < $1.key }
            let allKeys = groupEntries.map(\.key)
            let examples = allKeys.filter { generatedKeys.contains($0) }
            lines.append([
                group.dailyAggregation,
                group.primary,
                behaviorDescription(for: group.primary),
                group.statistics.joined(separator: "<br>"),
                group.preferredSource,
                group.weightedBy ?? "none",
                group.nullHandling,
                group.periods.joined(separator: "<br>"),
                examples.isEmpty ? "none in weekly example" : examples.joined(separator: "<br>"),
                allKeys.joined(separator: "<br>")
            ].map(markdownCell).joined(separator: " | ").withTableEdges)
        }

        lines.append("")
        lines.append("## Required weekly evidence")
        lines.append("")
        lines.append("| Behavior | Dictionary rule | Generated key |")
        lines.append("|---|---|---|")
        for evidence in behaviorEvidence {
            lines.append("| \(markdownCell(evidence.label)) | `\(evidence.dailyAggregation)` → `\(evidence.primary)` | `\(evidence.key)` |")
        }
        lines.append("")
        lines.append("Missing calendar days are represented by the 3/7 period coverage. Missing metric values are represented by `average_heart_rate` and `weight_kg`, each with 2 metric days counted.")
        lines.append("")
        lines.append("## Metric, path, and type inventory")
        lines.append("")
        lines.append("Every row below comes from `HealthMetricDataDictionary.entries(using:)`. Roll-up `primary_value` and statistic values are strings, while `days_counted` is an integer.")
        lines.append("")
        lines.append("| Key | Canonical key | Metric ID | Display name | Category | Metric type | Unit | HealthKit identifier | Daily aggregation | Roll-up primary | JSON paths | CSV path | Markdown path | Bases path |")
        lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for entry in entries.sorted(by: { $0.key < $1.key }) {
            let paths = [
                "`$.metrics[?(@.key == \"\(entry.key)\")]`",
                "`$.categories[\"\(entry.category)\"][?(@.key == \"\(entry.key)\")]`"
            ].joined(separator: "<br>")
            lines.append([
                "`\(entry.key)`",
                "`\(entry.canonicalKey)`",
                "`\(entry.metricId)`",
                entry.displayName,
                entry.category,
                entry.metricType,
                entry.unit.isEmpty ? "none" : entry.unit,
                entry.healthKitIdentifier.map { "`\($0)`" } ?? "none",
                "`\(entry.dailyAggregation)`",
                "`\(entry.rollup.primary)`",
                paths,
                "`rows[Key=\(entry.key)]`",
                "`## \(entry.category) / Key=\(entry.key)`",
                "`$.rollup_metrics.\(entry.key)`"
            ].map(markdownCell).joined(separator: " | ").withTableEdges)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func behaviorDescription(for primary: String) -> String {
        switch primary {
        case "sum": return "Sum numeric daily values; report daily average, minimum, maximum, and days counted when declared."
        case "average": return "Average numeric daily values with data; preserve trend statistics declared by the rule."
        case "weighted_average": return "Weight daily workout values by exported workout minutes; fall back to equal weights when needed."
        case "minimum": return "Use the minimum numeric daily value."
        case "maximum": return "Use the maximum numeric daily value."
        case "latest": return "Use the value from the latest source day; numeric values retain declared trend statistics."
        case "union": return "Union list items in sorted order and count item occurrences across source days."
        case "histogram": return "Keep the latest category and count each category value across source days."
        case "time_of_day": return "Report earliest, latest, and average clock time without combining calendar dates."
        default: return "Apply the production generator fallback for this declared primary behavior."
        }
    }

    private static func manifest(
        for artifacts: [String: Data],
        snapshot: RollupDataSnapshot,
        entryCount: Int
    ) -> String {
        let sourceDates = snapshot.sourceDates.sorted().map(HealthRollupDateFormatting.dayString)
        let allPeriodDates = (0..<snapshot.daysExpected).compactMap { offset in
            utcCalendar.date(byAdding: .day, value: offset, to: snapshot.window.startDate)
        }.map(HealthRollupDateFormatting.dayString)
        let missingDates = allPeriodDates.filter { !Set(sourceDates).contains($0) }

        let payload: [String: Any] = [
            "artifact_set": "healthmd.generated_rollup_reference_docs",
            "manifest_version": 1,
            "generated_at": HealthRollupDateFormatting.timestampString(generatedAt),
            "generator": [
                "test": "HealthMdTests/Export/GeneratedRollupReferenceDocsTests.swift",
                "script": "scripts/generated-rollup-reference-docs.sh",
                "production_types": [
                    "HealthRollupGenerator",
                    "RollupDataSnapshot",
                    "RollupJSONExporter",
                    "RollupCSVExporter",
                    "RollupMarkdownExporter",
                    "RollupObsidianBasesExporter",
                    "HealthMetricDataDictionary.entries(using:)"
                ]
            ],
            "schema": [
                "rollup": HealthRollupExportSchema.identifier,
                "source": HealthMdExportSchema.identifier,
                "source_version": HealthMdExportSchema.version,
                "data_dictionary_entry_count": entryCount
            ],
            "fixture": [
                "synthetic": true,
                "contains_phi": false,
                "timezone": "UTC",
                "period": snapshot.period.rawValue,
                "period_id": snapshot.periodID,
                "start_date": HealthRollupDateFormatting.dayString(snapshot.window.startDate),
                "end_date": HealthRollupDateFormatting.dayString(snapshot.window.endDate),
                "days_expected": snapshot.daysExpected,
                "days_counted": snapshot.daysCounted,
                "coverage_percent": snapshot.coveragePercent,
                "source_dates": sourceDates,
                "missing_dates": missingDates,
                "behavior_evidence": behaviorEvidence.map { evidence in
                    [
                        "label": evidence.label,
                        "daily_aggregation": evidence.dailyAggregation,
                        "rollup_primary": evidence.primary,
                        "key": evidence.key
                    ]
                }
            ],
            "artifacts": artifacts.keys.sorted().map { name -> [String: Any] in
                let data = artifacts[name]!
                return [
                    "path": name,
                    "bytes": data.count,
                    "sha256": sha256(data)
                ]
            }
        ]
        return prettyJSON(payload)
    }

    private static func prettyJSON(_ object: Any) -> String {
        let data = try! JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func markdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static var utcTimeZone: TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = utcTimeZone
        return calendar
    }

    private static func utcDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        utcCalendar.date(from: DateComponents(
            calendar: utcCalendar,
            timeZone: utcTimeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ))!
    }
}

private struct BehaviorEvidence {
    let label: String
    let dailyAggregation: String
    let primary: String
    let key: String
}

private struct MatrixGroupKey: Hashable, Comparable {
    let dailyAggregation: String
    let primary: String
    let statistics: [String]
    let periods: [String]
    let preferredSource: String
    let nullHandling: String
    let weightedBy: String?
    let notes: String?

    init(entry: HealthMetricDataDictionaryEntry) {
        dailyAggregation = entry.dailyAggregation
        primary = entry.rollup.primary
        statistics = entry.rollup.statistics
        periods = entry.rollup.periods
        preferredSource = entry.rollup.preferredSource
        nullHandling = entry.rollup.nullHandling
        weightedBy = entry.rollup.weightedBy
        notes = entry.rollup.notes
    }

    static func < (lhs: MatrixGroupKey, rhs: MatrixGroupKey) -> Bool {
        let left = [
            lhs.dailyAggregation,
            lhs.primary,
            lhs.statistics.joined(separator: ","),
            lhs.preferredSource,
            lhs.weightedBy ?? "",
            lhs.nullHandling,
            lhs.periods.joined(separator: ","),
            lhs.notes ?? ""
        ]
        let right = [
            rhs.dailyAggregation,
            rhs.primary,
            rhs.statistics.joined(separator: ","),
            rhs.preferredSource,
            rhs.weightedBy ?? "",
            rhs.nullHandling,
            rhs.periods.joined(separator: ","),
            rhs.notes ?? ""
        ]
        return left.lexicographicallyPrecedes(right)
    }
}

private enum GenerationError: LocalizedError {
    case invalidFixture(String)

    var errorDescription: String? {
        switch self {
        case .invalidFixture(let message): return message
        }
    }
}

private extension String {
    var withTableEdges: String { "| \(self) |" }
}
#endif
