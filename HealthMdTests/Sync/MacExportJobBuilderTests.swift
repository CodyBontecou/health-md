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
        XCTAssertEqual(job.records.count, 2)
        XCTAssertEqual(job.requestedTarget?.kind, .connectedMac)
        XCTAssertEqual(job.requestedTarget?.destinationDisplayName, "MacVault")
    }

    func testBuild_includesFullRollupWindowRecordsWithoutGranularData() async throws {
        let settings = makeSettings()
        settings.includeGranularData = true
        settings.generateWeeklyRollups = true
        let start = Self.day(2026, 5, 12)
        let end = Self.day(2026, 5, 13)
        var requestedDates: [Date] = []
        var requestedGranularFlags: [Bool] = []

        let job = try await MacExportJobBuilder.build(
            sourceDeviceName: "Test iPhone",
            startDate: start,
            endDate: end,
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { date, includeGranularData in
                requestedDates.append(Calendar.current.startOfDay(for: date))
                requestedGranularFlags.append(includeGranularData)
                var data = HealthData(date: date)
                data.activity.steps = 123
                return data
            }
        )

        XCTAssertEqual(job.records.count, 7)
        XCTAssertEqual(requestedDates.first, Calendar.current.startOfDay(for: Self.day(2026, 5, 11)))
        XCTAssertEqual(requestedDates.last, Calendar.current.startOfDay(for: Self.day(2026, 5, 17)))
        XCTAssertEqual(requestedGranularFlags.filter { $0 }.count, 2)
        XCTAssertEqual(requestedGranularFlags.filter { !$0 }.count, 5)
        XCTAssertEqual(job.dateRangeStart, Calendar.current.startOfDay(for: start))
        XCTAssertEqual(job.dateRangeEnd, Calendar.current.startOfDay(for: end))
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
