import CryptoKit
import Foundation

// MARK: - Clinical records and FHIR

/// Foundation-only capture of every public HKFHIRResource field. `rawJSONData` is
/// the original HealthKit Data value and is never decoded or re-encoded.
struct HealthKitFHIRResourceValue: Codable, Equatable, Sendable {
    let resourceType: String
    let identifier: String
    let fhirVersionString: String?
    let fhirVersionMajor: Int64?
    let fhirVersionMinor: Int64?
    let fhirVersionPatch: Int64?
    let fhirRelease: String?
    let sourceURLString: String?
    let rawJSONData: Data

    init(
        resourceType: String,
        identifier: String,
        fhirVersionString: String? = nil,
        fhirVersionMajor: Int64? = nil,
        fhirVersionMinor: Int64? = nil,
        fhirVersionPatch: Int64? = nil,
        fhirRelease: String? = nil,
        sourceURLString: String? = nil,
        rawJSONData: Data
    ) {
        self.resourceType = resourceType
        self.identifier = identifier
        self.fhirVersionString = fhirVersionString
        self.fhirVersionMajor = fhirVersionMajor
        self.fhirVersionMinor = fhirVersionMinor
        self.fhirVersionPatch = fhirVersionPatch
        self.fhirRelease = fhirRelease
        self.sourceURLString = sourceURLString
        self.rawJSONData = rawJSONData
    }
}

struct HealthKitClinicalRecordValue: Codable, Equatable, Sendable {
    let envelope: HealthKitSpecializedSampleEnvelope
    let clinicalTypeIdentifier: String
    let displayName: String
    let fhirResource: HealthKitFHIRResourceValue?

    init(
        envelope: HealthKitSpecializedSampleEnvelope,
        clinicalTypeIdentifier: String,
        displayName: String,
        fhirResource: HealthKitFHIRResourceValue?
    ) {
        self.envelope = envelope
        self.clinicalTypeIdentifier = clinicalTypeIdentifier
        self.displayName = displayName
        self.fhirResource = fhirResource
    }
}

// MARK: - CDA documents

struct HealthKitCDADocumentRecordValue: Codable, Equatable, Sendable {
    let envelope: HealthKitSpecializedSampleEnvelope
    let title: String?
    let patientName: String?
    let authorName: String?
    let custodianName: String?
    /// Exact XML bytes returned by HKDocumentQuery(includeDocumentData: true).
    let documentData: Data?

    init(
        envelope: HealthKitSpecializedSampleEnvelope,
        title: String?,
        patientName: String?,
        authorName: String?,
        custodianName: String?,
        documentData: Data?
    ) {
        self.envelope = envelope
        self.title = title
        self.patientName = patientName
        self.authorName = authorName
        self.custodianName = custodianName
        self.documentData = documentData
    }
}

// MARK: - Verifiable clinical records

struct HealthKitVerifiableClinicalRecordValue: Codable, Equatable, Sendable {
    let envelope: HealthKitSpecializedSampleEnvelope
    let recordTypes: [String]
    let sourceType: String?
    let issuerIdentifier: String
    let subjectFullName: String
    let subjectDateOfBirthComponents: HealthKitDateComponentsValue?
    let issuedDate: Date
    let relevantDate: Date
    let expirationDate: Date?
    let itemNames: [String]
    let dataRepresentation: Data

    init(
        envelope: HealthKitSpecializedSampleEnvelope,
        recordTypes: [String],
        sourceType: String?,
        issuerIdentifier: String,
        subjectFullName: String,
        subjectDateOfBirthComponents: HealthKitDateComponentsValue?,
        issuedDate: Date,
        relevantDate: Date,
        expirationDate: Date?,
        itemNames: [String],
        dataRepresentation: Data
    ) {
        self.envelope = envelope
        self.recordTypes = recordTypes
        self.sourceType = sourceType
        self.issuerIdentifier = issuerIdentifier
        self.subjectFullName = subjectFullName
        self.subjectDateOfBirthComponents = subjectDateOfBirthComponents
        self.issuedDate = issuedDate
        self.relevantDate = relevantDate
        self.expirationDate = expirationDate
        self.itemNames = itemNames
        self.dataRepresentation = dataRepresentation
    }
}

// MARK: - Vision prescriptions

struct HealthKitVisionPrismValue: Codable, Equatable, Sendable {
    let amount: HealthKitExactQuantityValue
    let angle: HealthKitExactQuantityValue
    let verticalAmount: HealthKitExactQuantityValue
    let horizontalAmount: HealthKitExactQuantityValue
    let verticalBaseRawValue: Int64
    let verticalBaseSymbolicValue: String?
    let horizontalBaseRawValue: Int64
    let horizontalBaseSymbolicValue: String?
    let eyeRawValue: Int64
    let eyeSymbolicValue: String?

    init(
        amount: HealthKitExactQuantityValue,
        angle: HealthKitExactQuantityValue,
        verticalAmount: HealthKitExactQuantityValue,
        horizontalAmount: HealthKitExactQuantityValue,
        verticalBaseRawValue: Int64,
        verticalBaseSymbolicValue: String?,
        horizontalBaseRawValue: Int64,
        horizontalBaseSymbolicValue: String?,
        eyeRawValue: Int64,
        eyeSymbolicValue: String?
    ) {
        self.amount = amount
        self.angle = angle
        self.verticalAmount = verticalAmount
        self.horizontalAmount = horizontalAmount
        self.verticalBaseRawValue = verticalBaseRawValue
        self.verticalBaseSymbolicValue = verticalBaseSymbolicValue
        self.horizontalBaseRawValue = horizontalBaseRawValue
        self.horizontalBaseSymbolicValue = horizontalBaseSymbolicValue
        self.eyeRawValue = eyeRawValue
        self.eyeSymbolicValue = eyeSymbolicValue
    }
}

struct HealthKitVisionLensValue: Codable, Equatable, Sendable {
    let sphere: HealthKitExactQuantityValue
    let cylinder: HealthKitExactQuantityValue?
    let axis: HealthKitExactQuantityValue?
    let addPower: HealthKitExactQuantityValue?
    let vertexDistance: HealthKitExactQuantityValue?
    let prism: HealthKitVisionPrismValue?
    let farPupillaryDistance: HealthKitExactQuantityValue?
    let nearPupillaryDistance: HealthKitExactQuantityValue?
    let baseCurve: HealthKitExactQuantityValue?
    let diameter: HealthKitExactQuantityValue?

    init(
        sphere: HealthKitExactQuantityValue,
        cylinder: HealthKitExactQuantityValue? = nil,
        axis: HealthKitExactQuantityValue? = nil,
        addPower: HealthKitExactQuantityValue? = nil,
        vertexDistance: HealthKitExactQuantityValue? = nil,
        prism: HealthKitVisionPrismValue? = nil,
        farPupillaryDistance: HealthKitExactQuantityValue? = nil,
        nearPupillaryDistance: HealthKitExactQuantityValue? = nil,
        baseCurve: HealthKitExactQuantityValue? = nil,
        diameter: HealthKitExactQuantityValue? = nil
    ) {
        self.sphere = sphere
        self.cylinder = cylinder
        self.axis = axis
        self.addPower = addPower
        self.vertexDistance = vertexDistance
        self.prism = prism
        self.farPupillaryDistance = farPupillaryDistance
        self.nearPupillaryDistance = nearPupillaryDistance
        self.baseCurve = baseCurve
        self.diameter = diameter
    }
}

struct HealthKitVisionPrescriptionRecordValue: Codable, Equatable, Sendable {
    let envelope: HealthKitSpecializedSampleEnvelope
    let prescriptionTypeRawValue: Int64
    let prescriptionTypeSymbolicValue: String?
    let dateIssued: Date
    let expirationDate: Date?
    let subtype: String
    let rightEye: HealthKitVisionLensValue?
    let leftEye: HealthKitVisionLensValue?
    let brand: String?

    init(
        envelope: HealthKitSpecializedSampleEnvelope,
        prescriptionTypeRawValue: Int64,
        prescriptionTypeSymbolicValue: String?,
        dateIssued: Date,
        expirationDate: Date?,
        subtype: String,
        rightEye: HealthKitVisionLensValue?,
        leftEye: HealthKitVisionLensValue?,
        brand: String? = nil
    ) {
        self.envelope = envelope
        self.prescriptionTypeRawValue = prescriptionTypeRawValue
        self.prescriptionTypeSymbolicValue = prescriptionTypeSymbolicValue
        self.dateIssued = dateIssued
        self.expirationDate = expirationDate
        self.subtype = subtype
        self.rightEye = rightEye
        self.leftEye = leftEye
        self.brand = brand
    }
}

// MARK: - Attachments

struct HealthKitAttachmentValue: Codable, Equatable, Sendable {
    let identifier: UUID
    let filename: String
    let uniformTypeIdentifier: String
    let byteCount: Int64
    let creationDate: Date
    let metadata: [String: HealthKitMetadataValue]
    /// Nil means streaming failed or bytes were unavailable. Empty Data is a successful zero-byte attachment.
    let data: Data?
    let sha256: String?

    init(
        identifier: UUID,
        filename: String,
        uniformTypeIdentifier: String,
        byteCount: Int64,
        creationDate: Date,
        metadata: [String: HealthKitMetadataValue] = [:],
        data: Data?,
        sha256: String?
    ) {
        self.identifier = identifier
        self.filename = filename
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.byteCount = byteCount
        self.creationDate = creationDate
        self.metadata = metadata
        self.data = data
        self.sha256 = sha256
    }
}

// MARK: - Portable mappers

enum ClinicalDocumentVisionHealthKitRecordMapper {
    static let clinicalUUIDStabilityNote = "HKClinicalRecord UUID is public but is not stable for a given clinical sample; originalUUID is preserved and stableExternalIdentity is provided when FHIR identity fields are available."

    static func clinical(
        _ value: HealthKitClinicalRecordValue,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        var fields: [String: HealthKitMetadataValue] = [
            "clinicalTypeIdentifier": .string(value.clinicalTypeIdentifier),
            "displayName": .string(value.displayName),
            "fhirResourceAvailable": .bool(value.fhirResource != nil),
            "uuidStabilityNote": .string(clinicalUUIDStabilityNote),
        ]
        if let resource = value.fhirResource {
            var resourceFields: [String: HealthKitMetadataValue] = [
                "resourceType": .string(resource.resourceType),
                "identifier": .string(resource.identifier),
                "rawJSONData": .data(resource.rawJSONData),
            ]
            if let sourceURLString = resource.sourceURLString {
                // This is provenance only. The exporter never accesses the URL.
                resourceFields["sourceURLString"] = .string(sourceURLString)
            }
            if let version = fhirVersionFields(resource) {
                resourceFields["fhirVersion"] = .dictionary(version)
            }
            let stableIdentity = stableFHIRIdentity(
                sourceBundleIdentifier: value.envelope.sourceRevision.bundleIdentifier,
                resource: resource
            )
            resourceFields["stableExternalIdentity"] = .string(stableIdentity)
            resourceFields["stableExternalIdentityKind"] = .string("source_resource_type_identifier_raw_bytes_sha256")
            fields["fhirResource"] = .dictionary(resourceFields)
        }
        return record(
            envelope: value.envelope,
            selectedMetricIDs: selectedMetricIDs,
            payload: .structured(kind: "clinicalFHIRRecord", fields: fields)
        )
    }

    static func cdaDocument(
        _ value: HealthKitCDADocumentRecordValue,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        var fields: [String: HealthKitMetadataValue] = [
            "documentAvailable": .bool(value.documentData != nil),
        ]
        if let title = value.title { fields["title"] = .string(title) }
        if let patientName = value.patientName { fields["patientName"] = .string(patientName) }
        if let authorName = value.authorName { fields["authorName"] = .string(authorName) }
        if let custodianName = value.custodianName { fields["custodianName"] = .string(custodianName) }
        if let documentData = value.documentData { fields["documentData"] = .data(documentData) }
        return record(
            envelope: value.envelope,
            selectedMetricIDs: selectedMetricIDs,
            payload: .structured(kind: "cdaDocument", fields: fields)
        )
    }

    static func verifiableClinicalRecord(
        _ value: HealthKitVerifiableClinicalRecordValue,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        var fields: [String: HealthKitMetadataValue] = [
            "recordTypes": .array(value.recordTypes.map(HealthKitMetadataValue.string)),
            "issuerIdentifier": .string(value.issuerIdentifier),
            "subjectFullName": .string(value.subjectFullName),
            "issuedDate": .date(value.issuedDate),
            "relevantDate": .date(value.relevantDate),
            "itemNames": .array(value.itemNames.map(HealthKitMetadataValue.string)),
            "dataRepresentation": .data(value.dataRepresentation),
        ]
        if let sourceType = value.sourceType { fields["sourceType"] = .string(sourceType) }
        if let dateOfBirth = value.subjectDateOfBirthComponents {
            fields["subjectDateOfBirthComponents"] = dateOfBirth.metadataValue
        }
        if let expirationDate = value.expirationDate { fields["expirationDate"] = .date(expirationDate) }
        return record(
            envelope: value.envelope,
            selectedMetricIDs: selectedMetricIDs,
            payload: .structured(kind: "verifiableClinicalRecord", fields: fields)
        )
    }

    static func visionPrescription(
        _ value: HealthKitVisionPrescriptionRecordValue,
        selectedMetricIDs: [String]
    ) -> HealthKitRecord {
        var fields: [String: HealthKitMetadataValue] = [
            "prescriptionType": SpecializedHealthKitRecordMapper.rawEnum(
                rawValue: value.prescriptionTypeRawValue,
                symbolicValue: value.prescriptionTypeSymbolicValue
            ),
            "dateIssued": .date(value.dateIssued),
            "subtype": .string(value.subtype),
        ]
        if let expirationDate = value.expirationDate { fields["expirationDate"] = .date(expirationDate) }
        if let rightEye = value.rightEye { fields["rightEye"] = lensFields(rightEye) }
        if let leftEye = value.leftEye { fields["leftEye"] = lensFields(leftEye) }
        if let brand = value.brand { fields["brand"] = .string(brand) }
        return record(
            envelope: value.envelope,
            selectedMetricIDs: selectedMetricIDs,
            payload: .structured(kind: "visionPrescription", fields: fields)
        )
    }

    static func attachment(
        _ value: HealthKitAttachmentValue,
        parentUUID: UUID,
        parentObjectTypeIdentifier: String,
        selectedMetricIDs: [String]
    ) -> HealthKitExternalRecord {
        var fields: [String: HealthKitMetadataValue] = [
            "identifier": .string(value.identifier.uuidString),
            "filename": .string(value.filename),
            "uniformTypeIdentifier": .string(value.uniformTypeIdentifier),
            "byteCount": .signedInteger(value.byteCount),
            "creationDate": .date(value.creationDate),
            "metadata": .dictionary(value.metadata),
            "parentObjectTypeIdentifier": .string(parentObjectTypeIdentifier),
            "parentObjectTypeIdentifiers": .array([.string(parentObjectTypeIdentifier)]),
            "bytesAvailable": .bool(value.data != nil),
        ]
        if let data = value.data { fields["data"] = .data(data) }
        if let sha256 = value.sha256 { fields["sha256"] = .string(sha256) }
        return HealthKitExternalRecord(
            externalIdentifier: "healthkit.attachment|\(value.identifier.uuidString)",
            externalIdentityKind: .attachmentIdentifier,
            objectTypeIdentifier: "HKAttachment",
            recordKind: .attachment,
            selectedMetricIDs: selectedMetricIDs,
            fields: fields,
            relationships: [HealthKitRecordRelationship(
                targetUUID: parentUUID,
                role: "parent",
                kind: "attachment"
            )]
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func stableFHIRIdentity(
        sourceBundleIdentifier: String,
        resource: HealthKitFHIRResourceValue
    ) -> String {
        var framed = Data()
        appendLengthFramed(Data(sourceBundleIdentifier.utf8), to: &framed)
        appendLengthFramed(Data(resource.resourceType.utf8), to: &framed)
        appendLengthFramed(Data(resource.identifier.utf8), to: &framed)
        appendLengthFramed(resource.rawJSONData, to: &framed)
        return "healthkit.fhir.sha256|\(sha256Hex(framed))"
    }

    private static func appendLengthFramed(_ component: Data, to data: inout Data) {
        var length = UInt64(component.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(component)
    }

    private static func fhirVersionFields(
        _ resource: HealthKitFHIRResourceValue
    ) -> [String: HealthKitMetadataValue]? {
        var fields: [String: HealthKitMetadataValue] = [:]
        if let value = resource.fhirVersionString { fields["stringRepresentation"] = .string(value) }
        if let value = resource.fhirVersionMajor { fields["majorVersion"] = .signedInteger(value) }
        if let value = resource.fhirVersionMinor { fields["minorVersion"] = .signedInteger(value) }
        if let value = resource.fhirVersionPatch { fields["patchVersion"] = .signedInteger(value) }
        if let value = resource.fhirRelease { fields["fhirRelease"] = .string(value) }
        return fields.isEmpty ? nil : fields
    }

    private static func lensFields(_ lens: HealthKitVisionLensValue) -> HealthKitMetadataValue {
        var fields: [String: HealthKitMetadataValue] = ["sphere": lens.sphere.metadataValue]
        if let value = lens.cylinder { fields["cylinder"] = value.metadataValue }
        if let value = lens.axis { fields["axis"] = value.metadataValue }
        if let value = lens.addPower { fields["addPower"] = value.metadataValue }
        if let value = lens.vertexDistance { fields["vertexDistance"] = value.metadataValue }
        if let value = lens.farPupillaryDistance { fields["farPupillaryDistance"] = value.metadataValue }
        if let value = lens.nearPupillaryDistance { fields["nearPupillaryDistance"] = value.metadataValue }
        if let value = lens.baseCurve { fields["baseCurve"] = value.metadataValue }
        if let value = lens.diameter { fields["diameter"] = value.metadataValue }
        if let prism = lens.prism {
            fields["prism"] = .dictionary([
                "amount": prism.amount.metadataValue,
                "angle": prism.angle.metadataValue,
                "verticalAmount": prism.verticalAmount.metadataValue,
                "horizontalAmount": prism.horizontalAmount.metadataValue,
                "verticalBase": SpecializedHealthKitRecordMapper.rawEnum(
                    rawValue: prism.verticalBaseRawValue,
                    symbolicValue: prism.verticalBaseSymbolicValue
                ),
                "horizontalBase": SpecializedHealthKitRecordMapper.rawEnum(
                    rawValue: prism.horizontalBaseRawValue,
                    symbolicValue: prism.horizontalBaseSymbolicValue
                ),
                "eye": SpecializedHealthKitRecordMapper.rawEnum(
                    rawValue: prism.eyeRawValue,
                    symbolicValue: prism.eyeSymbolicValue
                ),
            ])
        }
        return .dictionary(fields)
    }

    private static func record(
        envelope: HealthKitSpecializedSampleEnvelope,
        selectedMetricIDs: [String],
        payload: HealthKitRecordPayload
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: envelope.originalUUID,
            objectTypeIdentifier: envelope.objectTypeIdentifier,
            recordKind: envelope.recordKind,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: .selectedMetric,
            startDate: envelope.startDate,
            endDate: envelope.endDate,
            hasUndeterminedDuration: envelope.hasUndeterminedDuration,
            sourceRevision: envelope.sourceRevision,
            device: envelope.device,
            metadata: envelope.metadata,
            payload: payload
        )
    }
}
