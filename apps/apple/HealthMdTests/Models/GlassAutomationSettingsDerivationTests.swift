import XCTest
@testable import HealthMd

/// Derivations behind the glass automation settings pages: frontmatter field groups and
/// the individual entry example.
@MainActor
final class GlassAutomationSettingsDerivationTests: XCTestCase {
    func testOutputEditorsRejectUnsafePathsBeforeTheyCanBreakSetupSharing() {
        for path in ["../escape", "entries/../escape", "/absolute", "C:\\vault", "a//b", "a%2fb", "a\nb"] {
            XCTAssertNotNil(AutomationOutputPathValidation.invalidReason(folders: [path], filename: "{date}"), path)
        }
        for name in ["", "   ", ".", "..", "../escape", "a/b", "a\\b", "a%2fb", "a\nb"] {
            XCTAssertNotNil(AutomationOutputPathValidation.invalidReason(folders: ["entries"], filename: name), name)
        }
    }

    func testOutputEditorsAllowVaultRootNestedFoldersAndExistingTokens() {
        XCTAssertNil(AutomationOutputPathValidation.invalidReason(folders: ["", "Health/{year}/{month}"], filename: "{date}"))
        XCTAssertNil(AutomationOutputPathValidation.invalidReason(folders: ["entries/健康"], filename: "{date}_{time}_{metric}"))
        XCTAssertNotNil(AutomationOutputPathValidation.invalidReason(folders: ["Health", "../escape"], filename: "{date}"))
    }

    // MARK: - Frontmatter field groups

    func testEveryDefaultFieldLandsInANamedGroup() {
        let other = FrontmatterConfiguration.defaultFields
            .filter { FrontmatterFieldGroup.group(for: $0.originalKey) == .other }
            .map(\.originalKey)
        XCTAssertEqual(other, [])
    }

    func testAmbiguousPrefixesResolveToTheirOwnGroup() {
        XCTAssertEqual(FrontmatterFieldGroup.group(for: "active_medication_count"), .medications)
        XCTAssertEqual(FrontmatterFieldGroup.group(for: "active_calories"), .activity)
        XCTAssertEqual(FrontmatterFieldGroup.group(for: "workout_avg_heart_rate"), .workouts)
        XCTAssertEqual(FrontmatterFieldGroup.group(for: "walking_heart_rate"), .heart)
        XCTAssertEqual(FrontmatterFieldGroup.group(for: "step_length_cm"), .mobility)
        XCTAssertEqual(FrontmatterFieldGroup.group(for: "average_mood_valence"), .mindfulness)
        XCTAssertEqual(FrontmatterFieldGroup.group(for: "future_field"), .other)
    }

    func testGroupingKeepsEveryFieldOnceInConfigurationOrder() {
        let fields = FrontmatterConfiguration.defaultFields
        let grouped = FrontmatterFieldGroup.grouped(fields)
        XCTAssertEqual(grouped.flatMap(\.fields).count, fields.count)
        XCTAssertEqual(Set(grouped.flatMap(\.fields).map(\.originalKey)), Set(fields.map(\.originalKey)))
        let sleep = grouped.first { $0.group == .sleep }
        XCTAssertEqual(sleep?.fields.map(\.originalKey), fields.filter { $0.originalKey.hasPrefix("sleep_") }.map(\.originalKey))
        XCTAssertFalse(grouped.contains { $0.fields.isEmpty })
    }

    // MARK: - Individual entry example

    private let utc = TimeZone(identifier: "UTC")!
    private let date = Date(timeIntervalSince1970: 1_793_344_320) // 2026-10-30T07:12:00Z

    private func settings(tracking ids: [String], categoryFolders: Bool = true) -> IndividualTrackingSnapshot {
        IndividualTrackingSnapshot(
            globalEnabled: true,
            metricConfigs: Dictionary(uniqueKeysWithValues: ids.map { ($0, MetricTrackingConfig(trackIndividually: true)) }),
            entriesFolder: "entries",
            useCategoryFolders: categoryFolders,
            filenameTemplate: "{date}-{time}-{metric}"
        )
    }

    func testExampleUsesTheTrackedMetricAndTheExporterFormat() throws {
        let example = try XCTUnwrap(IndividualEntryExample.make(
            settings: settings(tracking: ["blood_glucose", "workouts"]),
            enabledMetricIDs: ["blood_glucose", "workouts"],
            date: date,
            timeZone: utc
        ))
        XCTAssertEqual(example.path, "entries/vitals/2026_10_30-0712-blood_glucose.md")
        let frontmatter = try XCTUnwrap(example.frontmatter)
        XCTAssertTrue(frontmatter.hasPrefix("---\n"))
        XCTAssertTrue(frontmatter.contains("metric: blood_glucose"))
        XCTAssertTrue(frontmatter.contains("type: vitals"))
        XCTAssertTrue(frontmatter.contains("date: 2026-10-30"))
        XCTAssertFalse(frontmatter.contains("value:"), "The example must not invent a health value")
    }

    func testFlatFoldersAndWorkoutOnlyShowThePathWithoutFrontmatter() throws {
        let example = try XCTUnwrap(IndividualEntryExample.make(
            settings: settings(tracking: ["workouts"], categoryFolders: false),
            enabledMetricIDs: ["workouts"],
            date: date,
            timeZone: utc
        ))
        XCTAssertEqual(example.path, "entries/2026_10_30-0712-workouts.md")
        XCTAssertNil(example.frontmatter)
    }

    func testNoExampleWithoutATrackedMetricEnabledInTheProfile() {
        XCTAssertNil(IndividualEntryExample.make(
            settings: settings(tracking: ["blood_glucose"]),
            enabledMetricIDs: ["steps"],
            date: date,
            timeZone: utc
        ))
        XCTAssertNil(IndividualEntryExample.make(
            settings: settings(tracking: []),
            enabledMetricIDs: ["blood_glucose"],
            date: date,
            timeZone: utc
        ))
    }
}
