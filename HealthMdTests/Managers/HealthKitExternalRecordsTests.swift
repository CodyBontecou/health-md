import Foundation
import HealthKit
import XCTest
@testable import HealthMd

@MainActor
final class HealthKitExternalRecordsTests: XCTestCase {
    private let dayStart = Date(timeIntervalSince1970: 1_800_000_000)

    func testExternalRecordCodableFilteringCanonicalJSONAndCSVNeverFabricateHKObjectFields() throws {
        let selected = externalCharacteristic(
            identifier: HealthKitRecordCatalog.biologicalSexIdentifier,
            metricID: "biological_sex",
            rawValue: 1,
            symbolicValue: "female"
        )
        let disabled = externalCharacteristic(
            identifier: HealthKitRecordCatalog.bloodTypeIdentifier,
            metricID: "blood_type",
            rawValue: 7,
            symbolicValue: "oPositive"
        )
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: ownership,
            externalRecords: [disabled, selected]
        )

        let decoded = try JSONDecoder().decode(
            HealthKitRecordArchive.self,
            from: JSONEncoder().encode(archive)
        )
        XCTAssertEqual(decoded, archive)
        XCTAssertEqual(
            archive.filtered(enabledMetricIDs: ["biological_sex"]).externalRecords,
            [selected]
        )
        XCTAssertTrue(archive.hasRecordsOrFailures)

        let canonical = try HealthKitRecordArchiveSerializer.string(for: archive)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(canonical.utf8)) as? [String: Any]
        )
        let externalRecords = try XCTUnwrap(object["external_records"] as? [[String: Any]])
        XCTAssertEqual(externalRecords.count, 2)
        let serialized = try HealthKitRecordArchiveSerializer.externalRecordString(for: selected)
        XCTAssertFalse(serialized.contains("original_uuid"))
        XCTAssertFalse(serialized.contains("source_revision"))
        XCTAssertFalse(serialized.contains("device"))
        XCTAssertTrue(serialized.contains("characteristic_singleton"))

        let healthData = HealthData(
            date: dayStart,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            healthKitRecordArchive: archive
        )
        let csv = healthData.toCSV()
        XCTAssertEqual(csv.components(separatedBy: "Raw HealthKit External Record").count - 1, 2)
        XCTAssertTrue(csv.contains(CSVFieldEscaper.escape(serialized)))
    }

    func testLegacyArchiveWithoutExternalRecordsDecodesEmpty() throws {
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: ownership
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any]
        )
        object.removeValue(forKey: "externalRecords")

        let decoded = try JSONDecoder().decode(
            HealthKitRecordArchive.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.externalRecords, [])
    }

    func testActivitySummaryMapperPreservesDateIdentityRingsGoalsModeAndPausedState() throws {
        let components = HealthKitDateComponentsValue(
            calendarIdentifier: "gregorian",
            timeZoneIdentifier: "America/Los_Angeles",
            era: 1,
            year: 2026,
            month: 7,
            day: 15
        )
        func quantity(_ value: Double, _ unit: String) -> HealthKitExactQuantityValue {
            HealthKitExactQuantityValue(value: value, unit: unit, rawDescription: "\(value) \(unit)")
        }
        let value = HealthKitActivitySummaryRecordValue(
            dateComponents: components,
            activityMoveModeRawValue: 2,
            activityMoveModeSymbolicValue: "appleMoveTime",
            paused: true,
            activeEnergyBurned: quantity(512.125, "kcal"),
            appleMoveTime: quantity(73.5, "min"),
            appleExerciseTime: quantity(41.25, "min"),
            appleStandHours: quantity(11, "count"),
            activeEnergyBurnedGoal: quantity(600, "kcal"),
            appleMoveTimeGoal: quantity(90, "min"),
            appleExerciseTimeGoal: quantity(30, "min"),
            exerciseTimeGoal: quantity(45, "min"),
            appleStandHoursGoal: quantity(12, "count"),
            standHoursGoal: quantity(10, "count")
        )

        let record = HealthKitExternalRecordMapper.activitySummary(
            value,
            objectTypeIdentifier: HealthKitRecordCatalog.activitySummaryIdentifier,
            selectedMetricIDs: ["activity_summary"]
        )

        XCTAssertEqual(record.externalIdentityKind, .activitySummaryDateComponents)
        XCTAssertEqual(
            record.externalIdentifier,
            "healthkit.activity_summary|calendar=gregorian|timezone=America/Los_Angeles|era=1|year=2026|month=7|day=15"
        )
        XCTAssertEqual(record.recordKind, .activitySummary)
        XCTAssertEqual(record.fields["paused"], .bool(true))
        XCTAssertEqual(record.fields["activeEnergyBurned"], quantity(512.125, "kcal").metadataValue)
        XCTAssertEqual(record.fields["appleMoveTime"], quantity(73.5, "min").metadataValue)
        XCTAssertEqual(record.fields["exerciseTimeGoal"], quantity(45, "min").metadataValue)
        XCTAssertEqual(record.fields["standHoursGoal"], quantity(10, "count").metadataValue)
        XCTAssertEqual(record.fields["activityMoveMode"], .dictionary([
            "rawValue": .signedInteger(2),
            "symbolicValue": .string("appleMoveTime"),
        ]))
        guard case .dictionary(let dateFields) = record.fields["dateComponents"] else {
            return XCTFail("Expected typed date components")
        }
        XCTAssertEqual(dateFields["calendarIdentifier"], .string("gregorian"))
        XCTAssertEqual(dateFields["timeZoneIdentifier"], .string("America/Los_Angeles"))
        XCTAssertEqual(dateFields["day"], .signedInteger(15))
    }

    func testCharacteristicSymbolMapsPreserveEveryRawValueIncludingUnknowns() {
        XCTAssertEqual(SystemHealthStoreAdapter.biologicalSexSymbol(rawValue: 1), "female")
        XCTAssertEqual(SystemHealthStoreAdapter.biologicalSexSymbol(rawValue: 2), "male")
        XCTAssertEqual(SystemHealthStoreAdapter.biologicalSexSymbol(rawValue: 3), "other")
        XCTAssertEqual(SystemHealthStoreAdapter.bloodTypeSymbol(rawValue: 1), "aPositive")
        XCTAssertEqual(SystemHealthStoreAdapter.bloodTypeSymbol(rawValue: 8), "oNegative")
        XCTAssertEqual(SystemHealthStoreAdapter.fitzpatrickSkinTypeSymbol(rawValue: 6), "typeVI")
        XCTAssertEqual(SystemHealthStoreAdapter.wheelchairUseSymbol(rawValue: 2), "yes")
        XCTAssertEqual(SystemHealthStoreAdapter.activityMoveModeSymbol(rawValue: 1), "activeEnergy")
        XCTAssertEqual(SystemHealthStoreAdapter.activityMoveModeSymbol(rawValue: 2), "appleMoveTime")
        XCTAssertNil(SystemHealthStoreAdapter.biologicalSexSymbol(rawValue: 999))
    }

    func testFoodCorrelationMapperPreservesMealEnvelopeFoodTypeAndEveryNutrientUUID() throws {
        let adapter = SystemHealthStoreAdapter()
        let foodType = try XCTUnwrap(HKObjectType.correlationType(forIdentifier: .food))
        let proteinType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .dietaryProtein))
        let energyType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed))
        let protein = HKQuantitySample(
            type: proteinType,
            quantity: HKQuantity(unit: .gram(), doubleValue: 28.25),
            start: dayStart,
            end: dayStart,
            metadata: ["component": "protein"]
        )
        let energy = HKQuantitySample(
            type: energyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 450.5),
            start: dayStart,
            end: dayStart,
            metadata: ["component": "energy"]
        )
        let correlation = HKCorrelation(
            type: foodType,
            start: dayStart,
            end: dayStart.addingTimeInterval(1),
            objects: [protein, energy],
            metadata: [HKMetadataKeyFoodType: "Lunch bowl"]
        )

        let records = adapter.canonicalFoodRecords(
            from: correlation,
            selectedMetricIDs: ["dietary_protein"]
        )
        XCTAssertEqual(records.count, 3)
        let parent = try XCTUnwrap(records.first { $0.originalUUID == correlation.uuid })
        XCTAssertEqual(parent.metadata[HKMetadataKeyFoodType], .string("Lunch bowl"))
        guard case .correlation(let componentUUIDs) = parent.payload else {
            return XCTFail("Expected correlation payload")
        }
        XCTAssertEqual(Set(componentUUIDs), [protein.uuid, energy.uuid])
        XCTAssertEqual(Set(parent.relationships.compactMap(\.targetUUID)), [protein.uuid, energy.uuid])
        for component in [protein, energy] {
            let child = try XCTUnwrap(records.first { $0.originalUUID == component.uuid })
            XCTAssertEqual(child.relationships.first?.targetUUID, correlation.uuid)
            XCTAssertEqual(child.relationships.first?.role, component.sampleType.identifier)
            XCTAssertEqual(child.relationships.first?.kind, "parent")
            guard case .quantity(let payload) = child.payload else {
                return XCTFail("Expected enriched food quantity component")
            }
            XCTAssertEqual(payload.sampleSubclass, "HKCumulativeQuantitySample")
            XCTAssertEqual(payload.sampleKind, "cumulative")
            XCTAssertEqual(payload.count, 1)
            XCTAssertNotNil(payload.sum)
            XCTAssertNil(payload.series)
        }
    }

    func testManagerFoodGraphMergesStandaloneNutrientViewByUUIDAndMarksQuerySuccessful() async throws {
        let store = FakeHealthStore()
        let parentUUID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
        let childUUID = UUID(uuidString: "81000000-0000-0000-0000-000000000002")!
        let extraTarget = UUID(uuidString: "81000000-0000-0000-0000-000000000003")!
        let parent = sourceRecord(
            uuid: parentUUID,
            identifier: HealthKitRecordCatalog.foodCorrelationIdentifier,
            kind: .correlation,
            payload: .correlation(componentUUIDs: [childUUID]),
            relationships: [HealthKitRecordRelationship(
                targetUUID: childUUID,
                role: HKQuantityTypeIdentifier.dietaryProtein.rawValue,
                kind: "component"
            )]
        )
        let foodChild = sourceRecord(
            uuid: childUUID,
            identifier: HKQuantityTypeIdentifier.dietaryProtein.rawValue,
            payload: .quantity(HealthKitQuantityPayload(value: 20, unit: "g")),
            relationships: [HealthKitRecordRelationship(
                targetUUID: parentUUID,
                role: HKQuantityTypeIdentifier.dietaryProtein.rawValue,
                kind: "parent"
            )]
        )
        let standaloneChild = sourceRecord(
            uuid: childUUID,
            identifier: HKQuantityTypeIdentifier.dietaryProtein.rawValue,
            payload: foodChild.payload,
            relationships: [HealthKitRecordRelationship(
                targetUUID: extraTarget,
                role: "standalone",
                kind: "queryView"
            )]
        )
        store.foodRecordResults = [parent, foodChild]
        store.quantityRecordResults[HKQuantityTypeIdentifier.dietaryProtein.rawValue] = [standaloneChild]

        let data = try await manager(store: store).fetchHealthData(
            for: dayStart,
            includeGranularData: true,
            metricSelection: selection(["dietary_protein"])
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .complete)
        XCTAssertEqual(Set(archive.records.map(\.originalUUID)), [parentUUID, childUUID])
        let merged = try XCTUnwrap(archive.records.first { $0.originalUUID == childUUID })
        XCTAssertEqual(merged.relationships.count, 2)
        XCTAssertTrue(merged.relationships.contains { $0.targetUUID == parentUUID })
        XCTAssertTrue(merged.relationships.contains { $0.targetUUID == extraTarget })
        let result = try XCTUnwrap(archive.queryResults.first {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.foodCorrelationIdentifier
        })
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.recordCount, 1)
        XCTAssertEqual(store.foodRecordQueries.count, 1)
    }

    func testEverySelectedCharacteristicExportsOnceWithRawValuesAndFullDOBComponents() async throws {
        let store = FakeHealthStore()
        let dob = HealthKitExternalRecordMapper.characteristic(
            objectTypeIdentifier: HealthKitRecordCatalog.dateOfBirthIdentifier,
            selectedMetricIDs: ["date_of_birth"],
            fields: ["dateComponents": HealthKitDateComponentsValue(
                calendarIdentifier: "gregorian",
                timeZoneIdentifier: "America/New_York",
                era: 1,
                year: 1990,
                month: 4,
                day: 3,
                hour: 12,
                minute: 30
            ).metadataValue]
        )
        let fixtures: [(String, String, Int64, String)] = [
            (HealthKitRecordCatalog.biologicalSexIdentifier, "biological_sex", 3, "other"),
            (HealthKitRecordCatalog.bloodTypeIdentifier, "blood_type", 5, "abPositive"),
            (HealthKitRecordCatalog.fitzpatrickSkinTypeIdentifier, "fitzpatrick_skin_type", 4, "typeIV"),
            (HealthKitRecordCatalog.wheelchairUseIdentifier, "wheelchair_use", 2, "yes"),
            (HealthKitRecordCatalog.activityMoveModeIdentifier, "activity_move_mode", 2, "appleMoveTime"),
        ]
        store.specializedRecordResult = HealthKitSpecializedRecordQueryResult(
            externalRecords: [dob] + fixtures.map {
                externalCharacteristic(identifier: $0.0, metricID: $0.1, rawValue: $0.2, symbolicValue: $0.3)
            }
        )

        let metricIDs = Set(["date_of_birth"] + fixtures.map(\.1))
        let data = try await manager(store: store).fetchHealthData(
            for: dayStart,
            includeGranularData: true,
            metricSelection: selection(metricIDs)
        )
        let records = try XCTUnwrap(data.healthKitRecordArchive?.externalRecords)
        XCTAssertEqual(records.count, 6)
        XCTAssertEqual(Set(records.map(\.externalIdentifier)).count, 6)
        let decodedDOB = try XCTUnwrap(records.first {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.dateOfBirthIdentifier
        })
        guard case .dictionary(let fields) = decodedDOB.fields["dateComponents"] else {
            return XCTFail("Expected full date components")
        }
        XCTAssertEqual(fields["year"], .signedInteger(1990))
        XCTAssertEqual(fields["hour"], .signedInteger(12))
        XCTAssertEqual(fields["timeZoneIdentifier"], .string("America/New_York"))
        for fixture in fixtures {
            let record = try XCTUnwrap(records.first { $0.objectTypeIdentifier == fixture.0 })
            XCTAssertEqual(record.fields["value"], .dictionary([
                "rawValue": .signedInteger(fixture.2),
                "symbolicValue": .string(fixture.3),
            ]))
        }
    }

    func testActivityAndProfileMetricsAreSelectableAndResolveExactAuthorizationTypes() throws {
        let expected: [(String, String, HealthKitRecordKind)] = [
            ("activity_summary", HealthKitRecordCatalog.activitySummaryIdentifier, .activitySummary),
            ("date_of_birth", HealthKitRecordCatalog.dateOfBirthIdentifier, .characteristic),
            ("biological_sex", HealthKitRecordCatalog.biologicalSexIdentifier, .characteristic),
            ("blood_type", HealthKitRecordCatalog.bloodTypeIdentifier, .characteristic),
            ("fitzpatrick_skin_type", HealthKitRecordCatalog.fitzpatrickSkinTypeIdentifier, .characteristic),
            ("wheelchair_use", HealthKitRecordCatalog.wheelchairUseIdentifier, .characteristic),
            ("activity_move_mode", HealthKitRecordCatalog.activityMoveModeIdentifier, .characteristic),
        ]

        for (metricID, identifier, kind) in expected {
            let metric = try XCTUnwrap(HealthMetrics.all.first { $0.id == metricID })
            XCTAssertTrue(metric.isArchiveOnly)
            let plan = HealthKitRecordCatalog.attributedSelectionPlan(enabledMetricIDs: [metricID])
            XCTAssertEqual(plan.count, 1)
            let entry = try XCTUnwrap(plan.first)
            XCTAssertEqual(entry.objectTypeIdentifier, identifier)
            XCTAssertEqual(entry.recordKind, kind)
            XCTAssertEqual(entry.directMetricIDs, [metricID])
            let resolved = try XCTUnwrap(HealthKitRecordCatalog.resolveObjectType(entry.descriptor))
            XCTAssertEqual(resolved.identifier, identifier)
            if kind == .activitySummary {
                XCTAssertTrue(resolved is HKActivitySummaryType)
            } else {
                XCTAssertTrue(resolved is HKCharacteristicType)
            }
        }
    }

    func testDailyArchiveWithoutExplicitSelectionDoesNotQueryProfileCharacteristics() async throws {
        let store = FakeHealthStore()
        store.specializedRecordResult = HealthKitSpecializedRecordQueryResult(
            externalRecords: [externalCharacteristic(
                identifier: HealthKitRecordCatalog.biologicalSexIdentifier,
                metricID: "biological_sex",
                rawValue: 1,
                symbolicValue: "female"
            )]
        )

        let data = try await manager(store: store).fetchHealthData(
            for: dayStart,
            includeGranularData: true
        )

        XCTAssertTrue(data.healthKitRecordArchive?.externalRecords.isEmpty == true)
        XCTAssertFalse(store.specializedRecordQueries.flatMap(\.entries).contains {
            $0.recordKind == .characteristic
        })
        XCTAssertTrue(store.specializedRecordQueries.flatMap(\.entries).contains {
            $0.recordKind == .activitySummary
        })
    }

    func testSpecializedFailureIsIsolatedFromSuccessfulExternalProfileRecord() async throws {
        let store = FakeHealthStore()
        let profile = externalCharacteristic(
            identifier: HealthKitRecordCatalog.biologicalSexIdentifier,
            metricID: "biological_sex",
            rawValue: 1,
            symbolicValue: "female"
        )
        let interval = HealthKitQueryInterval(startDate: dayStart, endDate: dayStart.addingTimeInterval(86_400))
        store.specializedRecordResult = HealthKitSpecializedRecordQueryResult(
            externalRecords: [profile],
            recordQueryResults: [HealthKitQueryResult(
                identifier: HealthKitRecordCatalog.activitySummaryIdentifier,
                objectTypeIdentifier: HealthKitRecordCatalog.activitySummaryIdentifier,
                operation: "queryActivitySummaryRecords",
                metricIDs: ["activity_summary"],
                interval: interval,
                status: .failure,
                recordCount: 0,
                error: HealthKitQueryError(
                    domain: "ActivityFixture",
                    code: 91,
                    description: "Activity summary query failed"
                )
            )]
        )

        let data = try await manager(store: store).fetchHealthData(
            for: dayStart,
            includeGranularData: true,
            metricSelection: selection(["activity_summary", "biological_sex"])
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .partial)
        XCTAssertEqual(archive.externalRecords.count, 1)
        XCTAssertEqual(archive.externalRecords.first?.objectTypeIdentifier, HealthKitRecordCatalog.biologicalSexIdentifier)
        XCTAssertEqual(archive.queryResults.filter { $0.status == .failure }.count, 1)
        XCTAssertEqual(data.partialFailures.filter { $0.dataType.contains("specialized") }.count, 1)
    }

    private var ownership: HealthKitDailyOwnershipMetadata {
        HealthKitDailyOwnershipMetadata(
            ownerDate: "2027-01-15",
            intervalStart: dayStart,
            intervalEnd: dayStart.addingTimeInterval(86_400),
            calendarTimeZoneIdentifier: "UTC"
        )
    }

    private func externalCharacteristic(
        identifier: String,
        metricID: String,
        rawValue: Int64,
        symbolicValue: String
    ) -> HealthKitExternalRecord {
        HealthKitExternalRecordMapper.characteristic(
            objectTypeIdentifier: identifier,
            selectedMetricIDs: [metricID],
            fields: ["value": HealthKitExternalRecordMapper.rawEnum(
                rawValue: rawValue,
                symbolicValue: symbolicValue
            )]
        )
    }

    private func sourceRecord(
        uuid: UUID,
        identifier: String,
        kind: HealthKitRecordKind = .quantity,
        payload: HealthKitRecordPayload,
        relationships: [HealthKitRecordRelationship]
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: identifier,
            recordKind: kind,
            selectedMetricIDs: ["fixture"],
            includedBecause: .selectedMetric,
            startDate: dayStart.addingTimeInterval(60),
            endDate: dayStart.addingTimeInterval(61),
            sourceRevision: HealthKitSourceRevision(
                name: "Fixture",
                bundleIdentifier: "com.example.fixture"
            ),
            payload: payload,
            relationships: relationships
        )
    }

    private func manager(store: FakeHealthStore) -> HealthKitManager {
        let defaults = UserDefaults(suiteName: "HealthKitExternalRecordsTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: "healthKit.authorizationRequested")
        return HealthKitManager(store: store, userDefaults: defaults)
    }

    private func selection(_ metricIDs: Set<String>) -> MetricSelectionState {
        let result = MetricSelectionState()
        result.deselectAll()
        result.enabledMetrics = metricIDs
        return result
    }
}
