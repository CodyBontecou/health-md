import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class HealthKitAttachmentCaptureTests: XCTestCase {
    private static let source = HealthKitSourceRevision(
        name: "Attachment Fixture",
        bundleIdentifier: "com.example.attachment-fixture",
        version: "1"
    )

    @MainActor
    func testCentralSweepIncludesEveryRetainedSampleFamilyExactlyOnce() async throws {
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_820_000_000))
        let store = FakeHealthStore()
        let quantity = record(
            uuid: uuid(1),
            type: HKQuantityTypeIdentifier.stepCount.rawValue,
            kind: .quantity,
            start: start
        )
        let category = record(
            uuid: uuid(2),
            type: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
            kind: .category,
            start: start.addingTimeInterval(1)
        )
        let correlation = record(
            uuid: uuid(3),
            type: HealthKitRecordCatalog.bloodPressureCorrelationIdentifier,
            kind: .correlation,
            start: start.addingTimeInterval(2),
            payload: .correlation(componentUUIDs: [uuid(4)])
        )
        let component = record(
            uuid: uuid(4),
            type: HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
            kind: .quantity,
            start: start.addingTimeInterval(2),
            includedBecause: .relationshipDependency
        )
        let workout = record(
            uuid: uuid(5),
            type: HealthKitRecordCatalog.workoutTypeIdentifier,
            kind: .workout,
            start: start.addingTimeInterval(3)
        )
        let route = record(
            uuid: uuid(6),
            type: HealthKitRecordCatalog.workoutRouteTypeIdentifier,
            kind: .workoutRoute,
            start: start.addingTimeInterval(3),
            includedBecause: .relationshipDependency
        )
        let ecg = record(
            uuid: uuid(7),
            type: HealthKitRecordCatalog.electrocardiogramIdentifier,
            kind: .electrocardiogram,
            start: start.addingTimeInterval(4)
        )
        let stateOfMind = record(
            uuid: uuid(8),
            type: HealthKitRecordCatalog.stateOfMindIdentifier,
            kind: .stateOfMind,
            start: start.addingTimeInterval(5)
        )
        let dose = record(
            uuid: uuid(9),
            type: HealthKitRecordCatalog.medicationDoseEventIdentifier,
            kind: .medicationDoseEvent,
            start: start.addingTimeInterval(6)
        )

        store.quantityRecordResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [quantity]
        store.categoryRecordResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [category]
        store.bloodPressureRecordResults = [correlation, component]
        store.workoutRecordResult = HealthKitWorkoutRecordQueryResult(records: [workout, route])
        store.specializedRecordResult = HealthKitSpecializedRecordQueryResult(
            records: [ecg],
            externalRecords: [
                HealthKitExternalRecord(
                    externalIdentifier: "healthkit.activity_summary|fixture",
                    externalIdentityKind: .activitySummaryDateComponents,
                    objectTypeIdentifier: HealthKitRecordCatalog.activitySummaryIdentifier,
                    recordKind: .activitySummary,
                    selectedMetricIDs: ["activity_summary"],
                    fields: [:]
                ),
                HealthKitExternalRecord(
                    externalIdentifier: "healthkit.characteristic|biological_sex",
                    externalIdentityKind: .characteristicSingleton,
                    objectTypeIdentifier: HKCharacteristicTypeIdentifier.biologicalSex.rawValue,
                    recordKind: .characteristic,
                    selectedMetricIDs: ["biological_sex"],
                    fields: [:]
                ),
            ]
        )
        store.stateOfMindRecordResults = [stateOfMind]
        store.medicationRecordResult = HealthKitMedicationRecordQueryResult(
            records: [dose],
            inventoryRecords: [HealthKitMedicationInventoryRecord(
                externalIdentifier: "medication-fixture",
                objectTypeIdentifier: HealthKitRecordCatalog.userAnnotatedMedicationIdentifier,
                selectedMetricIDs: ["medications"]
            )]
        )

        let data = try await manager(store: store, medicationAuthorized: true).fetchHealthData(
            for: start,
            includeGranularData: true,
            metricSelection: selection([
                "steps", "sleep_total", "blood_pressure_systolic",
                "workouts", "electrocardiograms", "state_of_mind_entries", "medications",
                "activity_summary", "biological_sex",
            ])
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(store.attachmentRecordQueries.count, 1)
        XCTAssertEqual(
            Set(store.attachmentRecordQueries[0].map(\.parentUUID)),
            Set((1...9).map { self.uuid($0) })
        )
        XCTAssertEqual(store.attachmentRecordQueries[0].count, 9)
        XCTAssertEqual(Set(archive.records.map(\.originalUUID)), Set((1...9).map { self.uuid($0) }))
        XCTAssertEqual(archive.externalRecords.count, 2)
        XCTAssertEqual(archive.medicationInventoryRecords.count, 1)
        XCTAssertEqual(archive.captureStatus, .complete)
    }

    @MainActor
    func testSharedAttachmentMergesRichestBytesRelationshipsFilteringAndExportParity() async throws {
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_820_100_000))
        let store = FakeHealthStore()
        let quantity = record(
            uuid: uuid(11),
            type: HKQuantityTypeIdentifier.stepCount.rawValue,
            kind: .quantity,
            start: start
        )
        let category = record(
            uuid: uuid(12),
            type: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
            kind: .category,
            start: start.addingTimeInterval(1)
        )
        store.quantityRecordResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [quantity]
        store.categoryRecordResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [category]

        let attachmentID = uuid(99)
        let exactBytes = Data([0x00, 0x01, 0xff])
        let metadataOnly = attachment(
            id: attachmentID,
            parent: quantity,
            metricIDs: ["steps"],
            metadata: ["quantity": .string("retained")],
            data: nil
        )
        let withBytes = attachment(
            id: attachmentID,
            parent: category,
            metricIDs: ["sleep_total"],
            metadata: ["category": .signedInteger(7)],
            data: exactBytes
        )
        let interval = HealthKitQueryInterval(
            startDate: start,
            endDate: Calendar.current.date(byAdding: .day, value: 1, to: start)!
        )
        store.attachmentRecordResult = HealthKitAttachmentQueryResult(
            records: [metadataOnly, withBytes],
            parentRelationships: [
                parentEdge(parent: quantity, attachment: metadataOnly),
                parentEdge(parent: category, attachment: withBytes),
            ],
            queryResults: [
                attachmentSuccess(parent: quantity, metricIDs: ["steps"], interval: interval),
                attachmentSuccess(parent: category, metricIDs: ["sleep_total"], interval: interval),
            ]
        )

        let data = try await manager(store: store).fetchHealthData(
            for: start,
            includeGranularData: true,
            metricSelection: selection(["steps", "sleep_total"])
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        let captured = try XCTUnwrap(archive.externalRecords.first)
        XCTAssertEqual(archive.externalRecords.count, 1)
        XCTAssertEqual(captured.relationships.compactMap(\.targetUUID), [uuid(11), uuid(12)])
        XCTAssertEqual(captured.fields["data"], .data(exactBytes))
        XCTAssertEqual(captured.fields["bytesAvailable"], .bool(true))
        XCTAssertEqual(
            captured.fields["sha256"],
            .string(ClinicalDocumentVisionHealthKitRecordMapper.sha256Hex(exactBytes))
        )
        XCTAssertEqual(
            captured.fields["metadata"],
            .dictionary([
                "quantity": .string("retained"),
                "category": .signedInteger(7),
            ])
        )
        for parentUUID in [uuid(11), uuid(12)] {
            XCTAssertTrue(archive.records.first { $0.originalUUID == parentUUID }?.relationships.contains {
                $0.targetExternalIdentifier == captured.externalIdentifier
            } == true)
        }

        let stepsOnly = archive.filtered(enabledMetricIDs: ["steps"])
        XCTAssertEqual(stepsOnly.records.map(\.originalUUID), [uuid(11)])
        XCTAssertEqual(stepsOnly.externalRecords.count, 1)
        XCTAssertEqual(stepsOnly.externalRecords[0].relationships.compactMap(\.targetUUID), [uuid(11)])
        XCTAssertTrue(archive.filtered(enabledMetricIDs: []).externalRecords.isEmpty)

        let reversedMerge = HealthKitAttachmentQueryResult(records: [withBytes, metadataOnly])
        XCTAssertEqual(reversedMerge.records, archive.externalRecords)

        let roundTrip = try JSONDecoder().decode(
            HealthKitRecordArchive.self,
            from: JSONEncoder().encode(archive)
        )
        XCTAssertEqual(roundTrip.externalRecords[0].fields["data"], .data(exactBytes))
        let base64 = exactBytes.base64EncodedString()
        let jsonExport = data.toJSON()
        XCTAssertTrue(
            jsonExport.contains(base64) ||
                jsonExport.contains(base64.replacingOccurrences(of: "/", with: "\\/"))
        )
        XCTAssertTrue(data.toCSV().contains(base64))
        XCTAssertEqual(
            try HealthKitRecordArchiveSerializer.string(for: archive),
            try HealthKitRecordArchiveSerializer.string(for: roundTrip)
        )
    }

    @MainActor
    func testMetadataFailureKeepsParentAndEmitsIsolatedPartialDiagnostic() async throws {
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_820_140_000))
        let store = FakeHealthStore()
        let parent = record(
            uuid: uuid(19),
            type: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
            kind: .category,
            start: start
        )
        store.categoryRecordResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [parent]
        let interval = HealthKitQueryInterval(
            startDate: start,
            endDate: Calendar.current.date(byAdding: .day, value: 1, to: start)!
        )
        store.attachmentRecordResult = HealthKitAttachmentQueryResult(
            queryResults: [HealthKitQueryResult(
                identifier: "\(parent.originalUUID.uuidString):attachments",
                objectTypeIdentifier: "HKAttachment",
                operation: "queryAttachmentMetadata",
                metricIDs: ["sleep_total"],
                metricAttribution: HealthKitMetricAttribution(directMetricIDs: ["sleep_total"]),
                interval: interval,
                status: .failure,
                recordCount: 0,
                error: HealthKitQueryError(
                    domain: "AttachmentFixture",
                    code: 41,
                    description: "metadata unavailable",
                    isRecoverable: true
                )
            )],
            integrityWarnings: [HealthKitRecordIntegrityWarning(
                code: "attachment_metadata_unavailable",
                message: "Attachment metadata was unavailable.",
                metricIDs: ["sleep_total"],
                recordUUIDs: [parent.originalUUID]
            )]
        )

        let data = try await manager(store: store).fetchHealthData(
            for: start,
            includeGranularData: true,
            metricSelection: selection(["sleep_total"])
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .partial)
        XCTAssertEqual(archive.records.map(\.originalUUID), [parent.originalUUID])
        XCTAssertTrue(archive.externalRecords.isEmpty)
        XCTAssertEqual(archive.integrityWarnings.map(\.code), ["attachment_metadata_unavailable"])
        XCTAssertTrue(archive.queryResults.contains {
            $0.operation == "queryAttachmentMetadata" && $0.status == .failure
        })
    }

    func testEmptyAttachmentDataIsSuccessfulAndKeepsEmptyChecksum() throws {
        let start = Date(timeIntervalSince1970: 1_820_150_000)
        let parent = record(
            uuid: uuid(20),
            type: HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
            kind: .category,
            start: start
        )
        let empty = attachment(
            id: uuid(97),
            parent: parent,
            metricIDs: ["sleep_total"],
            metadata: [:],
            data: Data()
        )
        XCTAssertEqual(empty.fields["bytesAvailable"], .bool(true))
        XCTAssertEqual(empty.fields["data"], .data(Data()))
        XCTAssertEqual(
            empty.fields["sha256"],
            .string(ClinicalDocumentVisionHealthKitRecordMapper.sha256Hex(Data()))
        )
        let decoded = try JSONDecoder().decode(
            HealthKitExternalRecord.self,
            from: JSONEncoder().encode(empty)
        )
        XCTAssertEqual(decoded.fields["data"], .data(Data()))
    }

    @MainActor
    func testStreamFailureKeepsMetadataAndParentAndMakesArchivePartial() async throws {
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_820_200_000))
        let store = FakeHealthStore()
        let parent = record(
            uuid: uuid(21),
            type: HKQuantityTypeIdentifier.stepCount.rawValue,
            kind: .quantity,
            start: start
        )
        store.quantityRecordResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [parent]
        let external = attachment(
            id: uuid(98),
            parent: parent,
            metricIDs: ["steps"],
            metadata: ["available": .bool(true)],
            data: nil
        )
        let interval = HealthKitQueryInterval(
            startDate: start,
            endDate: Calendar.current.date(byAdding: .day, value: 1, to: start)!
        )
        store.attachmentRecordResult = HealthKitAttachmentQueryResult(
            records: [external],
            parentRelationships: [parentEdge(parent: parent, attachment: external)],
            queryResults: [
                attachmentSuccess(parent: parent, metricIDs: ["steps"], interval: interval),
                HealthKitQueryResult(
                    identifier: "\(parent.originalUUID.uuidString):attachment:\(uuid(98).uuidString):data",
                    objectTypeIdentifier: "HKAttachment",
                    operation: "streamAttachmentData",
                    metricIDs: ["steps"],
                    metricAttribution: HealthKitMetricAttribution(directMetricIDs: ["steps"]),
                    interval: interval,
                    status: .failure,
                    recordCount: 0,
                    error: HealthKitQueryError(
                        domain: "AttachmentFixture",
                        code: 42,
                        description: "stream unavailable",
                        isRecoverable: true
                    )
                ),
            ],
            integrityWarnings: [HealthKitRecordIntegrityWarning(
                code: "attachment_data_unavailable",
                message: "Attachment metadata was retained, but bytes were unavailable.",
                metricIDs: ["steps"],
                recordUUIDs: [parent.originalUUID]
            )]
        )

        let data = try await manager(store: store).fetchHealthData(
            for: start,
            includeGranularData: true,
            metricSelection: selection(["steps"])
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .partial)
        XCTAssertEqual(archive.records.map(\.originalUUID), [parent.originalUUID])
        XCTAssertEqual(archive.externalRecords.first?.fields["bytesAvailable"], .bool(false))
        XCTAssertNil(archive.externalRecords.first?.fields["data"])
        XCTAssertEqual(archive.integrityWarnings.map(\.code), ["attachment_data_unavailable"])
        XCTAssertTrue(archive.queryResults.contains {
            $0.operation == "streamAttachmentData" && $0.status == .failure
        })
        XCTAssertTrue(data.partialFailures.contains { $0.dataType.contains("HealthKit attachment child") })
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "A7700000-0000-0000-0000-%012d", suffix))!
    }

    private func record(
        uuid: UUID,
        type: String,
        kind: HealthKitRecordKind,
        start: Date,
        includedBecause: HealthKitRecordInclusionReason = .selectedMetric,
        payload: HealthKitRecordPayload = .structured(kind: "fixture", fields: [:])
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: type,
            recordKind: kind,
            selectedMetricIDs: [],
            includedBecause: includedBecause,
            startDate: start,
            endDate: start,
            sourceRevision: Self.source,
            payload: payload
        )
    }

    private func attachment(
        id: UUID,
        parent: HealthKitRecord,
        metricIDs: [String],
        metadata: [String: HealthKitMetadataValue],
        data: Data?
    ) -> HealthKitExternalRecord {
        let value = HealthKitAttachmentValue(
            identifier: id,
            filename: "fixture.bin",
            uniformTypeIdentifier: "public.data",
            byteCount: 3,
            creationDate: parent.startDate,
            metadata: metadata,
            data: data,
            sha256: data.map(ClinicalDocumentVisionHealthKitRecordMapper.sha256Hex)
        )
        return ClinicalDocumentVisionHealthKitRecordMapper.attachment(
            value,
            parentUUID: parent.originalUUID,
            parentObjectTypeIdentifier: parent.objectTypeIdentifier,
            selectedMetricIDs: metricIDs
        ).attributed(HealthKitMetricAttribution(directMetricIDs: metricIDs))
    }

    private func parentEdge(
        parent: HealthKitRecord,
        attachment: HealthKitExternalRecord
    ) -> HealthKitAttachmentParentRelationship {
        HealthKitAttachmentParentRelationship(
            parentUUID: parent.originalUUID,
            relationship: HealthKitRecordRelationship(
                targetExternalIdentifier: attachment.externalIdentifier,
                role: "attachment",
                kind: "attachment"
            )
        )
    }

    private func attachmentSuccess(
        parent: HealthKitRecord,
        metricIDs: [String],
        interval: HealthKitQueryInterval
    ) -> HealthKitQueryResult {
        HealthKitQueryResult(
            identifier: "\(parent.originalUUID.uuidString):attachments",
            objectTypeIdentifier: "HKAttachment",
            operation: "queryAttachmentMetadata",
            metricIDs: metricIDs,
            metricAttribution: HealthKitMetricAttribution(directMetricIDs: metricIDs),
            interval: interval,
            status: .success,
            recordCount: 1
        )
    }

    @MainActor
    private func manager(
        store: FakeHealthStore,
        medicationAuthorized: Bool = false
    ) -> HealthKitManager {
        let name = "HealthKitAttachmentCaptureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        if medicationAuthorized {
            defaults.set(true, forKey: "healthKit.medicationAuthorizationRequested")
        }
        return HealthKitManager(store: store, userDefaults: defaults)
    }

    @MainActor
    private func selection(_ metricIDs: Set<String>) -> MetricSelectionState {
        let state = MetricSelectionState()
        state.deselectAll()
        for metricID in metricIDs { state.toggleMetric(metricID) }
        return state
    }
}
