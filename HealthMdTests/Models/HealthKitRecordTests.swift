import XCTest
@testable import HealthMd

final class HealthKitRecordTests: XCTestCase {
    private static let dayStart = Date(timeIntervalSince1970: 1_800_000_000)
    private static let dayEnd = dayStart.addingTimeInterval(86_400)
    private static let firstUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let secondUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let thirdUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let fourthUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private static let fifthUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    private static let sixthUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!

    func testTypedMetadataRoundTripsEveryCaseWithoutNumericCollapse() throws {
        let fixedDate = Self.dayStart.addingTimeInterval(123.456)
        let values: [HealthKitMetadataValue] = [
            .null,
            .string("literal"),
            .bool(true),
            .signedInteger(.min),
            .unsignedInteger(.max),
            .floatingPoint(12.75),
            .date(fixedDate),
            .data(Data([0x00, 0x7f, 0xff])),
            .url(try XCTUnwrap(URL(string: "https://example.com/record?id=1"))),
            .quantity(HealthKitMetadataQuantity(value: 120.25, unit: "mmHg", rawDescription: "120.25 mmHg")),
            .array([.signedInteger(-7), .null, .string("nested")]),
            .dictionary([
                "maximum": .unsignedInteger(.max),
                "minimum": .signedInteger(.min),
                "nested": .dictionary(["flag": .bool(false)])
            ]),
            .unsupported(typeName: "HKFutureMetadata", description: "<future value>")
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(values)
        let decoded = try decoder.decode([HealthKitMetadataValue].self, from: encoded)

        XCTAssertEqual(decoded, values)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains(String(Int64.min)))
        XCTAssertTrue(json.contains(String(UInt64.max)))
        XCTAssertTrue(json.contains("\"type\":\"signedInteger\""))
        XCTAssertTrue(json.contains("\"type\":\"unsignedInteger\""))
    }

    func testEveryPayloadCaseRoundTripsAndFutureTagDecodesAsUnknown() throws {
        let payloads: [HealthKitRecordPayload] = [
            .quantity(HealthKitQuantityPayload(value: 72.5, unit: "count/min")),
            .category(HealthKitCategoryPayload(rawValue: 3, symbolicValue: "asleepREM")),
            .correlation(componentUUIDs: [Self.secondUUID, Self.firstUUID]),
            .structured(kind: "workout", fields: [
                "activityType": .unsignedInteger(37),
                "indoor": .bool(true)
            ]),
            .binaryArtifactReference(HealthKitBinaryArtifactReference(
                identifier: "artifacts/ecg-1.dat",
                mediaType: "application/octet-stream",
                filename: "ecg.dat",
                byteCount: 4_096,
                sha256: "0123456789abcdef"
            )),
            .unknown(kind: "futureKnownByAdapter", fields: ["raw": .data(Data([1, 2, 3]))])
        ]

        let encoded = try JSONEncoder().encode(payloads)
        let decoded = try JSONDecoder().decode([HealthKitRecordPayload].self, from: encoded)
        XCTAssertEqual(decoded, payloads)

        let futurePayloadJSON = Data(#"""
        {
          "type": "HKFuturePayload",
          "fields": {
            "exact": { "type": "unsignedInteger", "value": 18446744073709551615 },
            "optional": { "type": "null" }
          }
        }
        """#.utf8)
        let futurePayload = try JSONDecoder().decode(HealthKitRecordPayload.self, from: futurePayloadJSON)
        XCTAssertEqual(futurePayload, .unknown(kind: "HKFuturePayload", fields: [
            "exact": .unsignedInteger(.max),
            "optional": .null
        ]))
    }

    func testFullArchiveRoundTripPreservesProvenanceDeviceRelationshipsAndInventory() throws {
        let source = HealthKitSourceRevision(
            name: "Health",
            bundleIdentifier: "com.apple.Health",
            version: "19.0",
            productType: "iPhone18,1",
            operatingSystemVersion: "19.0.1"
        )
        let device = HealthKitDeviceProvenance(
            name: "Apple Watch",
            manufacturer: "Apple Inc.",
            model: "Watch",
            hardwareVersion: "Watch7,5",
            firmwareVersion: "12.0",
            softwareVersion: "12.0.1",
            localIdentifier: "local-watch",
            udiDeviceIdentifier: "udi-watch"
        )
        let record = HealthKitRecord(
            originalUUID: Self.firstUUID,
            objectTypeIdentifier: "HKQuantityTypeIdentifierHeartRate",
            recordKind: .quantity,
            selectedMetricIDs: ["heart_rate_max", "heart_rate_avg", "heart_rate_avg"],
            includedBecause: .selectedMetric,
            startDate: Self.dayStart.addingTimeInterval(60),
            endDate: Self.dayStart.addingTimeInterval(61.25),
            sourceRevision: source,
            device: device,
            metadata: [
                "HKMetadataKeyWasUserEntered": .bool(false),
                "sequence": .signedInteger(9)
            ],
            payload: .quantity(HealthKitQuantityPayload(value: 71.25, unit: "count/min")),
            relationships: [
                HealthKitRecordRelationship(
                    targetExternalIdentifier: "rxnorm:617314",
                    role: "medication",
                    kind: "annotation",
                    targetOwnerDate: "2027-01-15"
                ),
                HealthKitRecordRelationship(
                    targetUUID: Self.secondUUID,
                    role: "component",
                    kind: "correlationComponent",
                    targetOwnerDate: "2027-01-15"
                )
            ]
        )
        let query = HealthKitQueryResult(
            identifier: "heart-rate-samples",
            objectTypeIdentifier: "HKQuantityTypeIdentifierHeartRate",
            operation: "sampleQuery",
            metricIDs: ["heart_rate_avg", "heart_rate_max"],
            interval: interval,
            status: .success,
            recordCount: 1
        )
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: ownership,
            records: [record],
            queryManifest: HealthKitQueryManifest(results: [query]),
            integrityWarnings: [HealthKitRecordIntegrityWarning(
                code: "cross-day-link",
                message: "Relationship target is owned by another day",
                metricIDs: ["heart_rate_avg"],
                recordUUIDs: [Self.firstUUID]
            )],
            medicationInventoryRecords: [HealthKitMedicationInventoryRecord(
                externalIdentifier: "rxnorm:617314",
                selectedMetricIDs: ["medications"],
                includedBecause: .relationshipDependency,
                displayName: "Vitamin D3",
                fields: ["archived": .bool(false), "dose": .string("1 tablet")]
            )]
        )

        let decoded = try JSONDecoder().decode(
            HealthKitRecordArchive.self,
            from: JSONEncoder().encode(archive)
        )

        XCTAssertEqual(decoded, archive)
        XCTAssertEqual(decoded.schemaIdentifier, "healthmd.healthkit_records")
        XCTAssertEqual(decoded.recordSchemaVersion, 1)
        XCTAssertEqual(decoded.records.first?.sourceRevision, source)
        XCTAssertEqual(decoded.records.first?.device, device)
        XCTAssertEqual(decoded.records.first?.relationships.count, 2)
        XCTAssertEqual(decoded.records.first?.startDate, Self.dayStart.addingTimeInterval(60))
        XCTAssertEqual(decoded.records.first?.endDate, Self.dayStart.addingTimeInterval(61.25))
        XCTAssertEqual(decoded.medicationInventoryRecords.first?.externalIdentifier, "rxnorm:617314")
        XCTAssertEqual(decoded.dailyOwnership.ownerDate, "2027-01-15")
    }

    func testDuplicateLookingRecordsWithDifferentOriginalUUIDsBothSurvive() throws {
        let first = makeRecord(uuid: Self.firstUUID, metricIDs: ["steps"])
        let second = makeRecord(uuid: Self.secondUUID, metricIDs: ["steps"])
        let archive = makeArchive(records: [second, first])

        XCTAssertEqual(archive.records.map(\.originalUUID), [Self.firstUUID, Self.secondUUID])

        let decoded = try JSONDecoder().decode(
            HealthKitRecordArchive.self,
            from: JSONEncoder().encode(archive)
        )
        XCTAssertEqual(decoded.records.count, 2)
        XCTAssertEqual(Set(decoded.records.map(\.originalUUID)), [Self.firstUUID, Self.secondUUID])
    }

    func testLegacyHealthDataMissingArchiveAndStatusDefaultsLegacyUnavailable() throws {
        let current = HealthData(
            date: Self.dayStart,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any]
        )
        object.removeValue(forKey: "healthKitRecordArchive")
        object.removeValue(forKey: "healthKitRecordCaptureStatus")

        let legacy = try JSONDecoder().decode(
            HealthData.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(legacy.healthKitRecordArchive)
        XCTAssertEqual(legacy.healthKitRecordCaptureStatus, .legacyUnavailable)
    }

    func testNewSummaryOnlyHealthDataEncodesNotRequestedWithoutArchive() throws {
        let summaryOnly = HealthData(
            date: Self.dayStart,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
        )
        let encoded = try JSONEncoder().encode(summaryOnly)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["healthKitRecordCaptureStatus"] as? String, "notRequested")
        XCTAssertNil(object["healthKitRecordArchive"])

        let decoded = try JSONDecoder().decode(HealthData.self, from: encoded)
        XCTAssertEqual(decoded.healthKitRecordCaptureStatus, .notRequested)
        XCTAssertNil(decoded.healthKitRecordArchive)
        XCTAssertFalse(decoded.hasAnyData)
    }

    func testArchiveStatusIsAuthoritativeAndArchiveRecordsOrFailuresCountAsData() {
        let recordArchive = makeArchive(captureStatus: .partial, records: [
            makeRecord(uuid: Self.firstUUID, metricIDs: ["steps"])
        ])
        var withRecord = HealthData(
            date: Self.dayStart,
            healthKitRecordArchive: recordArchive,
            healthKitRecordCaptureStatus: .complete
        )

        XCTAssertEqual(withRecord.healthKitRecordCaptureStatus, .partial)
        withRecord.healthKitRecordCaptureStatus = .notRequested
        XCTAssertEqual(withRecord.healthKitRecordCaptureStatus, .partial)
        XCTAssertTrue(withRecord.hasAnyData)

        let failedQuery = HealthKitQueryResult(
            identifier: "failed",
            operation: "sampleQuery",
            metricIDs: ["steps"],
            interval: interval,
            status: .failure,
            recordCount: 0,
            error: HealthKitQueryError(domain: "HKErrorDomain", code: 5, description: "Denied", isRecoverable: false)
        )
        let failureOnly = HealthData(
            date: Self.dayStart,
            healthKitRecordArchive: makeArchive(
                captureStatus: .partial,
                queryResults: [failedQuery]
            )
        )
        XCTAssertTrue(failureOnly.hasAnyData)
    }

    func testMetricFilteringRetainsOnlyEnabledSelectedRecordsAndTheirDependencies() {
        let retainedSelected = makeRecord(
            uuid: Self.firstUUID,
            metricIDs: ["steps", "weight"],
            relationships: [HealthKitRecordRelationship(
                targetUUID: Self.secondUUID,
                role: "component",
                kind: "correlationComponent",
                targetOwnerDate: "2027-01-15"
            )]
        )
        let retainedDependency = makeRecord(
            uuid: Self.secondUUID,
            metricIDs: ["weight"],
            includedBecause: .relationshipDependency,
            relationships: [HealthKitRecordRelationship(
                targetUUID: Self.thirdUUID,
                role: "child",
                kind: "nestedDependency",
                targetOwnerDate: "2027-01-15"
            )]
        )
        let nestedDependency = makeRecord(
            uuid: Self.thirdUUID,
            metricIDs: [],
            includedBecause: .relationshipDependency
        )
        let disabledSelected = makeRecord(
            uuid: Self.fourthUUID,
            metricIDs: ["weight"],
            relationships: [HealthKitRecordRelationship(
                targetUUID: Self.fifthUUID,
                role: "component",
                kind: "correlationComponent",
                targetOwnerDate: "2027-01-15"
            )]
        )
        let disabledDependency = makeRecord(
            uuid: Self.fifthUUID,
            metricIDs: ["weight"],
            includedBecause: .relationshipDependency
        )
        let unrelatedDependency = makeRecord(
            uuid: Self.sixthUUID,
            metricIDs: ["steps"],
            includedBecause: .relationshipDependency
        )
        let queryResults = [
            makeQuery(id: "steps", metricIDs: ["steps"], status: .success, count: 1),
            makeQuery(id: "weight", metricIDs: ["weight"], status: .failure, count: 0),
            makeQuery(id: "shared", metricIDs: ["weight", "steps"], status: .success, count: 2)
        ]
        let archive = HealthKitRecordArchive(
            captureStatus: .partial,
            dailyOwnership: ownership,
            records: [
                disabledDependency, unrelatedDependency, disabledSelected,
                nestedDependency, retainedDependency, retainedSelected
            ],
            queryManifest: HealthKitQueryManifest(results: queryResults),
            medicationInventoryRecords: [
                HealthKitMedicationInventoryRecord(
                    externalIdentifier: "enabled-medication",
                    selectedMetricIDs: ["steps"],
                    displayName: "Enabled"
                ),
                HealthKitMedicationInventoryRecord(
                    externalIdentifier: "disabled-medication",
                    selectedMetricIDs: ["weight"],
                    displayName: "Disabled"
                )
            ]
        )
        var healthData = HealthData(date: Self.dayStart, healthKitRecordArchive: archive)
        healthData.activity.steps = 10
        healthData.body.weight = 70
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.enabledMetrics.insert("steps")
        LifecycleHarness.retain(selection)

        let filteredHealthData = healthData.filtered(by: selection)
        let filtered = filteredHealthData.healthKitRecordArchive

        XCTAssertEqual(filtered?.records.map(\.originalUUID), [Self.firstUUID, Self.secondUUID, Self.thirdUUID])
        XCTAssertEqual(filtered?.records.first?.selectedMetricIDs, ["steps"])
        XCTAssertEqual(filtered?.records.dropFirst().first?.selectedMetricIDs, [])
        XCTAssertEqual(filtered?.queryResults.map(\.identifier), ["shared", "steps"])
        XCTAssertTrue(filtered?.queryResults.allSatisfy { $0.metricIDs == ["steps"] } == true)
        XCTAssertEqual(filtered?.medicationInventoryRecords.map(\.externalIdentifier), ["enabled-medication"])
        XCTAssertEqual(filteredHealthData.activity.steps, 10)
        XCTAssertNil(filteredHealthData.body.weight)
    }

    func testSuccessEmptyAndFailureRemainDistinctInManifest() throws {
        let successEmpty = makeQuery(id: "empty", metricIDs: ["steps"], status: .success, count: 0)
        let error = HealthKitQueryError(
            domain: "HKErrorDomain",
            code: 11,
            description: "Authorization unavailable",
            isRecoverable: true
        )
        let failure = HealthKitQueryResult(
            identifier: "failure",
            objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
            operation: "sampleQuery",
            metricIDs: ["steps"],
            interval: interval,
            status: .failure,
            recordCount: 0,
            error: error
        )
        let unsupported = makeQuery(id: "unsupported", metricIDs: ["steps"], status: .unsupported, count: 0)
        let skipped = makeQuery(id: "skipped", metricIDs: ["steps"], status: .skipped, count: 0)
        let manifest = HealthKitQueryManifest(results: [successEmpty, failure, unsupported, skipped])

        let decoded = try JSONDecoder().decode(
            HealthKitQueryManifest.self,
            from: JSONEncoder().encode(manifest)
        )

        XCTAssertEqual(decoded.results.map(\.status), [.success, .failure, .unsupported, .skipped])
        XCTAssertEqual(decoded.results[0].recordCount, 0)
        XCTAssertNil(decoded.results[0].error)
        XCTAssertEqual(decoded.results[1].error, error)
        XCTAssertEqual(decoded.results[1].interval, interval)
        XCTAssertEqual(decoded.results[1].operation, "sampleQuery")
        XCTAssertEqual(decoded.results[1].metricIDs, ["steps"])
    }

    func testDeterministicRecordSortingUsesDatesTypeThenUUID() {
        let late = makeRecord(
            uuid: Self.firstUUID,
            metricIDs: ["steps"],
            startDate: Self.dayStart.addingTimeInterval(30),
            endDate: Self.dayStart.addingTimeInterval(31),
            objectTypeIdentifier: "B"
        )
        let typeB = makeRecord(
            uuid: Self.secondUUID,
            metricIDs: ["steps"],
            startDate: Self.dayStart,
            endDate: Self.dayStart.addingTimeInterval(1),
            objectTypeIdentifier: "B"
        )
        let typeASecondUUID = makeRecord(
            uuid: Self.secondUUID,
            metricIDs: ["steps"],
            startDate: Self.dayStart,
            endDate: Self.dayStart.addingTimeInterval(1),
            objectTypeIdentifier: "A"
        )
        let typeAFirstUUID = makeRecord(
            uuid: Self.firstUUID,
            metricIDs: ["steps"],
            startDate: Self.dayStart,
            endDate: Self.dayStart.addingTimeInterval(1),
            objectTypeIdentifier: "A"
        )

        let sorted = HealthKitRecord.sortedDeterministically([
            late, typeB, typeASecondUUID, typeAFirstUUID
        ])

        XCTAssertEqual(sorted, [typeAFirstUUID, typeASecondUUID, typeB, late])
    }

    // MARK: - Fixtures

    private static var ownership: HealthKitDailyOwnershipMetadata {
        HealthKitDailyOwnershipMetadata(
            ownerDate: "2027-01-15",
            intervalStart: dayStart,
            intervalEnd: dayEnd,
            calendarTimeZoneIdentifier: "America/New_York"
        )
    }

    private static var interval: HealthKitQueryInterval {
        HealthKitQueryInterval(startDate: dayStart, endDate: dayEnd)
    }

    private static var source: HealthKitSourceRevision {
        HealthKitSourceRevision(
            name: "Fixture Source",
            bundleIdentifier: "com.example.fixture",
            version: "1.0",
            productType: "iPhone",
            operatingSystemVersion: "19.0"
        )
    }

    private var ownership: HealthKitDailyOwnershipMetadata { Self.ownership }
    private var interval: HealthKitQueryInterval { Self.interval }

    private func makeArchive(
        captureStatus: HealthKitRecordCaptureStatus = .complete,
        records: [HealthKitRecord] = [],
        queryResults: [HealthKitQueryResult] = []
    ) -> HealthKitRecordArchive {
        HealthKitRecordArchive(
            captureStatus: captureStatus,
            dailyOwnership: ownership,
            records: records,
            queryManifest: HealthKitQueryManifest(results: queryResults)
        )
    }

    private func makeRecord(
        uuid: UUID,
        metricIDs: [String],
        includedBecause: HealthKitRecordInclusionReason = .selectedMetric,
        relationships: [HealthKitRecordRelationship] = [],
        startDate: Date = HealthKitRecordTests.dayStart,
        endDate: Date = HealthKitRecordTests.dayStart.addingTimeInterval(1),
        objectTypeIdentifier: String = "HKQuantityTypeIdentifierStepCount"
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: objectTypeIdentifier,
            recordKind: .quantity,
            selectedMetricIDs: metricIDs,
            includedBecause: includedBecause,
            startDate: startDate,
            endDate: endDate,
            sourceRevision: Self.source,
            payload: .quantity(HealthKitQuantityPayload(value: 100, unit: "count")),
            relationships: relationships
        )
    }

    private func makeQuery(
        id: String,
        metricIDs: [String],
        status: HealthKitQueryResultStatus,
        count: Int
    ) -> HealthKitQueryResult {
        HealthKitQueryResult(
            identifier: id,
            operation: "sampleQuery",
            metricIDs: metricIDs,
            interval: interval,
            status: status,
            recordCount: count,
            error: status == .failure
                ? HealthKitQueryError(domain: "HKErrorDomain", code: 1, description: "failed")
                : nil
        )
    }
}
