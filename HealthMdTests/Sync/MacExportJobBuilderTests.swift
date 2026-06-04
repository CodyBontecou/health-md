import XCTest
@testable import HealthMd

@MainActor
final class MacExportJobBuilderTests: XCTestCase {
    func testBuild_fetchesEachDateUsingIncludeGranularDataSetting() async throws {
        let settings = makeSettings()
        settings.includeGranularData = true
        let start = Self.day(2026, 5, 12)
        let end = Self.day(2026, 5, 13)
        var requestedGranularFlags: [Bool] = []

        let job = try await MacExportJobBuilder.build(
            jobID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            sourceDeviceName: "Test iPhone",
            startDate: start,
            endDate: end,
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { date, includeGranularData in
                requestedGranularFlags.append(includeGranularData)
                var data = HealthData(date: date)
                data.activity.steps = 123
                return data
            }
        )

        XCTAssertEqual(requestedGranularFlags, [true, true])
        XCTAssertTrue(job.settingsSnapshot.includeGranularData)
        XCTAssertEqual(job.settingsSnapshot.portableProfile.formatIDs, ["markdown"])
        XCTAssertEqual(job.settingsSnapshot.portableProfile.aggregateFilenameTemplate, settings.filenameFormat)
        XCTAssertEqual(job.settingsSnapshot.portableProfile.aggregateFolderTemplate, settings.folderStructure)
        XCTAssertEqual(job.records.count, 2)
        XCTAssertEqual(job.exportTriggerSource, .connectedPeer)
        XCTAssertEqual(job.requestedTarget?.kind, .connectedMac)
        XCTAssertEqual(job.requestedTarget?.destinationDisplayName, "MacVault")
        XCTAssertEqual(job.portableJobSnapshot.jobID, job.jobID)
        XCTAssertEqual(job.portableJobSnapshot.sourceDeviceName, "Test iPhone")
        XCTAssertEqual(job.portableJobSnapshot.exportProfile, job.settingsSnapshot.portableProfile)
        XCTAssertEqual(job.portableJobSnapshot.requestedTarget?.kindID, ExportTargetSnapshot.Kind.connectedMac.rawValue)
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suiteName = "MacExportJobBuilderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.markdown]
        return settings
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }
}
