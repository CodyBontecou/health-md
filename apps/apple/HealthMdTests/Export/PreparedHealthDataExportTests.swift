import XCTest
@testable import HealthMd

@MainActor
final class PreparedHealthDataExportTests: XCTestCase {
    func testPreparedContentUsesOneImmutableSettingsSnapshotAcrossFormats() throws {
        let suiteName = "PreparedHealthDataExportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.includeMetadata = true
        settings.groupByCategory = true
        settings.formatCustomization.unitPreference = .metric

        var record = HealthData(date: Date(timeIntervalSince1970: 1_800_000_000))
        record.activity.steps = 12_345
        record.activity.walkingRunningDistance = 5_000
        let prepared = record.preparedExport(settings: settings)
        let before = try Dictionary(uniqueKeysWithValues: ExportFormat.allCases.map {
            ($0, try prepared.content(format: $0, settings: settings))
        })

        settings.includeMetadata = false
        settings.groupByCategory = false
        settings.formatCustomization.unitPreference = .imperial
        settings.formatCustomization.dateFormat = .usShort
        settings.formatCustomization.frontmatterConfig.keyStyle = .snakeCase

        for format in ExportFormat.allCases {
            XCTAssertEqual(
                try prepared.content(format: format, settings: settings),
                before[format],
                "Prepared \(format.rawValue) output must not mix settings from different moments."
            )
        }
    }
}
