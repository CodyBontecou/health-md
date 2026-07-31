import XCTest
@testable import HealthMd

@MainActor
final class PreparedHealthDataExportTests: XCTestCase {
    func testSelectionAppliedFastPathMatchesRegularPreparationForLosslessData() throws {
        let suiteName = "PreparedHealthDataExportTests.fast-path.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = Set(ExportFormat.allCases)
        settings.metricSelection.deselectAll()
        ["heart_rate_avg", "heart_rate_max", "sleep_total", "workouts"].forEach {
            settings.metricSelection.toggleMetric($0)
        }

        let selected = ExportFixtures.losslessDay.filtered(by: settings.metricSelection)
        let regular = selected.preparedExport(settings: settings)
        let fast = selected.preparedExportAssumingSelectionApplied(settings: settings)

        for format in ExportFormat.allCases {
            XCTAssertEqual(
                try fast.content(format: format, settings: settings),
                try regular.content(format: format, settings: settings),
                "Already-selected \(format.rawValue) output must remain byte-identical."
            )
        }
    }

    func testPreparedStreamingAndFileArtifactsMatchCompatibilityContent() throws {
        let suiteName = "PreparedHealthDataExportTests.streaming.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = Set(ExportFormat.allCases)
        let prepared = ExportFixtures.losslessDay.preparedExport(settings: settings)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PreparedHealthDataExportTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        for format in ExportFormat.allCases {
            let expected = Data(try prepared.content(format: format, settings: settings).utf8)
            let sink = MemoryExportByteSink(mediaType: "application/octet-stream")
            try prepared.render(format: format, to: sink)
            _ = try sink.finish()
            XCTAssertEqual(sink.data, expected, format.rawValue)

            let artifact = try prepared.renderArtifact(format: format, in: directory)
            XCTAssertEqual(try Data(contentsOf: artifact.url), expected, format.rawValue)
            XCTAssertEqual(artifact.descriptor.byteCount, UInt64(expected.count))
        }
    }

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
