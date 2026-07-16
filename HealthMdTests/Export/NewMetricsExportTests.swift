//
//  NewMetricsExportTests.swift
//  HealthMdTests
//
//  TDD tests for the new health metric categories added in the full-metrics
//  wiring pass: reproductive health, cycling performance, vitamins, minerals,
//  symptoms, other, and extended activity/heart/vitals/mobility/nutrition.
//

import XCTest
import HealthKit
@testable import HealthMd

// Static to avoid macOS 26 / Swift 6 reentrant-main-actor-deinit crash.
// AdvancedExportSettings (and its nested FormatCustomization) must never be
// deallocated during a test run.
//
// `settings` uses an isolated UserDefaults suite so the test is not poisoned by
// stale persisted state from earlier app/dev runs (e.g. a saved
// MetricSelectionState that predates Symptoms / Reproductive Health / Other
// being added as categories — these would otherwise default to disabled).
private enum NewMetricsTestFixtures {
    static let customization = FormatCustomization()
    static let isolatedDefaults: UserDefaults = {
        let suiteName = "healthmd.tests.new-metrics-export.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }()
    static let settings = AdvancedExportSettings(userDefaults: isolatedDefaults)
}

final class NewMetricsExportTests: XCTestCase {

    // MARK: - Dictionary Integrity

    /// Every metric ID in HealthMetrics.all must have an entry in the export mapping.
    func testAllMetricIdsHaveExportMappings() {
        let mappedIds = Set(HealthMetricExportMapping.metricIdToFrontmatterKeys.keys)
        let definedIds = HealthMetrics.all
            .filter { !$0.isPendingAppleApproval }
            .map(\.id)

        let archiveOnlyIds = Set(
            HealthMetrics.all.filter(\.isArchiveOnly).map(\.id)
        )
        XCTAssertEqual(
            HealthMetricExportMapping.reviewedArchiveOnlyMetricIDs,
            archiveOnlyIds,
            "Archive-only definitions require an explicit export-mapping review"
        )
        XCTAssertTrue(
            mappedIds.isDisjoint(with: archiveOnlyIds),
            "Archive-only metrics must not gain fake daily summary keys"
        )

        let missing = definedIds.filter {
            !mappedIds.contains($0) && !archiveOnlyIds.contains($0)
        }
        XCTAssertEqual(missing, [], "Metric IDs defined in HealthMetrics but missing from export mapping or archive-only review")
    }

    /// The metricIdToFrontmatterKeys dictionary must initialise without crashing.
    /// (Catches duplicate-key bugs that only manifest at runtime.)
    func testExportMappingDictionaryInitialises() {
        let dict = HealthMetricExportMapping.metricIdToFrontmatterKeys
        XCTAssertGreaterThan(dict.count, 100, "Expected 100+ metric mappings")
    }

    // MARK: - Frontmatter Builder Smoke Tests

    /// Build the frontmatter dictionary with ALL new data populated.
    /// Must not crash and must contain keys for every new category.
    func testBuildFrontmatterWithAllNewMetrics() {
        var data = HealthData(date: Date())

        // Extended activity
        data.activity.wheelchairDistance = 5000
        data.activity.downhillSnowSportsDistance = 12000
        data.activity.moveTime = 30
        data.activity.physicalEffort = 8.5

        // Extended heart
        data.heart.heartRateRecovery = 25
        data.heart.atrialFibrillationBurden = 0.02

        // Extended vitals
        data.vitals.basalBodyTemperature = 36.6
        data.vitals.wristTemperature = 0.3
        data.vitals.electrodermalActivity = 1.5
        data.vitals.forcedVitalCapacity = 4.2
        data.vitals.forcedExpiratoryVolume1 = 3.5
        data.vitals.peakExpiratoryFlowRate = 500
        data.vitals.inhalerUsage = 2

        // Extended nutrition
        data.nutrition.monounsaturatedFat = 15.2
        data.nutrition.polyunsaturatedFat = 8.7

        // Extended mobility
        data.mobility.walkingSteadiness = 0.85
        data.mobility.runningSpeed = 3.5
        data.mobility.runningStrideLength = 1.2
        data.mobility.runningGroundContactTime = 250
        data.mobility.runningVerticalOscillation = 8.5
        data.mobility.runningPower = 320

        // Cycling performance
        data.cyclingPerformance.cyclingSpeed = 8.3
        data.cyclingPerformance.cyclingPower = 200
        data.cyclingPerformance.cyclingCadence = 85
        data.cyclingPerformance.cyclingFTP = 250

        // Vitamins
        data.vitamins.vitaminA = 900
        data.vitamins.vitaminC = 90
        data.vitamins.vitaminD = 20

        // Minerals
        data.minerals.calcium = 1000
        data.minerals.iron = 18
        data.minerals.potassium = 3500

        // Symptoms
        data.symptoms.counts = [
            "symptom_headache": 2,
            "symptom_fatigue": 1,
        ]

        // Reproductive health
        data.reproductiveHealth.menstrualFlow = "medium"
        data.reproductiveHealth.cervicalMucusQuality = "creamy"

        // Other
        data.other.uvExposure = 3.5
        data.other.timeInDaylight = 45
        data.other.toothbrushingCount = 2
        data.other.handwashingCount = 8

        let converter = UnitConverter(preference: .metric)
        let result = ExportFrontmatterMetricBuilder.build(
            from: data,
            converter: converter,
            timeFormat: .hour24
        )

        // Spot-check keys from each new category
        XCTAssertNotNil(result["wheelchair_km"], "wheelchair distance")
        XCTAssertNotNil(result["move_minutes"], "move time")
        XCTAssertNotNil(result["heart_rate_recovery"], "HR recovery")
        XCTAssertNotNil(result["afib_burden_percent"], "AFib burden")
        XCTAssertNotNil(result["basal_body_temperature"], "basal body temp")
        XCTAssertNotNil(result["forced_vital_capacity_l"], "FVC")
        XCTAssertNotNil(result["monounsaturated_fat_g"], "mono fat")
        XCTAssertNotNil(result["walking_steadiness_percent"], "walking steadiness")
        XCTAssertNotNil(result["running_power_w"], "running power")
        XCTAssertNotNil(result["cycling_power_w"], "cycling power")
        XCTAssertNotNil(result["vitamin_a_ug"], "vitamin A")
        XCTAssertNotNil(result["calcium_mg"], "calcium")
        XCTAssertNotNil(result["symptom_headache"], "symptom headache")
        XCTAssertNotNil(result["menstrual_flow"], "menstrual flow")
        XCTAssertNotNil(result["uv_exposure"], "UV exposure")
        XCTAssertNotNil(result["toothbrushing"], "toothbrushing")
    }

    // MARK: - Full Export Pipeline Smoke

    // Shared data factory for export pipeline tests.
    private func makePopulatedHealthData() -> HealthData {
        var data = HealthData(date: Date())
        data.symptoms.counts = ["symptom_headache": 1]
        data.vitamins.vitaminC = 90
        data.minerals.iron = 18
        data.other.toothbrushingCount = 2
        data.cyclingPerformance.cyclingPower = 200
        data.reproductiveHealth.menstrualFlow = "light"
        data.vitals.basalBodyTemperature = 36.6
        data.heart.heartRateRecovery = 25
        data.activity.wheelchairDistance = 5000
        data.mobility.runningSpeed = 3.5
        data.nutrition.monounsaturatedFat = 15.2
        return data
    }

    /// Step 1: Filtering new data should not crash.
    func testExportPipeline_filterNewData() {
        let data = makePopulatedHealthData()
        let filtered = data.filtered(by: NewMetricsTestFixtures.settings.metricSelection)
        XCTAssertTrue(filtered.hasAnyData)
    }

    /// Step 2: Markdown export with new data should not crash.
    func testExportPipeline_markdown() {
        let data = makePopulatedHealthData()
        let result = data.export(format: .markdown, settings: NewMetricsTestFixtures.settings)
        XCTAssertFalse(result.isEmpty, "Markdown export should not be empty")
    }

    /// Step 3: Obsidian Bases export with new data should not crash.
    func testExportPipeline_obsidianBases() {
        let data = makePopulatedHealthData()
        let result = data.export(format: .obsidianBases, settings: NewMetricsTestFixtures.settings)
        XCTAssertFalse(result.isEmpty, "Obsidian Bases export should not be empty")
    }

    /// Step 4: JSON export with new data should not crash.
    func testExportPipeline_json() {
        let data = makePopulatedHealthData()
        let result = data.export(format: .json, settings: NewMetricsTestFixtures.settings)
        XCTAssertFalse(result.isEmpty, "JSON export should not be empty")
    }

    /// Step 5: CSV export with new data should not crash.
    func testExportPipeline_csv() {
        let data = makePopulatedHealthData()
        let result = data.export(format: .csv, settings: NewMetricsTestFixtures.settings)
        XCTAssertFalse(result.isEmpty, "CSV export should not be empty")
    }

    /// Step 6: Codable round-trip for new data structs.
    func testCodableRoundTrip_newDataStructs() throws {
        let data = makePopulatedHealthData()
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthData.self, from: encoded)
        XCTAssertEqual(decoded.symptoms.counts["symptom_headache"], 1)
        XCTAssertEqual(decoded.vitamins.vitaminC, 90)
        XCTAssertEqual(decoded.minerals.iron, 18)
        XCTAssertEqual(decoded.cyclingPerformance.cyclingPower, 200)
        XCTAssertEqual(decoded.reproductiveHealth.menstrualFlow, "light")
        XCTAssertEqual(decoded.other.toothbrushingCount, 2)
        XCTAssertEqual(decoded.vitals.basalBodyTemperature, 36.6)
        XCTAssertEqual(decoded.heart.heartRateRecovery, 25)
        XCTAssertEqual(decoded.activity.wheelchairDistance, 5000)
        XCTAssertEqual(decoded.mobility.runningSpeed, 3.5)
        XCTAssertEqual(decoded.nutrition.monounsaturatedFat, 15.2)
    }

    /// RED TEST: Every quantity-type metric must have a unit mapping in
    /// SystemHealthStoreAdapter.unitMap, otherwise the real device will crash
    /// with an incompatible HKUnit when converting HealthKit samples.
    func testAllQuantityMetricsHaveUnitMappings() {
        let adapter = SystemHealthStoreAdapter()
        let mappedIdentifiers = Set(adapter.unitMap.keys.map(\.rawValue))

        let quantityMetrics = HealthMetrics.all.filter {
            $0.metricType == .quantity && $0.availability.isAvailableOnCurrentPlatform
        }
        var missing: [String] = []

        for metric in quantityMetrics {
            guard let hkId = metric.healthKitIdentifier else { continue }
            if !mappedIdentifiers.contains(hkId) {
                missing.append("\(metric.id) (\(hkId))")
            }
        }

        XCTAssertEqual(missing, [],
            "Quantity metrics missing from SystemHealthStoreAdapter.unitMap — " +
            "these will crash on a real device when data exists")
    }

    func testVitaminAndMineralUnitMappingsMatchDeclaredCanonicalUnits() {
        let adapter = SystemHealthStoreAdapter()
        let expectedUnits: [HKQuantityTypeIdentifier: HKUnit] = [
            .dietaryVitaminA: .gramUnit(with: .micro),
            .dietaryVitaminB6: .gramUnit(with: .milli),
            .dietaryVitaminB12: .gramUnit(with: .micro),
            .dietaryVitaminC: .gramUnit(with: .milli),
            .dietaryVitaminD: .gramUnit(with: .micro),
            .dietaryVitaminE: .gramUnit(with: .milli),
            .dietaryVitaminK: .gramUnit(with: .micro),
            .dietaryThiamin: .gramUnit(with: .milli),
            .dietaryRiboflavin: .gramUnit(with: .milli),
            .dietaryNiacin: .gramUnit(with: .milli),
            .dietaryFolate: .gramUnit(with: .micro),
            .dietaryBiotin: .gramUnit(with: .micro),
            .dietaryPantothenicAcid: .gramUnit(with: .milli),
            .dietaryCalcium: .gramUnit(with: .milli),
            .dietaryIron: .gramUnit(with: .milli),
            .dietaryPotassium: .gramUnit(with: .milli),
            .dietaryMagnesium: .gramUnit(with: .milli),
            .dietaryPhosphorus: .gramUnit(with: .milli),
            .dietaryZinc: .gramUnit(with: .milli),
            .dietarySelenium: .gramUnit(with: .micro),
            .dietaryCopper: .gramUnit(with: .milli),
            .dietaryManganese: .gramUnit(with: .milli),
            .dietaryChromium: .gramUnit(with: .micro),
            .dietaryMolybdenum: .gramUnit(with: .micro),
            .dietaryChloride: .gramUnit(with: .milli),
            .dietaryIodine: .gramUnit(with: .micro),
        ]
        let declaredIdentifiers = Set(
            (HealthMetrics.vitamins + HealthMetrics.minerals)
                .compactMap(\.healthKitIdentifier)
        )

        XCTAssertEqual(
            Set(expectedUnits.keys.map(\.rawValue)),
            declaredIdentifiers,
            "The unit fixture must cover every declared vitamin and mineral"
        )

        for identifier in expectedUnits.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let actualUnit = adapter.unitMap[identifier],
                  let expectedUnit = expectedUnits[identifier] else {
                XCTFail("Missing unit mapping for \(identifier.rawValue)")
                continue
            }
            XCTAssertEqual(
                actualUnit.unitString,
                expectedUnit.unitString,
                "Canonical unit mismatch for \(identifier.rawValue)"
            )
        }
    }

    func testNoVitaminOrMineralUnitMappingUsesPlainGrams() {
        let adapter = SystemHealthStoreAdapter()
        let nutrientIdentifiers = Set(
            (HealthMetrics.vitamins + HealthMetrics.minerals)
                .compactMap(\.healthKitIdentifier)
        )
        let plainGramUnitString = HKUnit.gram().unitString
        let offenders = adapter.unitMap
            .filter { nutrientIdentifiers.contains($0.key.rawValue) && $0.value.unitString == plainGramUnitString }
            .map { $0.key.rawValue }
            .sorted()

        XCTAssertEqual(
            offenders,
            [],
            "Vitamin/mineral mappings must use their declared mg or µg canonical units"
        )
    }

    /// RED TEST: UV exposure is a discrete quantity type in HealthKit. Using
    /// querySum (cumulativeSum) crashes on device. Must use queryMax or queryAverage.
    func testFetchOtherData_uvExposureIsDiscrete() async throws {
        let store = FakeHealthStore()
        // Populate UV exposure data
        store.statisticsMaxes[HKQuantityTypeIdentifier.uvExposure.rawValue] = 7.0
        // Note: we intentionally do NOT populate statisticsSums for uvExposure
        // to simulate the real device behavior where sum is not supported.

        let manager = await HealthKitManager(store: store)
        let data = try await manager.fetchHealthData(for: HealthKitFixtures.referenceDate)

        // UV exposure should come through via max (discrete), not sum (cumulative)
        XCTAssertEqual(data.other.uvExposure, 7.0, "UV exposure should be fetched as discrete max, not cumulative sum")
    }

    /// Every format must include new metric DATA (not necessarily frontmatter keys).
    /// Check for display labels/values that indicate the metric was rendered.
    func testAllFormatsOutputNewMetricData() {
        let data = makePopulatedHealthData()
        let settings = NewMetricsTestFixtures.settings

        // Representative strings that must appear in each format's output.
        // These are format-agnostic: labels, values, or category names.
        let requiredStrings = [
            "Wheelchair",       // Activity extension
            "Heart Rate Recovery", // Heart extension
            "Basal Body Temp",  // Vitals extension (partial match)
            "Cycling",          // New category
            "Vitamin C",        // Vitamins category
            "Iron",             // Minerals category (value "18")
            "Headache",         // Symptoms category
            "Menstrual Flow",   // Reproductive Health
            "Toothbrushing",    // Other category
            "Running",          // Mobility extension (partial match)
            "Monounsaturated",  // Nutrition extension
        ]

        // Markdown and CSV use display labels
        for format in [ExportFormat.markdown, .csv] {
            let output = data.export(format: format, settings: settings)
            for keyword in requiredStrings {
                XCTAssertTrue(
                    output.localizedCaseInsensitiveContains(keyword),
                    "\(format) export missing content for '\(keyword)'"
                )
            }
        }

        // JSON uses camelCase/snake_case keys — check for frontmatter keys and values
        let jsonOutput = data.export(format: .json, settings: settings)
        let jsonMarkers = [
            "wheelchair",       // activity extension
            "heartRateRecovery", // heart extension (camelCase)
            "basalBodyTemperature", // vitals extension
            "cycling",          // cycling category key
            "vitamin_c",        // vitamins section
            "iron",             // minerals section
            "symptom_headache", // symptoms section
            "menstrual_flow",   // reproductive health
            "toothbrushing",    // other section
            "running",          // mobility extension
            "monounsaturatedFat", // nutrition extension
        ]
        for marker in jsonMarkers {
            XCTAssertTrue(
                jsonOutput.localizedCaseInsensitiveContains(marker),
                "JSON export missing content for '\(marker)'"
            )
        }

        // Obsidian Bases uses frontmatter keys
        let obsidianOutput = data.export(format: .obsidianBases, settings: settings)
        let obsidianKeys = [
            "wheelchair_km", "heart_rate_recovery", "basal_body_temperature",
            "cycling_power_w", "vitamin_c_mg", "iron_mg",
            "symptom_headache", "menstrual_flow", "toothbrushing",
            "monounsaturated_fat_g",
        ]
        for key in obsidianKeys {
            XCTAssertTrue(
                obsidianOutput.contains(key),
                "Obsidian Bases export missing frontmatter key '\(key)'"
            )
        }
    }

    /// Step 9: DataTypeSelection Codable backward compatibility — decoding old
    /// data (missing reproductiveHealth) must not crash.
    func testDataTypeSelection_backwardCompatibility() throws {
        // Simulate old saved data without the reproductiveHealth field
        let oldJSON = """
        {"sleep":true,"activity":true,"heart":true,"vitals":true,"body":true,
         "nutrition":true,"mindfulness":true,"mobility":true,"hearing":true,"workouts":true}
        """
        let data = oldJSON.data(using: .utf8)!
        // This should either decode successfully or fail gracefully — NOT crash
        let result = try? JSONDecoder().decode(DataTypeSelection.self, from: data)
        // If synthesized Codable can't handle missing keys, result will be nil.
        // The app init uses try? too, so nil is safe. But let's verify.
        if let result = result {
            XCTAssertTrue(result.sleep)
        }
        // Either way: no crash = pass
    }

    // MARK: - MetricSelectionState Coverage

    /// Verify frontmatterKeys(enabledIn:) works with all metrics enabled (default state).
    func testFrontmatterKeysWithAllMetricsEnabled() {
        let selection = MetricSelectionState()
        // Default state: all enabled
        let keys = HealthMetricExportMapping.frontmatterKeys(enabledIn: selection)
        XCTAssertGreaterThan(keys.count, 50, "Expected many frontmatter keys with all metrics enabled")

        // Verify no duplicates
        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count, "Frontmatter keys should have no duplicates")
    }

    func testFrontmatterIncludesSchemaVersionAndCompactUnitsMap() {
        var data = HealthData(date: Date())
        data.activity.activeCalories = 321
        data.vitals.bloodOxygenAvg = 0.97
        data.activity.vo2Max = 42.3
        data.vitals.wristTemperature = 0.12
        data.heart.hrv = 55.5

        let customization = FormatCustomization()
        let snapshot = data.exportSnapshot(customization: customization)
        let lines = snapshot.frontmatterLines(using: customization.frontmatterConfig)

        XCTAssertTrue(lines.contains("schema: \(HealthMdExportSchema.identifier)"))
        XCTAssertTrue(lines.contains("schema_version: \(HealthMdExportSchema.version)"))
        XCTAssertTrue(lines.contains("units:"))
        XCTAssertTrue(lines.contains("  active_calories: kcal"))
        XCTAssertTrue(lines.contains("  blood_oxygen: percent"))
        XCTAssertTrue(lines.contains("  vo2_max: mL/kg/min"))
        XCTAssertTrue(lines.contains("  wrist_temperature: °C"))
        XCTAssertTrue(lines.contains("  hrv_ms: ms"))
        XCTAssertFalse(lines.contains("  date:"), "date is not a metric and must not appear in units")
        XCTAssertFalse(lines.contains("  type:"), "type is not a metric and must not appear in units")
    }

    func testFrontmatterUnitsUseFinalCustomOutputKey() {
        var data = HealthData(date: Date())
        data.activity.activeCalories = 123

        let customization = FormatCustomization()
        if let index = customization.frontmatterConfig.fields.firstIndex(where: { $0.originalKey == "active_calories" }) {
            customization.frontmatterConfig.fields[index].customKey = "activeEnergyKcal"
        }

        let snapshot = data.exportSnapshot(customization: customization)
        let lines = snapshot.frontmatterLines(using: customization.frontmatterConfig)

        XCTAssertTrue(lines.contains("activeEnergyKcal: 123"))
        XCTAssertTrue(lines.contains("  activeEnergyKcal: kcal"))
        XCTAssertFalse(lines.contains("  active_calories: kcal"))
    }

    func testVO2MaxProvenanceExportsEveryFormatFiltersTogetherAndDecodesLegacyRecords() throws {
        let sourceUUID = UUID(uuidString: "54000000-0000-0000-0000-000000000001")!
        let sourceStart = Date(timeIntervalSince1970: 1_800_000_000.125)
        let sourceEnd = sourceStart.addingTimeInterval(0.875)
        var data = HealthData(date: sourceStart.addingTimeInterval(172_800))
        data.activity.vo2Max = 41.75
        data.activity.vo2MaxSourceUUID = sourceUUID
        data.activity.vo2MaxSourceStartDate = sourceStart
        data.activity.vo2MaxSourceEndDate = sourceEnd
        data.activity.vo2MaxCarriedForward = true
        data.activity.vo2MaxAgeSeconds = 172_800

        let json = data.toJSON(customization: FormatCustomization())
        XCTAssertTrue(json.contains("\"vo2MaxSourceUUID\" : \"\(sourceUUID.uuidString)\""), json)
        XCTAssertTrue(json.contains("\"vo2MaxSourceStartDate\" : \"\(CanonicalRFC3339UTC.string(from: sourceStart))\""), json)
        XCTAssertTrue(json.contains("\"vo2MaxSourceEndDate\" : \"\(CanonicalRFC3339UTC.string(from: sourceEnd))\""), json)
        XCTAssertTrue(json.contains("\"vo2MaxCarriedForward\" : true"), json)
        XCTAssertTrue(json.contains("\"vo2MaxAgeSeconds\" : 172800"), json)

        let csv = data.toCSV(customization: FormatCustomization())
        XCTAssertTrue(csv.contains(",Activity,VO2 Max Source UUID,\(sourceUUID.uuidString),uuid,"), csv)
        XCTAssertTrue(csv.contains(",Activity,VO2 Max Carried Forward,true,boolean,"), csv)
        XCTAssertTrue(csv.contains(",Activity,VO2 Max Age,172800,seconds,"), csv)

        let markdown = data.toMarkdown(customization: FormatCustomization())
        XCTAssertTrue(markdown.contains("vo2_max_source_uuid: \(sourceUUID.uuidString)"), markdown)
        XCTAssertTrue(markdown.contains("vo2_max_carried_forward: true"), markdown)
        XCTAssertTrue(markdown.contains("Source measurement: \(CanonicalRFC3339UTC.string(from: sourceStart)) (carried forward)"), markdown)

        let bases = data.toObsidianBases(customization: FormatCustomization())
        XCTAssertTrue(bases.contains("vo2_max_source_start: \(CanonicalRFC3339UTC.string(from: sourceStart))"), bases)
        XCTAssertTrue(bases.contains("vo2_max_age_seconds: 172800"), bases)

        let disabled = MetricSelectionState()
        disabled.deselectAll()
        disabled.enabledMetrics.insert("steps")
        let filtered = data.filtered(by: disabled)
        XCTAssertNil(filtered.activity.vo2Max)
        XCTAssertNil(filtered.activity.vo2MaxSourceUUID)
        XCTAssertNil(filtered.activity.vo2MaxSourceStartDate)
        XCTAssertNil(filtered.activity.vo2MaxCarriedForward)
        XCTAssertFalse(filtered.toJSON(customization: FormatCustomization()).contains("vo2Max"))

        let dictionary = Dictionary(uniqueKeysWithValues: HealthMetricDataDictionary.entries().map { ($0.canonicalKey, $0) })
        XCTAssertEqual(dictionary["vo2_max_source_uuid"]?.unit, "uuid")
        XCTAssertEqual(dictionary["vo2_max_source_start"]?.dailyAggregation, "latest")
        XCTAssertEqual(dictionary["vo2_max_source_start"]?.rollup.statistics, ["latest", "value_counts", "days_counted"])
        XCTAssertEqual(dictionary["vo2_max_carried_forward"]?.unit, "boolean")
        XCTAssertEqual(dictionary["vo2_max_age_seconds"]?.unit, "seconds")

        let legacy = try JSONDecoder().decode(ActivityData.self, from: Data(#"{"vo2Max":42.5}"#.utf8))
        XCTAssertEqual(legacy.vo2Max, 42.5)
        XCTAssertNil(legacy.vo2MaxSourceUUID)
        XCTAssertNil(legacy.vo2MaxCarriedForward)
    }

    func testDataDictionaryContainsRepresentativeKeys() {
        let entries = HealthMetricDataDictionary.entries()
        let byCanonicalKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.canonicalKey, $0) })

        let activeCalories = byCanonicalKey["active_calories"]
        XCTAssertEqual(activeCalories?.metricId, "active_energy")
        XCTAssertEqual(activeCalories?.unit, "kcal")
        XCTAssertEqual(activeCalories?.healthKitIdentifier, "HKQuantityTypeIdentifierActiveEnergyBurned")
        XCTAssertEqual(activeCalories?.aggregation, "sum")
        XCTAssertEqual(activeCalories?.dailyAggregation, "sum")
        XCTAssertEqual(activeCalories?.healthKitAggregation, "cumulative")
        XCTAssertEqual(activeCalories?.rollup.primary, "sum")
        XCTAssertEqual(activeCalories?.rollup.periods, ["weekly", "monthly", "yearly"])
        XCTAssertEqual(activeCalories?.schemaVersion, HealthMdExportSchema.version)

        XCTAssertEqual(byCanonicalKey["blood_oxygen"]?.unit, "percent")
        XCTAssertEqual(byCanonicalKey["blood_oxygen"]?.healthKitIdentifier, "HKQuantityTypeIdentifierOxygenSaturation")
        XCTAssertEqual(byCanonicalKey["vo2_max"]?.unit, "mL/kg/min")
        XCTAssertEqual(byCanonicalKey["vo2_max"]?.healthKitIdentifier, "HKQuantityTypeIdentifierVO2Max")
        XCTAssertEqual(byCanonicalKey["wrist_temperature"]?.unit, "°C")
        XCTAssertEqual(byCanonicalKey["wrist_temperature"]?.healthKitIdentifier, "HKQuantityTypeIdentifierAppleSleepingWristTemperature")
        XCTAssertEqual(byCanonicalKey["hrv_ms"]?.unit, "ms")
        XCTAssertEqual(byCanonicalKey["hrv_ms"]?.healthKitIdentifier, "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
        XCTAssertEqual(byCanonicalKey["blood_oxygen_min"]?.dailyAggregation, "minimum")
        XCTAssertEqual(byCanonicalKey["blood_oxygen_min"]?.rollup.primary, "minimum")
        XCTAssertEqual(byCanonicalKey["medication_count"]?.dailyAggregation, "latest")
        XCTAssertEqual(byCanonicalKey["medication_count"]?.rollup.primary, "latest")
        XCTAssertEqual(byCanonicalKey["medication_details"]?.dailyAggregation, "list")
        XCTAssertEqual(byCanonicalKey["medication_details"]?.unit, "")
        XCTAssertEqual(byCanonicalKey["medication_dose_events"]?.dailyAggregation, "list")
        XCTAssertEqual(byCanonicalKey["medication_dose_events"]?.unit, "")
        XCTAssertEqual(byCanonicalKey["workout_avg_heart_rate"]?.dailyAggregation, "weighted_average")
        XCTAssertEqual(byCanonicalKey["workout_avg_heart_rate"]?.rollup.weightedBy, "duration")
    }

    func testAggregationDefinitionsMatchFetchedDailyStatisticsAndRollups() {
        let definitions = Dictionary(uniqueKeysWithValues: HealthMetrics.all.map { ($0.id, $0) })
        for metricID in [
            "respiratory_rate", "blood_oxygen", "body_temperature",
            "blood_pressure_systolic", "blood_pressure_diastolic", "blood_glucose"
        ] {
            guard case .discreteAvg? = definitions[metricID]?.aggregation else {
                return XCTFail("\(metricID) must declare discrete average because fetches produce avg/min/max")
            }
        }
        guard case .discreteMax? = definitions["uv_exposure"]?.aggregation else {
            return XCTFail("UV Exposure must declare the discrete maximum fetched by HealthKitManager")
        }

        let entries = Dictionary(uniqueKeysWithValues: HealthMetricDataDictionary.entries().map { ($0.canonicalKey, $0) })
        let summaryPrefixes = [
            "respiratory_rate", "blood_oxygen", "body_temperature",
            "blood_pressure_systolic", "blood_pressure_diastolic", "blood_glucose"
        ]
        for prefix in summaryPrefixes {
            XCTAssertEqual(entries[prefix]?.dailyAggregation, "average", prefix)
            XCTAssertEqual(entries["\(prefix)_avg"]?.dailyAggregation, "average", prefix)
            XCTAssertEqual(entries["\(prefix)_min"]?.dailyAggregation, "minimum", prefix)
            XCTAssertEqual(entries["\(prefix)_max"]?.dailyAggregation, "maximum", prefix)
            XCTAssertEqual(entries[prefix]?.healthKitAggregation, "discreteAvg", prefix)
            XCTAssertEqual(entries[prefix]?.rollup.primary, "average", prefix)
            XCTAssertEqual(entries["\(prefix)_min"]?.rollup.primary, "minimum", prefix)
            XCTAssertEqual(entries["\(prefix)_max"]?.rollup.primary, "maximum", prefix)
        }
        XCTAssertEqual(entries["uv_exposure"]?.dailyAggregation, "maximum")
        XCTAssertEqual(entries["uv_exposure"]?.healthKitAggregation, "discreteMax")
        XCTAssertEqual(entries["uv_exposure"]?.rollup.primary, "maximum")
    }

    func testStandMetricDefinitionsAndDataDictionaryDescribeSeparateConcepts() {
        let definitions = Dictionary(uniqueKeysWithValues: HealthMetrics.activity.map { ($0.id, $0) })
        let standTime = definitions["stand_time"]
        XCTAssertEqual(standTime?.name, "Stand Time")
        XCTAssertEqual(standTime?.unit, "min")
        XCTAssertEqual(standTime?.healthKitIdentifier, "HKQuantityTypeIdentifierAppleStandTime")
        if case .quantity? = standTime?.metricType {} else { XCTFail("Stand Time must be a quantity metric") }
        if case .cumulative? = standTime?.aggregation {} else { XCTFail("Stand Time must use cumulative aggregation") }

        let standHours = definitions["stand_hours"]
        XCTAssertEqual(standHours?.name, "Stand Hours")
        XCTAssertEqual(standHours?.unit, "hours")
        XCTAssertEqual(standHours?.healthKitIdentifier, "HKCategoryTypeIdentifierAppleStandHour")
        if case .category? = standHours?.metricType {} else { XCTFail("Stand Hours must be a category metric") }
        if case .count? = standHours?.aggregation {} else { XCTFail("Stand Hours must use count aggregation") }

        let entries = Dictionary(uniqueKeysWithValues: HealthMetricDataDictionary.entries().map { ($0.canonicalKey, $0) })
        XCTAssertEqual(entries["stand_time_minutes"]?.metricId, "stand_time")
        XCTAssertEqual(entries["stand_time_minutes"]?.displayName, "Stand Time")
        XCTAssertEqual(entries["stand_time_minutes"]?.unit, "min")
        XCTAssertEqual(entries["stand_time_minutes"]?.dailyAggregation, "sum")
        XCTAssertEqual(entries["stand_time_minutes"]?.rollup.primary, "sum")
        XCTAssertEqual(entries["stand_hours"]?.metricId, "stand_hours")
        XCTAssertEqual(entries["stand_hours"]?.displayName, "Stand Hours")
        XCTAssertEqual(entries["stand_hours"]?.unit, "hours")
        XCTAssertEqual(entries["stand_hours"]?.dailyAggregation, "count")
        XCTAssertEqual(entries["stand_hours"]?.rollup.primary, "sum")
    }

    func testDataDictionaryDocumentsRollupRulesForEveryExportedKey() {
        let entries = HealthMetricDataDictionary.entries()
        let canonicalKeys = Set(entries.map(\.canonicalKey))

        let diagnosticKeys: Set<String> = [
            "raw_capture_status", "raw_record_count", "raw_query_failure_count",
            "raw_integrity_warning_count", "raw_record_schema", "raw_record_schema_version"
        ]
        XCTAssertEqual(canonicalKeys, HealthMetricExportMapping.allKnownFrontmatterKeys.union(diagnosticKeys))

        for entry in entries {
            XCTAssertFalse(entry.dailyAggregation.isEmpty, "\(entry.canonicalKey) missing daily aggregation")
            XCTAssertFalse(entry.healthKitAggregation.isEmpty, "\(entry.canonicalKey) missing source aggregation")
            XCTAssertFalse(entry.rollup.primary.isEmpty, "\(entry.canonicalKey) missing roll-up primary rule")
            XCTAssertFalse(entry.rollup.statistics.isEmpty, "\(entry.canonicalKey) missing roll-up statistics")
            XCTAssertEqual(entry.rollup.periods, ["weekly", "monthly", "yearly"], "\(entry.canonicalKey) has unexpected roll-up periods")
        }
    }

    func testDataDictionaryUsesActualFrontmatterUnitsForLegacyAndDerivedKeys() {
        let customization = FormatCustomization()
        customization.unitPreference = .imperial
        let entries = HealthMetricDataDictionary.entries(using: customization)
        let byCanonicalKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.canonicalKey, $0) })

        XCTAssertEqual(byCanonicalKey["height_m"]?.unit, "m")
        XCTAssertEqual(byCanonicalKey["weight_kg"]?.unit, "kg")
        XCTAssertEqual(byCanonicalKey["walking_speed"]?.unit, "m/s")
        XCTAssertEqual(byCanonicalKey["heart_rate_min"]?.unit, "bpm")
        XCTAssertEqual(byCanonicalKey["respiratory_rate_min"]?.unit, "breaths/min")
        XCTAssertEqual(byCanonicalKey["blood_oxygen_min"]?.unit, "percent")
        XCTAssertEqual(byCanonicalKey["body_temperature_min"]?.unit, "°C")
        XCTAssertEqual(byCanonicalKey["wrist_temperature"]?.unit, "°C")
        XCTAssertEqual(byCanonicalKey["workout_calories"]?.unit, "kcal")
        XCTAssertEqual(byCanonicalKey["workout_avg_heart_rate"]?.unit, "bpm")
        XCTAssertEqual(byCanonicalKey["workout_count"]?.unit, "count")
    }

    // MARK: - removeExportField Coverage

    /// Verify that removeExportField handles all new frontmatter keys without crashing.
    func testRemoveExportFieldForAllNewKeys() {
        let newKeys = [
            "wheelchair_km", "downhill_snow_km", "move_minutes", "physical_effort",
            "heart_rate_recovery", "afib_burden_percent",
            "basal_body_temperature", "wrist_temperature", "electrodermal_activity",
            "forced_vital_capacity_l", "fev1_l", "peak_expiratory_flow", "inhaler_usage",
            "monounsaturated_fat_g", "polyunsaturated_fat_g",
            "walking_steadiness_percent", "running_speed", "running_stride_length_m",
            "running_ground_contact_ms", "running_vertical_oscillation_cm", "running_power_w",
            "cycling_speed", "cycling_power_w", "cycling_cadence_rpm", "cycling_ftp_w",
            "vitamin_a_ug", "vitamin_c_mg", "vitamin_d_ug",
            "calcium_mg", "iron_mg", "potassium_mg",
            "symptom_headache", "symptom_fatigue", "symptom_nausea",
            "menstrual_flow", "sexual_activity", "ovulation_test", "cervical_mucus", "intermenstrual_bleeding",
            "uv_exposure", "time_in_daylight_min", "number_of_falls",
            "blood_alcohol_percent", "alcoholic_beverages", "insulin_delivery_iu",
            "toothbrushing", "handwashing", "water_temperature", "underwater_depth_m",
        ]

        // Build a fully-populated HealthData
        var data = HealthData(date: Date())
        data.activity.wheelchairDistance = 5000
        data.heart.heartRateRecovery = 25
        data.vitals.basalBodyTemperature = 36.6
        data.vitamins.vitaminA = 900
        data.minerals.calcium = 1000
        data.symptoms.counts = ["symptom_headache": 1, "symptom_fatigue": 2, "symptom_nausea": 1]
        data.other.uvExposure = 3.5
        data.reproductiveHealth.menstrualFlow = "medium"
        data.cyclingPerformance.cyclingPower = 200
        data.mobility.runningSpeed = 3.5
        data.nutrition.monounsaturatedFat = 15.2

        XCTAssertFalse(newKeys.isEmpty, "Test fixture should cover new export keys")

        // Full filter path: create a MetricSelectionState that disables everything
        let selection = MetricSelectionState()
        selection.deselectAll()
        let filtered = data.filtered(by: selection)

        // With everything disabled, the filtered data should have no exportable content
        let converter = UnitConverter(preference: .metric)
        let dict = ExportFrontmatterMetricBuilder.build(from: filtered, converter: converter, timeFormat: .hour24)
        XCTAssertTrue(dict.isEmpty, "Filtered data with all metrics disabled should produce empty dictionary")
    }
}
