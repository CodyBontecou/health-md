import Foundation
import HealthKit
import XCTest
@testable import HealthMd

final class ClinicalDocumentVisionPortableMapperTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 812_345_600.125)
    private let source = HealthKitSourceRevision(
        name: "Clinical Fixture",
        bundleIdentifier: "com.example.provider",
        version: "26.5"
    )

    func testFHIRAndCDAPreserveEveryFieldAndExactBytesAcrossSyncJSONAndCSV() throws {
        let fhirBytes = Data([0x7b, 0x22, 0x78, 0x22, 0x3a, 0x22, 0xc3, 0xa9, 0x22, 0x7d, 0x0a])
        let cdaBytes = Data("<?xml version=\"1.0\"?><ClinicalDocument>é</ClinicalDocument>\n".utf8)
        let clinicalUUID = UUID()
        let cdaUUID = UUID()
        let resource = HealthKitFHIRResourceValue(
            resourceType: "Observation",
            identifier: "resource-123",
            fhirVersionString: "4.0.1",
            fhirVersionMajor: 4,
            fhirVersionMinor: 0,
            fhirVersionPatch: 1,
            fhirRelease: "R4",
            sourceURLString: "https://portal.example/protected/Observation/resource-123",
            rawJSONData: fhirBytes
        )
        let clinical = ClinicalDocumentVisionHealthKitRecordMapper.clinical(
            HealthKitClinicalRecordValue(
                envelope: envelope(
                    uuid: clinicalUUID,
                    identifier: HealthKitRecordCatalog.clinicalLabResultIdentifier,
                    kind: .clinical
                ),
                clinicalTypeIdentifier: HealthKitRecordCatalog.clinicalLabResultIdentifier,
                displayName: "Exact lab display name",
                fhirResource: resource
            ),
            selectedMetricIDs: ["clinical_lab_result_records"]
        )
        let cda = ClinicalDocumentVisionHealthKitRecordMapper.cdaDocument(
            HealthKitCDADocumentRecordValue(
                envelope: envelope(
                    uuid: cdaUUID,
                    identifier: HealthKitRecordCatalog.cdaDocumentIdentifier,
                    kind: .document
                ),
                title: "Discharge summary",
                patientName: "Patient Name",
                authorName: "Author Name",
                custodianName: "Custodian Name",
                documentData: cdaBytes
            ),
            selectedMetricIDs: ["cda_documents"]
        )

        guard case .structured(let clinicalKind, let clinicalFields) = clinical.payload,
              case .dictionary(let fhir) = clinicalFields["fhirResource"],
              case .structured(let cdaKind, let cdaFields) = cda.payload else {
            return XCTFail("Expected structured clinical and CDA payloads")
        }
        XCTAssertEqual(clinicalKind, "clinicalFHIRRecord")
        XCTAssertEqual(clinical.originalUUID, clinicalUUID)
        XCTAssertEqual(clinicalFields["displayName"], .string("Exact lab display name"))
        XCTAssertEqual(clinicalFields["uuidStabilityNote"], .string(ClinicalDocumentVisionHealthKitRecordMapper.clinicalUUIDStabilityNote))
        XCTAssertEqual(fhir["resourceType"], .string("Observation"))
        XCTAssertEqual(fhir["identifier"], .string("resource-123"))
        XCTAssertEqual(fhir["sourceURLString"], .string("https://portal.example/protected/Observation/resource-123"))
        XCTAssertEqual(fhir["rawJSONData"], .data(fhirBytes))
        guard case .string(let stableKey) = fhir["stableExternalIdentity"] else {
            return XCTFail("Expected stable external identity")
        }
        XCTAssertEqual(
            stableKey,
            ClinicalDocumentVisionHealthKitRecordMapper.stableFHIRIdentity(
                sourceBundleIdentifier: source.bundleIdentifier,
                resource: resource
            )
        )
        XCTAssertFalse(stableKey.contains(clinicalUUID.uuidString), "Stable identity must not disguise the unstable HKClinicalRecord UUID")

        XCTAssertEqual(cdaKind, "cdaDocument")
        XCTAssertEqual(cdaFields["title"], .string("Discharge summary"))
        XCTAssertEqual(cdaFields["patientName"], .string("Patient Name"))
        XCTAssertEqual(cdaFields["authorName"], .string("Author Name"))
        XCTAssertEqual(cdaFields["custodianName"], .string("Custodian Name"))
        XCTAssertEqual(cdaFields["documentData"], .data(cdaBytes))

        let archive = archive(records: [clinical, cda])
        let healthData = HealthData(
            date: start,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )
        let synced = try JSONDecoder().decode(HealthData.self, from: JSONEncoder().encode(healthData))
        XCTAssertEqual(synced.healthKitRecordArchive, archive)

        let jsonObject = try parseJSON(healthData.toJSON())
        XCTAssertEqual(try decodedData(named: "rawJSONData", in: jsonObject), fhirBytes)
        XCTAssertEqual(try decodedData(named: "documentData", in: jsonObject), cdaBytes)

        let csvRecords = try parseRFC4180(healthData.toCSV())
            .filter { $0.count == 6 && $0[2] == "Raw HealthKit Record" }
            .map { try parseJSON($0[3]) }
        XCTAssertEqual(try decodedData(named: "rawJSONData", in: csvRecords), fhirBytes)
        XCTAssertEqual(try decodedData(named: "documentData", in: csvRecords), cdaBytes)
    }

    func testVisionMapperPreservesAllLensQuantitiesSubtypeBrandAndUnknownRawEnums() {
        func quantity(_ value: Double, _ unit: String) -> HealthKitExactQuantityValue {
            HealthKitExactQuantityValue(value: value, unit: unit, rawDescription: "\(value) \(unit)")
        }
        let prism = HealthKitVisionPrismValue(
            amount: quantity(1.25, "pD"),
            angle: quantity(42.5, "deg"),
            verticalAmount: quantity(0.75, "pD"),
            horizontalAmount: quantity(0.5, "pD"),
            verticalBaseRawValue: 99,
            verticalBaseSymbolicValue: nil,
            horizontalBaseRawValue: 4,
            horizontalBaseSymbolicValue: "out",
            eyeRawValue: 2,
            eyeSymbolicValue: "right"
        )
        let right = HealthKitVisionLensValue(
            sphere: quantity(-2.125, "D"),
            cylinder: quantity(-0.75, "D"),
            axis: quantity(179.5, "deg"),
            addPower: quantity(1.25, "D"),
            vertexDistance: quantity(12.25, "mm"),
            prism: prism,
            farPupillaryDistance: quantity(32.125, "mm"),
            nearPupillaryDistance: quantity(30.875, "mm"),
            baseCurve: quantity(8.6, "mm"),
            diameter: quantity(14.2, "mm")
        )
        let record = ClinicalDocumentVisionHealthKitRecordMapper.visionPrescription(
            HealthKitVisionPrescriptionRecordValue(
                envelope: envelope(
                    uuid: UUID(),
                    identifier: HealthKitRecordCatalog.visionPrescriptionIdentifier,
                    kind: .visionPrescription
                ),
                prescriptionTypeRawValue: 77,
                prescriptionTypeSymbolicValue: nil,
                dateIssued: start,
                expirationDate: start.addingTimeInterval(31_536_000),
                subtype: "unknown",
                rightEye: right,
                leftEye: nil,
                brand: "Exact Contact Brand"
            ),
            selectedMetricIDs: ["vision_prescriptions"]
        )

        guard case .structured(let kind, let fields) = record.payload,
              case .dictionary(let type) = fields["prescriptionType"],
              case .dictionary(let eye) = fields["rightEye"],
              case .dictionary(let mappedPrism) = eye["prism"] else {
            return XCTFail("Expected complete vision payload")
        }
        XCTAssertEqual(kind, "visionPrescription")
        XCTAssertEqual(type, ["rawValue": .signedInteger(77)])
        XCTAssertEqual(fields["subtype"], .string("unknown"))
        XCTAssertEqual(fields["brand"], .string("Exact Contact Brand"))
        XCTAssertEqual(eye["sphere"], right.sphere.metadataValue)
        XCTAssertEqual(eye["cylinder"], right.cylinder?.metadataValue)
        XCTAssertEqual(eye["axis"], right.axis?.metadataValue)
        XCTAssertEqual(eye["addPower"], right.addPower?.metadataValue)
        XCTAssertEqual(eye["vertexDistance"], right.vertexDistance?.metadataValue)
        XCTAssertEqual(eye["farPupillaryDistance"], right.farPupillaryDistance?.metadataValue)
        XCTAssertEqual(eye["nearPupillaryDistance"], right.nearPupillaryDistance?.metadataValue)
        XCTAssertEqual(eye["baseCurve"], right.baseCurve?.metadataValue)
        XCTAssertEqual(eye["diameter"], right.diameter?.metadataValue)
        XCTAssertEqual(mappedPrism["verticalBase"], .dictionary(["rawValue": .signedInteger(99)]))
        XCTAssertEqual(mappedPrism["horizontalBase"], .dictionary([
            "rawValue": .signedInteger(4), "symbolicValue": .string("out"),
        ]))
    }

    func testAttachmentPreservesMetadataChecksumBytesAndExplicitUnavailableChildFailure() throws {
        let parentUUID = UUID()
        let bytes = Data([0x00, 0xff, 0x10, 0x0a, 0x42])
        let attachmentUUID = UUID()
        let checksum = ClinicalDocumentVisionHealthKitRecordMapper.sha256Hex(bytes)
        let available = ClinicalDocumentVisionHealthKitRecordMapper.attachment(
            HealthKitAttachmentValue(
                identifier: attachmentUUID,
                filename: "scan.dcm",
                uniformTypeIdentifier: "org.nema.dicom",
                byteCount: Int64(bytes.count),
                creationDate: start,
                metadata: ["series": .signedInteger(7), "captured": .date(start)],
                data: bytes,
                sha256: checksum
            ),
            parentUUID: parentUUID,
            parentObjectTypeIdentifier: HealthKitRecordCatalog.clinicalLabResultIdentifier,
            selectedMetricIDs: ["clinical_lab_result_records"]
        )
        XCTAssertEqual(available.externalIdentityKind, .attachmentIdentifier)
        XCTAssertEqual(available.relationships.first?.targetUUID, parentUUID)
        XCTAssertEqual(available.fields["data"], .data(bytes))
        XCTAssertEqual(available.fields["sha256"], .string(checksum))
        XCTAssertEqual(available.fields["uniformTypeIdentifier"], .string("org.nema.dicom"))
        XCTAssertEqual(available.fields["metadata"], .dictionary([
            "series": .signedInteger(7), "captured": .date(start),
        ]))

        let unavailable = ClinicalDocumentVisionHealthKitRecordMapper.attachment(
            HealthKitAttachmentValue(
                identifier: UUID(),
                filename: "remote.pdf",
                uniformTypeIdentifier: "com.adobe.pdf",
                byteCount: 500,
                creationDate: start,
                metadata: ["state": .string("remote")],
                data: nil,
                sha256: nil
            ),
            parentUUID: parentUUID,
            parentObjectTypeIdentifier: HealthKitRecordCatalog.cdaDocumentIdentifier,
            selectedMetricIDs: ["cda_documents"]
        )
        XCTAssertEqual(unavailable.fields["bytesAvailable"], .bool(false))
        XCTAssertNil(unavailable.fields["data"])
        XCTAssertNil(unavailable.fields["sha256"], "Unavailable bytes must not produce a fake hash")

        let interval = HealthKitQueryInterval(startDate: start, endDate: start.addingTimeInterval(86_400))
        let failure = HealthKitQueryResult(
            identifier: "attachment:\(attachmentUUID):data",
            objectTypeIdentifier: "HKAttachment",
            operation: "streamAttachmentData",
            metricIDs: ["cda_documents"],
            interval: interval,
            status: .failure,
            recordCount: 0,
            error: HealthKitQueryError(domain: "HKErrorDomain", code: 5, description: "Bytes unavailable")
        )
        let healthData = HealthData(
            date: start,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            healthKitRecordArchive: HealthKitRecordArchive(
                captureStatus: .partial,
                dailyOwnership: ownership,
                externalRecords: [available, unavailable],
                queryManifest: HealthKitQueryManifest(results: [failure])
            ),
            healthKitRecordCaptureStatus: .partial
        )
        let json = try parseJSON(healthData.toJSON())
        XCTAssertEqual(try decodedData(named: "data", in: json), bytes)
        let csvExternal = try XCTUnwrap(
            parseRFC4180(healthData.toCSV()).first { $0.count == 6 && $0[2] == "Raw HealthKit External Record" }
        )
        let csvJSON = try parseJSON(csvExternal[3])
        if findValue(named: "data", in: csvJSON) != nil {
            XCTAssertEqual(try decodedData(named: "data", in: csvJSON), bytes)
        }
        XCTAssertTrue(healthData.toCSV().contains("streamAttachmentData"))
    }

    func testVerifiableRecordPreservesEnvelopeAndAllPublicFieldsWithoutFabricatedIdentity() {
        let uuid = UUID()
        let data = Data("signed-payload".utf8)
        let record = ClinicalDocumentVisionHealthKitRecordMapper.verifiableClinicalRecord(
            HealthKitVerifiableClinicalRecordValue(
                envelope: envelope(uuid: uuid, identifier: HealthKitRecordCatalog.verifiableClinicalRecordIdentifier, kind: .verifiableClinicalRecord),
                recordTypes: ["laboratory", "custom-future-type"],
                sourceType: "SMARTHealthCard",
                issuerIdentifier: "https://issuer.example",
                subjectFullName: "Exact Subject",
                subjectDateOfBirthComponents: HealthKitDateComponentsValue(year: 1985, month: 7, day: 9),
                issuedDate: start,
                relevantDate: start.addingTimeInterval(-60),
                expirationDate: start.addingTimeInterval(3600),
                itemNames: ["Item A", "Item B"],
                dataRepresentation: data
            ),
            selectedMetricIDs: ["verifiable_clinical_records"]
        )
        XCTAssertEqual(record.originalUUID, uuid, "HKVerifiableClinicalRecord is an HKSample and exposes a public UUID")
        guard case .structured(_, let fields) = record.payload else { return XCTFail("Expected payload") }
        XCTAssertEqual(fields["recordTypes"], .array([.string("laboratory"), .string("custom-future-type")]))
        XCTAssertEqual(fields["sourceType"], .string("SMARTHealthCard"))
        XCTAssertEqual(fields["issuerIdentifier"], .string("https://issuer.example"))
        XCTAssertEqual(fields["subjectFullName"], .string("Exact Subject"))
        XCTAssertEqual(fields["itemNames"], .array([.string("Item A"), .string("Item B")]))
        XCTAssertEqual(fields["dataRepresentation"], .data(data))
        XCTAssertNil(fields["externalIdentifier"], "No additional identity may be fabricated")
    }

    func testCancelledQueryStateIsPreservedInManifestJSONAndCSV() throws {
        let interval = HealthKitQueryInterval(
            startDate: start,
            endDate: start.addingTimeInterval(86_400)
        )
        let cancelled = HealthKitQueryResult(
            identifier: HealthKitRecordCatalog.cdaDocumentIdentifier,
            objectTypeIdentifier: HealthKitRecordCatalog.cdaDocumentIdentifier,
            operation: "queryCDADocumentRecords",
            metricIDs: ["cda_documents"],
            interval: interval,
            status: .cancelled,
            recordCount: 0,
            error: HealthKitQueryError(
                domain: HKError.errorDomain,
                code: Int64(HKError.Code.errorUserCanceled.rawValue),
                description: "The user cancelled document selection.",
                isRecoverable: true
            )
        )
        let archive = HealthKitRecordArchive(
            captureStatus: .partial,
            dailyOwnership: ownership,
            queryManifest: HealthKitQueryManifest(results: [cancelled])
        )
        let healthData = HealthData(
            date: start,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .partial
        )

        XCTAssertTrue(try HealthKitRecordArchiveSerializer.manifestString(for: archive).contains("\"status\":\"cancelled\""))
        XCTAssertEqual(findValue(named: "status", in: try parseJSON(healthData.toJSON())) as? String, "cancelled")
        let csvFailure = try XCTUnwrap(
            parseRFC4180(healthData.toCSV()).first { $0.count == 6 && $0[2] == "Query Failure" }
        )
        XCTAssertEqual(findValue(named: "status", in: try parseJSON(csvFailure[3])) as? String, "cancelled")
        XCTAssertTrue(SystemHealthStoreAdapter.isCancellationError(NSError(
            domain: HKError.errorDomain,
            code: HKError.Code.errorUserCanceled.rawValue
        )))
        XCTAssertFalse(SystemHealthStoreAdapter.isCancellationError(NSError(
            domain: HKError.errorDomain,
            code: HKError.Code.errorAuthorizationDenied.rawValue
        )))
    }

    func testSafeLoggingNeverIncludesPHIFromLocalizedDescriptionOrUserInfo() {
        let phi = "Patient Jane Doe / private-note.xml / https://portal.example/protected"
        let error = NSError(
            domain: "HKErrorDomain",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: phi, "record": phi]
        )
        let logged = HealthKitSafeLogging.queryFailureDescriptor(
            objectTypeIdentifier: HealthKitRecordCatalog.cdaDocumentIdentifier,
            error: error
        )
        XCTAssertEqual(logged, "object_type=HKDocumentTypeIdentifierCDA domain=HKErrorDomain code=4")
        XCTAssertFalse(logged.contains("Jane"))
        XCTAssertFalse(logged.contains("private-note"))
        XCTAssertFalse(logged.contains("portal.example"))
    }

    private var ownership: HealthKitDailyOwnershipMetadata {
        HealthKitDailyOwnershipMetadata(
            ownerDate: "2026-09-23",
            intervalStart: start,
            intervalEnd: start.addingTimeInterval(86_400),
            calendarTimeZoneIdentifier: "UTC"
        )
    }

    private func archive(records: [HealthKitRecord]) -> HealthKitRecordArchive {
        HealthKitRecordArchive(captureStatus: .complete, dailyOwnership: ownership, records: records)
    }

    private func envelope(uuid: UUID, identifier: String, kind: HealthKitRecordKind) -> HealthKitSpecializedSampleEnvelope {
        HealthKitSpecializedSampleEnvelope(
            originalUUID: uuid,
            objectTypeIdentifier: identifier,
            recordKind: kind,
            startDate: start,
            endDate: start.addingTimeInterval(1),
            sourceRevision: source,
            metadata: ["typed": .data(Data([0x00, 0x01]))]
        )
    }

    private func parseJSON(_ string: String) throws -> Any {
        try JSONSerialization.jsonObject(with: XCTUnwrap(string.data(using: .utf8)))
    }

    private func decodedData(named name: String, in object: Any) throws -> Data {
        let field = try XCTUnwrap(findValue(named: name, in: object) as? [String: Any])
        XCTAssertEqual(field["type"] as? String, "data")
        return try XCTUnwrap(Data(base64Encoded: XCTUnwrap(field["value"] as? String)))
    }

    private func findValue(named name: String, in object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary[name] { return value }
            for value in dictionary.values {
                if let match = findValue(named: name, in: value) { return match }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findValue(named: name, in: value) { return match }
            }
        }
        return nil
    }

    private func parseRFC4180(_ csv: String) -> [[String]] {
        let characters = Array(csv)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else { quoted.toggle() }
            } else if character == ",", !quoted {
                row.append(field); field = ""
            } else if (character == "\n" || character == "\r"), !quoted {
                row.append(field); field = ""
                if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                row = []
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
            } else { field.append(character) }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

final class ClinicalDocumentVisionCapabilityTests: XCTestCase {
    @MainActor
    func testCatalogAndManagerQueryExactlySelectedClinicalType() async throws {
        let store = FakeHealthStore()
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric("clinical_allergy_records")
        let manager = manager(store: store)

        let data = try await manager.fetchHealthData(
            for: Date(timeIntervalSinceReferenceDate: 812_800_000),
            includeGranularData: true,
            metricSelection: selection
        )

        XCTAssertEqual(store.specializedRecordQueries.count, 1)
        XCTAssertEqual(store.specializedRecordQueries[0].entries.map(\.objectTypeIdentifier), [
            HealthKitRecordCatalog.clinicalAllergyIdentifier,
        ])
        XCTAssertEqual(data.healthKitRecordArchive?.queryResults.map(\.metricIDs), [["clinical_allergy_records"]])
        XCTAssertFalse(store.specializedRecordQueries[0].entries.contains {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.clinicalConditionIdentifier
        })
    }

    @MainActor
    func testUnsupportedHealthRecordsIsManifestUnsupportedNotSuccessEmpty() async throws {
        let store = FakeHealthStore()
        store.supportsHealthRecords = false
        let selection = selection("clinical_lab_result_records")
        let data = try await manager(store: store).fetchHealthData(
            for: .now,
            includeGranularData: true,
            metricSelection: selection
        )

        XCTAssertTrue(store.specializedRecordQueries.isEmpty)
        let result = try XCTUnwrap(data.healthKitRecordArchive?.queryResults.first)
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(result.recordCount, 0)
        XCTAssertTrue(result.statusDescription?.contains("supportsHealthRecords") == true)
        XCTAssertEqual(data.healthKitRecordArchive?.captureStatus, .partial)
    }

    @MainActor
    func testMissingVerifiableRecordsEntitlementIsUnsupportedWithoutPreviewWarning() async throws {
        let store = FakeHealthStore()
        store.supportsVerifiableClinicalRecords = false
        let data = try await manager(store: store).fetchHealthData(
            for: .now,
            includeGranularData: true,
            metricSelection: selection("verifiable_clinical_records")
        )

        XCTAssertTrue(store.specializedRecordQueries.isEmpty)
        let result = try XCTUnwrap(data.healthKitRecordArchive?.queryResults.first)
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertTrue(result.statusDescription?.contains("restricted Verifiable Health Records entitlement") == true)
        XCTAssertEqual(data.healthKitRecordArchive?.captureStatus, .partial)
        XCTAssertTrue(data.partialFailures.isEmpty, "An unavailable app capability must not become a raw Preview warning")
    }

    func testVerifiableRecordDescriptorsUseExactlyOneClinicalTypeEach() {
        guard #available(iOS 15.4, macOS 13.0, macCatalyst 15.4, *) else { return }

        let descriptors = SystemHealthStoreAdapter.verifiableClinicalRecordQueryDescriptors(
            predicate: nil
        )

        XCTAssertEqual(descriptors.map(\.recordTypes), [
            [.immunization],
            [.laboratory],
            [.recovery],
        ])
        XCTAssertTrue(descriptors.allSatisfy {
            Set($0.sourceTypes) == [.smartHealthCard, .euDigitalCOVIDCertificate]
        })
    }

    @MainActor
    func testOrdinaryClinicalAuthorizationExcludesDocumentVisionAndVerifiableFlows() async throws {
        let store = FakeHealthStore()
        store.authRequestStatus = .shouldRequest
        let manager = manager(store: store)
        try await manager.requestAuthorization()

        XCTAssertTrue(store.requestedReadTypes.contains {
            $0.identifier == HealthKitRecordCatalog.clinicalAllergyIdentifier
        })
        XCTAssertFalse(store.requestedReadTypes.contains {
            $0.identifier == HealthKitRecordCatalog.cdaDocumentIdentifier ||
            $0.identifier == HealthKitRecordCatalog.visionPrescriptionIdentifier ||
            $0.identifier == HealthKitRecordCatalog.verifiableClinicalRecordIdentifier
        })
        XCTAssertFalse(store.visionAuthorizationRequested)
    }

    @MainActor
    func testVisionSelectionIsSkippedUntilExplicitPerObjectAuthorizationThenQueried() async throws {
        let store = FakeHealthStore()
        let defaults = UserDefaults(suiteName: "ClinicalVisionAuth.\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: "ClinicalVisionAuth.\(UUID().uuidString)")
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let selection = selection("vision_prescriptions")

        let skipped = try await manager.fetchHealthData(
            for: .now,
            includeGranularData: true,
            metricSelection: selection
        )
        XCTAssertEqual(skipped.healthKitRecordArchive?.queryResults.first?.status, .skipped)
        XCTAssertTrue(store.specializedRecordQueries.isEmpty)

        try await manager.requestVisionPrescriptionAuthorization(force: true)
        XCTAssertTrue(store.visionAuthorizationRequested)
        XCTAssertTrue(manager.isVisionAuthorizationRequested)

        _ = try await manager.fetchHealthData(
            for: .now,
            includeGranularData: true,
            metricSelection: selection
        )
        XCTAssertEqual(store.specializedRecordQueries.count, 1)
        XCTAssertEqual(store.specializedRecordQueries[0].entries.map(\.objectTypeIdentifier), [
            HealthKitRecordCatalog.visionPrescriptionIdentifier,
        ])
    }

    @MainActor
    func testCDAAndVerifiableQueriesRunOnlyWhenExplicitlySelected() async throws {
        let store = FakeHealthStore()
        let manager = manager(store: store)
        let unrelated = selection("steps")
        _ = try await manager.fetchHealthData(for: .now, includeGranularData: true, metricSelection: unrelated)
        XCTAssertTrue(store.specializedRecordQueries.isEmpty)

        let documents = MetricSelectionState()
        documents.deselectAll()
        documents.toggleMetric("cda_documents")
        documents.toggleMetric("verifiable_clinical_records")
        _ = try await manager.fetchHealthData(for: .now, includeGranularData: true, metricSelection: documents)
        XCTAssertEqual(store.specializedRecordQueries.count, 1)
        XCTAssertEqual(Set(store.specializedRecordQueries[0].entries.map(\.objectTypeIdentifier)), [
            HealthKitRecordCatalog.cdaDocumentIdentifier,
            HealthKitRecordCatalog.verifiableClinicalRecordIdentifier,
        ])
    }

    private func selection(_ metricID: String) -> MetricSelectionState {
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric(metricID)
        return selection
    }

    @MainActor
    private func manager(store: FakeHealthStore) -> HealthKitManager {
        HealthKitManager(
            store: store,
            userDefaults: UserDefaults(suiteName: "ClinicalCapability.\(UUID().uuidString)")!
        )
    }
}
