import Foundation
import Testing

/// HealthMdWatchShared/WatchDashboardMetrics.swift and WatchHealthSnapshot.swift are compiled
/// into this bundle directly (the watch target has no test host).
struct WatchDashboardMetricTests {
    @Test
    func dashboardRestoresTheThreeActivityRowsFrom35() {
        #expect(WatchDashboardMetric.allCases == [
            .sleep, .heartRateVariability, .restingHeartRate, .steps,
            .activeEnergy, .exerciseMinutes, .standHours, .bloodOxygen
        ])
    }

    @Test
    func rowsFormatEverySnapshotValue() {
        let snapshot = WatchHealthSnapshot(
            date: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 0),
            steps: 8_420,
            activeEnergyKilocalories: 410.4,
            exerciseMinutes: 32,
            standHours: 9,
            sleepHours: 7.2,
            restingHeartRate: 58,
            heartRateVariabilityMS: 46,
            bloodOxygenPercent: 97
        )
        let values = Dictionary(uniqueKeysWithValues: WatchDashboardMetric.allCases.map { ($0, $0.value(in: snapshot)) })
        #expect(values[.sleep] == "7h 12m")
        #expect(values[.heartRateVariability] == "46 ms")
        #expect(values[.restingHeartRate] == "58")
        #expect(values[.activeEnergy] == "410 kcal")
        #expect(values[.exerciseMinutes] == "32 min")
        #expect(values[.standHours] == "9 hrs")
        #expect(values[.bloodOxygen] == "97%")
    }

    @Test
    func missingActivityValuesShowADashWithoutAUnit() {
        let empty = WatchHealthSnapshot(date: .now, lastUpdated: .now)
        for metric in WatchDashboardMetric.allCases {
            #expect(metric.value(in: empty) == "—", "\(metric) should show a bare dash")
        }
    }

    /// X-18: the watch target ships its own string catalog; every row title must be in it with
    /// a value for each shipped locale, or the title would fall back to English.
    @Test
    func everyRowTitleIsLocalizedInTheWatchCatalog() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HealthMdWatch/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let locales = ["de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]

        for metric in WatchDashboardMetric.allCases {
            let entry = try #require(strings[metric.titleKey] as? [String: Any], "missing \(metric.titleKey)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for locale in locales {
                let unit = (localizations[locale] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                #expect(value?.isEmpty == false, "\(metric.titleKey) has no \(locale) value")
            }
        }
    }
}
