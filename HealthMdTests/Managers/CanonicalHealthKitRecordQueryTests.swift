import Foundation
import HealthKit
import XCTest
@testable import HealthMd

final class CanonicalHealthKitRecordQueryTests: XCTestCase {
    private enum FixtureError: Error, Equatable {
        case quantity
        case category
        case bloodPressure
        case stateOfMind
        case medication
    }

    private final class UnsupportedMetadataObject: NSObject {
        override var description: String { "unsupported-fixture" }
    }

    func testQuantitySampleMappingPreservesIdentityProvenanceDeviceAndTypedMetadata() throws {
        let adapter = SystemHealthStoreAdapter()
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .heartRate))
        let canonicalUnit = HKUnit.count().unitDivided(by: .minute())
        let device = HKDevice(
            name: "Chest Strap",
            manufacturer: "Acme",
            model: "HR-1",
            hardwareVersion: "2.0",
            firmwareVersion: "3.1",
            softwareVersion: "4.2",
            localIdentifier: "local-device-id",
            udiDeviceIdentifier: "udi-device-id"
        )
        let start = Date(timeIntervalSinceReferenceDate: 812_345_678.123_456_7)
        let end = Date(timeIntervalSinceReferenceDate: 812_345_679.987_654_3)
        let sessionEstimate = HKQuantity(unit: canonicalUnit, doubleValue: 71.125)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: canonicalUnit, doubleValue: 72.25),
            start: start,
            end: end,
            device: device,
            metadata: [
                "legacyString": "unchanged",
                HKMetadataKeyWasUserEntered: true,
                HKMetadataKeySessionEstimate: sessionEstimate,
            ]
        )

        let record = adapter.canonicalQuantityRecord(
            from: sample,
            canonicalUnit: canonicalUnit,
            selectedMetricIDs: ["heart_rate"]
        )

        XCTAssertEqual(record.originalUUID, sample.uuid)
        XCTAssertEqual(record.objectTypeIdentifier, sample.quantityType.identifier)
        XCTAssertEqual(record.recordKind, .quantity)
        XCTAssertEqual(record.selectedMetricIDs, ["heart_rate"])
        XCTAssertEqual(record.includedBecause, .selectedMetric)
        XCTAssertEqual(record.startDate, start)
        XCTAssertEqual(record.endDate, end)
        XCTAssertEqual(record.startDate.timeIntervalSinceReferenceDate, start.timeIntervalSinceReferenceDate)
        XCTAssertEqual(record.endDate.timeIntervalSinceReferenceDate, end.timeIntervalSinceReferenceDate)
        XCTAssertEqual(record.hasUndeterminedDuration, sample.hasUndeterminedDuration)
        assertSourceRevision(record.sourceRevision, equals: sample.sourceRevision)
        XCTAssertEqual(
            record.device,
            HealthKitDeviceProvenance(
                name: "Chest Strap",
                manufacturer: "Acme",
                model: "HR-1",
                hardwareVersion: "2.0",
                firmwareVersion: "3.1",
                softwareVersion: "4.2",
                localIdentifier: "local-device-id",
                udiDeviceIdentifier: "udi-device-id"
            )
        )
        XCTAssertEqual(record.metadata["legacyString"], .string("unchanged"))
        XCTAssertEqual(record.metadata[HKMetadataKeyWasUserEntered], .bool(true))
        XCTAssertEqual(
            record.metadata[HKMetadataKeySessionEstimate],
            .quantity(HealthKitMetadataQuantity(
                value: 71.125,
                unit: canonicalUnit.unitString,
                rawDescription: sessionEstimate.description
            ))
        )
        XCTAssertEqual(
            record.payload,
            .quantity(HealthKitQuantityPayload(value: 72.25, unit: canonicalUnit.unitString))
        )
        XCTAssertTrue(record.relationships.isEmpty)
    }

    func testCategorySampleMappingPreservesRawValueIdentityAndProvenance() throws {
        let adapter = SystemHealthStoreAdapter()
        let type = try XCTUnwrap(HKCategoryType.categoryType(forIdentifier: .sleepAnalysis))
        let device = HKDevice(
            name: "Watch",
            manufacturer: "Acme",
            model: "Sleep-1",
            hardwareVersion: "1",
            firmwareVersion: "2",
            softwareVersion: "3",
            localIdentifier: "sleep-local",
            udiDeviceIdentifier: "sleep-udi"
        )
        let start = Date(timeIntervalSinceReferenceDate: 700_000_000.123_456_7)
        let end = Date(timeIntervalSinceReferenceDate: 700_003_600.765_432_1)
        let rawValue = HKCategoryValueSleepAnalysis.asleepREM.rawValue
        let sample = HKCategorySample(
            type: type,
            value: rawValue,
            start: start,
            end: end,
            device: device,
            metadata: ["legacyString": "still-unchanged"]
        )

        let record = adapter.canonicalCategoryRecord(
            from: sample,
            selectedMetricIDs: ["sleep_analysis"]
        )

        XCTAssertEqual(record.originalUUID, sample.uuid)
        XCTAssertEqual(record.objectTypeIdentifier, sample.categoryType.identifier)
        XCTAssertEqual(record.recordKind, .category)
        XCTAssertEqual(record.selectedMetricIDs, ["sleep_analysis"])
        XCTAssertEqual(record.includedBecause, .selectedMetric)
        XCTAssertEqual(record.startDate, start)
        XCTAssertEqual(record.endDate, end)
        XCTAssertEqual(record.hasUndeterminedDuration, sample.hasUndeterminedDuration)
        assertSourceRevision(record.sourceRevision, equals: sample.sourceRevision)
        XCTAssertEqual(
            record.device,
            HealthKitDeviceProvenance(
                name: "Watch",
                manufacturer: "Acme",
                model: "Sleep-1",
                hardwareVersion: "1",
                firmwareVersion: "2",
                softwareVersion: "3",
                localIdentifier: "sleep-local",
                udiDeviceIdentifier: "sleep-udi"
            )
        )
        XCTAssertEqual(record.metadata["legacyString"], .string("still-unchanged"))
        XCTAssertEqual(
            record.payload,
            .category(HealthKitCategoryPayload(rawValue: Int64(rawValue), symbolicValue: nil))
        )
    }

    func testBloodPressureCorrelationMappingPreservesExactGraph() throws {
        let adapter = SystemHealthStoreAdapter()
        let correlationType = try XCTUnwrap(HKObjectType.correlationType(forIdentifier: .bloodPressure))
        let systolicType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic))
        let diastolicType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic))
        let unit = HKUnit.millimeterOfMercury()
        let device = HKDevice(
            name: "Pressure Cuff",
            manufacturer: "Acme",
            model: "BP-3",
            hardwareVersion: "1",
            firmwareVersion: "2",
            softwareVersion: "3",
            localIdentifier: "bp-local",
            udiDeviceIdentifier: "bp-udi"
        )
        let start = Date(timeIntervalSinceReferenceDate: 812_000_000.125)
        let end = start.addingTimeInterval(0.75)
        let firstSystolic = HKQuantitySample(
            type: systolicType,
            quantity: HKQuantity(unit: unit, doubleValue: 121),
            start: start,
            end: end,
            device: device,
            metadata: ["component": "first-systolic"]
        )
        let diastolic = HKQuantitySample(
            type: diastolicType,
            quantity: HKQuantity(unit: unit, doubleValue: 79),
            start: start,
            end: end,
            device: device,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        let components: Set<HKSample> = [firstSystolic, diastolic]
        let correlation = HKCorrelation(
            type: correlationType,
            start: start,
            end: end,
            objects: components,
            device: device,
            metadata: ["session": "triple-reading"]
        )

        let records = adapter.canonicalBloodPressureRecords(
            from: correlation,
            selectedMetricIDs: ["blood_pressure_systolic", "blood_pressure_diastolic"]
        )

        XCTAssertEqual(records.count, 3)
        let parent = try XCTUnwrap(records.first { $0.originalUUID == correlation.uuid })
        XCTAssertEqual(parent.recordKind, .correlation)
        XCTAssertEqual(parent.startDate, start)
        XCTAssertEqual(parent.endDate, end)
        XCTAssertEqual(parent.hasUndeterminedDuration, correlation.hasUndeterminedDuration)
        XCTAssertEqual(parent.metadata["session"], .string("triple-reading"))
        XCTAssertEqual(parent.device?.localIdentifier, "bp-local")
        assertSourceRevision(parent.sourceRevision, equals: correlation.sourceRevision)

        let childUUIDs = Set(components.map(\.uuid))
        guard case .correlation(let payloadUUIDs) = parent.payload else {
            return XCTFail("Expected a correlation payload")
        }
        XCTAssertEqual(Set(payloadUUIDs), childUUIDs)
        XCTAssertEqual(payloadUUIDs.count, 2)
        XCTAssertEqual(Set(parent.relationships.compactMap(\.targetUUID)), childUUIDs)
        XCTAssertEqual(parent.relationships.filter { $0.role == "systolic" }.count, 1)
        XCTAssertEqual(parent.relationships.filter { $0.role == "diastolic" }.count, 1)
        XCTAssertTrue(parent.relationships.allSatisfy { $0.kind == "component" })

        for component in [firstSystolic, diastolic] {
            let child = try XCTUnwrap(records.first { $0.originalUUID == component.uuid })
            XCTAssertEqual(child.startDate, component.startDate)
            XCTAssertEqual(child.endDate, component.endDate)
            XCTAssertEqual(child.hasUndeterminedDuration, component.hasUndeterminedDuration)
            XCTAssertEqual(child.relationships.count, 1)
            XCTAssertEqual(child.relationships[0].targetUUID, correlation.uuid)
            XCTAssertEqual(child.relationships[0].kind, "parent")
            let expectedRole = component.quantityType == systolicType ? "systolic" : "diastolic"
            XCTAssertEqual(child.relationships[0].role, expectedRole)
            XCTAssertEqual(child.device?.udiDeviceIdentifier, "bp-udi")
            assertSourceRevision(child.sourceRevision, equals: component.sourceRevision)
        }
    }

    func testStateOfMindMappingPreservesRawAndSymbolicValuesAndSourceIdentity() throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let adapter = SystemHealthStoreAdapter()
        let timestamp = Date(timeIntervalSinceReferenceDate: 812_100_000.987_654_3)
        let sample = HKStateOfMind(
            date: timestamp,
            kind: .dailyMood,
            valence: 0.63,
            labels: [.happy, .grateful],
            associations: [.family, .work],
            metadata: [HKMetadataKeyWasUserEntered: true, "note": "exact"]
        )

        let record = adapter.canonicalStateOfMindRecord(
            from: sample,
            selectedMetricIDs: ["state_of_mind_entries"]
        )

        XCTAssertEqual(record.originalUUID, sample.uuid)
        XCTAssertEqual(record.objectTypeIdentifier, HealthKitRecordCatalog.stateOfMindIdentifier)
        XCTAssertEqual(record.startDate, sample.startDate)
        XCTAssertEqual(record.endDate, sample.endDate)
        XCTAssertEqual(record.startDate.timeIntervalSinceReferenceDate, timestamp.timeIntervalSinceReferenceDate)
        XCTAssertEqual(record.hasUndeterminedDuration, sample.hasUndeterminedDuration)
        assertSourceRevision(record.sourceRevision, equals: sample.sourceRevision)
        XCTAssertNil(record.device)
        XCTAssertEqual(record.metadata[HKMetadataKeyWasUserEntered], .bool(true))
        XCTAssertEqual(record.metadata["note"], .string("exact"))

        guard case .structured(let payloadKind, let fields) = record.payload else {
            return XCTFail("Expected structured State of Mind payload")
        }
        XCTAssertEqual(payloadKind, "stateOfMind")
        XCTAssertEqual(fields["valence"], .floatingPoint(sample.valence))
        XCTAssertEqual(
            fields["kind"],
            .dictionary([
                "rawValue": .signedInteger(Int64(sample.kind.rawValue)),
                "symbolicValue": .string("dailyMood"),
            ])
        )
        XCTAssertEqual(
            fields["valenceClassification"],
            .dictionary([
                "rawValue": .signedInteger(Int64(sample.valenceClassification.rawValue)),
                "symbolicValue": .string("pleasant"),
            ])
        )
        XCTAssertEqual(
            fields["labels"],
            .array([
                .dictionary(["rawValue": .signedInteger(Int64(HKStateOfMind.Label.happy.rawValue)), "symbolicValue": .string("happy")]),
                .dictionary(["rawValue": .signedInteger(Int64(HKStateOfMind.Label.grateful.rawValue)), "symbolicValue": .string("grateful")]),
            ])
        )
        XCTAssertEqual(
            fields["associations"],
            .array([
                .dictionary(["rawValue": .signedInteger(Int64(HKStateOfMind.Association.family.rawValue)), "symbolicValue": .string("family")]),
                .dictionary(["rawValue": .signedInteger(Int64(HKStateOfMind.Association.work.rawValue)), "symbolicValue": .string("work")]),
            ])
        )
    }

    func testTypedMetadataPreservesSupportedRecursiveValuesAndUnknowns() throws {
        let exactDate = Date(timeIntervalSinceReferenceDate: 812_345_678.123_456_7)
        let exactData = Data([0x00, 0x7f, 0xff])
        let exactURL = try XCTUnwrap(URL(string: "https://example.com/path?q=health"))
        let knownQuantity = HKQuantity(unit: .meterUnit(with: .centi), doubleValue: 250)
        let opaqueQuantity = HKQuantity(unit: .gram(), doubleValue: 7.5)
        let unsupported = UnsupportedMetadataObject()

        let converted = SystemHealthStoreAdapter.typedMetadata([
            "string": "value",
            "bool": NSNumber(value: true),
            "signed": NSNumber(value: Int64.min),
            "unsigned": NSNumber(value: UInt64.max),
            "integerOne": NSNumber(value: Int64(1)),
            "double": NSNumber(value: 123.5),
            "infinite": NSNumber(value: Double.infinity),
            "date": exactDate,
            "data": exactData,
            "url": exactURL,
            "array": [NSNumber(value: Int16(-7)), "nested", NSNumber(value: false)] as [Any],
            "dictionary": [
                "nestedSigned": NSNumber(value: Int32.max),
                "nestedString": "dictionary-value",
            ] as [String: Any],
            "unsupported": unsupported,
            HKMetadataKeyElevationAscended: knownQuantity,
            "opaqueQuantity": opaqueQuantity,
        ])

        XCTAssertEqual(converted["string"], .string("value"))
        XCTAssertEqual(converted["bool"], .bool(true))
        XCTAssertEqual(converted["signed"], .signedInteger(Int64.min))
        XCTAssertEqual(converted["unsigned"], .unsignedInteger(UInt64.max))
        XCTAssertEqual(converted["integerOne"], .signedInteger(1), "A numeric NSNumber must not bridge to Bool")
        XCTAssertEqual(converted["double"], .floatingPoint(123.5))
        if case .unsupported = converted["infinite"] {
            // Non-finite numbers cannot be represented as canonical floating values.
        } else {
            XCTFail("Expected non-finite metadata to remain visible as unsupported")
        }
        XCTAssertEqual(converted["date"], .date(exactDate))
        if case .date(let convertedDate) = converted["date"] {
            XCTAssertEqual(convertedDate.timeIntervalSinceReferenceDate, exactDate.timeIntervalSinceReferenceDate)
        } else {
            XCTFail("Expected typed Date metadata")
        }
        XCTAssertEqual(converted["data"], .data(exactData))
        XCTAssertEqual(converted["url"], .url(exactURL))
        XCTAssertEqual(
            converted["array"],
            .array([.signedInteger(-7), .string("nested"), .bool(false)])
        )
        XCTAssertEqual(
            converted["dictionary"],
            .dictionary([
                "nestedSigned": .signedInteger(Int64(Int32.max)),
                "nestedString": .string("dictionary-value"),
            ])
        )
        if case .unsupported(let typeName, let description) = converted["unsupported"] {
            XCTAssertTrue(typeName.contains("UnsupportedMetadataObject"))
            XCTAssertEqual(description, "unsupported-fixture")
        } else {
            XCTFail("Expected unsupported objects to remain explicitly typed")
        }
        XCTAssertEqual(
            converted[HKMetadataKeyElevationAscended],
            .quantity(HealthKitMetadataQuantity(
                value: 2.5,
                unit: HKUnit.meter().unitString,
                rawDescription: knownQuantity.description
            ))
        )
        XCTAssertEqual(
            converted["opaqueQuantity"],
            .quantity(HealthKitMetadataQuantity(
                value: nil,
                unit: nil,
                rawDescription: opaqueQuantity.description
            )),
            "An arbitrary HKQuantity must not be assigned a guessed unit or value"
        )
    }

    func testFakeCanonicalQueriesSortThenLimitAndPreserveDuplicateLookingUUIDs() async throws {
        let store = FakeHealthStore()
        let typeIdentifier = HKQuantityTypeIdentifier.heartRate.rawValue
        let start = Date(timeIntervalSinceReferenceDate: 100.25)
        let uuid1 = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let uuid2 = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let uuid3 = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let first = makeRecord(uuid: uuid1, typeIdentifier: typeIdentifier, kind: .quantity, startDate: start)
        let duplicateLooking = makeRecord(uuid: uuid2, typeIdentifier: typeIdentifier, kind: .quantity, startDate: start)
        let later = makeRecord(uuid: uuid3, typeIdentifier: typeIdentifier, kind: .quantity, startDate: start.addingTimeInterval(1))
        store.quantityRecordResults[typeIdentifier] = [later, duplicateLooking, first]
        let predicate = HKQuery.predicateForSamples(withStart: start, end: start.addingTimeInterval(60))
        let selectedMetricIDs = ["heart_rate", "resting_heart_rate"]

        let records = try await store.queryQuantityRecords(
            identifier: .heartRate,
            predicate: predicate,
            selectedMetricIDs: selectedMetricIDs,
            limit: 2
        )

        XCTAssertEqual(records.map(\.originalUUID), [uuid1, uuid2])
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].selectedMetricIDs, selectedMetricIDs)
        XCTAssertEqual(records[1].selectedMetricIDs, selectedMetricIDs)
        XCTAssertEqual(store.quantityRecordQueries.count, 1)
        XCTAssertEqual(store.queriedQuantityRecordIdentifiers, [typeIdentifier])
        XCTAssertEqual(store.quantityRecordQueries[0].identifier, typeIdentifier)
        XCTAssertTrue(store.quantityRecordQueries[0].predicate === predicate)
        XCTAssertEqual(store.quantityRecordQueries[0].selectedMetricIDs, selectedMetricIDs)
        XCTAssertEqual(store.quantityRecordQueries[0].limit, 2)
    }

    func testFakeCanonicalCategoryQueryTracksSelectionAndPreservesLegacyStringSamples() async throws {
        let store = FakeHealthStore()
        let categoryIdentifier = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        let record = makeRecord(
            uuid: UUID(),
            typeIdentifier: categoryIdentifier,
            kind: .category,
            startDate: Date(timeIntervalSinceReferenceDate: 200)
        )
        store.categoryRecordResults[categoryIdentifier] = [record]
        store.categorySampleResults[categoryIdentifier] = [
            CategorySampleValue(
                value: 4,
                startDate: record.startDate,
                endDate: record.endDate,
                metadata: ["legacy": "category-string"]
            )
        ]
        store.quantitySampleResults[HKQuantityTypeIdentifier.heartRate.rawValue] = [
            QuantitySampleValue(
                value: 70,
                startDate: record.startDate,
                endDate: record.endDate,
                metadata: ["legacy": "quantity-string"]
            )
        ]

        let canonical = try await store.queryCategoryRecords(
            identifier: .sleepAnalysis,
            predicate: nil,
            selectedMetricIDs: ["sleep_analysis"],
            limit: nil
        )
        let legacyCategory = try await store.queryCategorySamples(
            identifier: .sleepAnalysis,
            predicate: nil,
            ascending: true,
            limit: nil
        )
        let legacyQuantity = try await store.queryQuantitySamples(
            identifier: .heartRate,
            predicate: nil,
            ascending: true,
            limit: nil
        )

        XCTAssertEqual(canonical.count, 1)
        XCTAssertEqual(canonical[0].selectedMetricIDs, ["sleep_analysis"])
        XCTAssertEqual(store.categoryRecordQueries.count, 1)
        XCTAssertEqual(store.queriedCategoryRecordIdentifiers, [categoryIdentifier])
        XCTAssertEqual(store.categoryRecordQueries[0].identifier, categoryIdentifier)
        XCTAssertEqual(store.categoryRecordQueries[0].selectedMetricIDs, ["sleep_analysis"])
        XCTAssertNil(store.categoryRecordQueries[0].limit)
        XCTAssertEqual(legacyCategory[0].metadata["legacy"], "category-string")
        XCTAssertEqual(legacyQuantity[0].metadata["legacy"], "quantity-string")
    }

    func testFakeCanonicalQueriesThrowPerIdentifierErrors() async {
        let store = FakeHealthStore()
        store.errorsForQuantityRecords[HKQuantityTypeIdentifier.heartRate.rawValue] = FixtureError.quantity
        store.errorsForCategoryRecords[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = FixtureError.category

        do {
            _ = try await store.queryQuantityRecords(
                identifier: .heartRate,
                predicate: nil,
                selectedMetricIDs: ["heart_rate"],
                limit: nil
            )
            XCTFail("Expected the configured quantity error")
        } catch let error as FixtureError {
            XCTAssertEqual(error, .quantity)
        } catch {
            XCTFail("Unexpected quantity error: \(error)")
        }

        do {
            _ = try await store.queryCategoryRecords(
                identifier: .sleepAnalysis,
                predicate: nil,
                selectedMetricIDs: ["sleep_analysis"],
                limit: nil
            )
            XCTFail("Expected the configured category error")
        } catch let error as FixtureError {
            XCTAssertEqual(error, .category)
        } catch {
            XCTFail("Unexpected category error: \(error)")
        }

        XCTAssertEqual(store.quantityRecordQueries.count, 1)
        XCTAssertEqual(store.categoryRecordQueries.count, 1)
    }

    func testFakeSpecializedCanonicalQueriesTrackAndThrowIndependently() async {
        let store = FakeHealthStore()
        store.errorForBloodPressureRecords = FixtureError.bloodPressure
        store.errorForStateOfMindRecords = FixtureError.stateOfMind
        store.errorForMedicationRecords = FixtureError.medication

        do {
            _ = try await store.queryBloodPressureRecords(
                predicate: nil,
                selectedMetricIDs: ["blood_pressure_systolic"],
                limit: 3
            )
            XCTFail("Expected blood pressure error")
        } catch let error as FixtureError {
            XCTAssertEqual(error, .bloodPressure)
        } catch {
            XCTFail("Unexpected blood pressure error: \(error)")
        }

        do {
            _ = try await store.queryStateOfMindRecords(
                predicate: nil,
                selectedMetricIDs: ["state_of_mind_entries"],
                limit: 4
            )
            XCTFail("Expected State of Mind error")
        } catch let error as FixtureError {
            XCTAssertEqual(error, .stateOfMind)
        } catch {
            XCTFail("Unexpected State of Mind error: \(error)")
        }

        do {
            _ = try await store.queryMedicationDoseEventRecords(
                predicate: nil,
                selectedMetricIDs: ["medications"],
                limit: 5
            )
            XCTFail("Expected medication error")
        } catch let error as FixtureError {
            XCTAssertEqual(error, .medication)
        } catch {
            XCTFail("Unexpected medication error: \(error)")
        }

        XCTAssertEqual(store.bloodPressureRecordQueries.count, 1)
        XCTAssertEqual(store.bloodPressureRecordQueries[0].selectedMetricIDs, ["blood_pressure_systolic"])
        XCTAssertEqual(store.bloodPressureRecordQueries[0].limit, 3)
        XCTAssertEqual(store.stateOfMindRecordQueries.count, 1)
        XCTAssertEqual(store.stateOfMindRecordQueries[0].limit, 4)
        XCTAssertEqual(store.medicationRecordQueries.count, 1)
        XCTAssertEqual(store.medicationRecordQueries[0].limit, 5)
    }

    private func assertSourceRevision(
        _ actual: HealthKitSourceRevision,
        equals expected: HKSourceRevision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.name, expected.source.name, file: file, line: line)
        XCTAssertEqual(actual.bundleIdentifier, expected.source.bundleIdentifier, file: file, line: line)
        XCTAssertEqual(actual.version, expected.version, file: file, line: line)
        XCTAssertEqual(actual.productType, expected.productType, file: file, line: line)
        // Public sample factories leave the numeric contents undefined until a
        // sample is saved, but the adapter must still preserve the public field
        // in its structured major/minor/patch representation.
        XCTAssertNotNil(actual.operatingSystemVersion, file: file, line: line)
    }

    private func makeRecord(
        uuid: UUID,
        typeIdentifier: String,
        kind: HealthKitRecordKind,
        startDate: Date
    ) -> HealthKitRecord {
        let payload: HealthKitRecordPayload = kind == .quantity
            ? .quantity(HealthKitQuantityPayload(value: 72, unit: "count/min"))
            : .category(HealthKitCategoryPayload(rawValue: 4, symbolicValue: nil))
        return HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: typeIdentifier,
            recordKind: kind,
            selectedMetricIDs: ["fixture-selection"],
            includedBecause: .selectedMetric,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1),
            sourceRevision: HealthKitSourceRevision(
                name: "Fixture",
                bundleIdentifier: "com.example.fixture"
            ),
            payload: payload
        )
    }
}
