import Foundation

// MARK: - Archive

/// Capture state for the portable, lossless HealthKit record archive attached to a daily `HealthData` value.
enum HealthKitRecordCaptureStatus: String, Codable, CaseIterable, Sendable {
    case complete
    case partial
    case notRequested
    case legacyUnavailable
}

/// The deterministic calendar-day identity used by every record in an archive.
///
/// `ownerDate` is an ISO `yyyy-MM-dd` value in `calendarTimeZoneIdentifier`. The explicit half-open
/// interval removes any dependency on the calendar or timezone of the device reading the archive.
struct HealthKitDailyOwnershipMetadata: Codable, Equatable, Sendable {
    let ownerDate: String
    let intervalStart: Date
    let intervalEnd: Date
    let calendarIdentifier: String
    let calendarTimeZoneIdentifier: String
    let assignmentRule: String

    init(
        ownerDate: String,
        intervalStart: Date,
        intervalEnd: Date,
        calendarIdentifier: String = "gregorian",
        calendarTimeZoneIdentifier: String,
        assignmentRule: String = "record_start_in_half_open_day_interval"
    ) {
        self.ownerDate = ownerDate
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.calendarIdentifier = calendarIdentifier
        self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier
        self.assignmentRule = assignmentRule
    }

    static func ownerDate(for date: Date, calendarTimeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: calendarTimeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// A portable archive of the original HealthKit objects used to produce one daily summary.
/// This type deliberately imports Foundation only; conversion from HealthKit belongs in a later adapter layer.
struct HealthKitRecordArchive: Codable, Equatable, Sendable {
    static let canonicalSchemaIdentifier = "healthmd.healthkit_records"
    static let currentRecordSchemaVersion = 1

    let schemaIdentifier: String
    let recordSchemaVersion: Int
    let captureStatus: HealthKitRecordCaptureStatus
    let dailyOwnership: HealthKitDailyOwnershipMetadata
    let records: [HealthKitRecord]
    let queryManifest: HealthKitQueryManifest
    let integrityWarnings: [HealthKitRecordIntegrityWarning]
    let medicationInventoryRecords: [HealthKitMedicationInventoryRecord]

    init(
        captureStatus: HealthKitRecordCaptureStatus,
        dailyOwnership: HealthKitDailyOwnershipMetadata,
        records: [HealthKitRecord] = [],
        queryManifest: HealthKitQueryManifest = HealthKitQueryManifest(),
        integrityWarnings: [HealthKitRecordIntegrityWarning] = [],
        medicationInventoryRecords: [HealthKitMedicationInventoryRecord] = [],
        schemaIdentifier: String = HealthKitRecordArchive.canonicalSchemaIdentifier,
        recordSchemaVersion: Int = HealthKitRecordArchive.currentRecordSchemaVersion
    ) {
        self.schemaIdentifier = schemaIdentifier
        self.recordSchemaVersion = recordSchemaVersion
        self.captureStatus = captureStatus
        self.dailyOwnership = dailyOwnership
        self.records = HealthKitRecord.sortedDeterministically(records)
        self.queryManifest = queryManifest.sortedDeterministically()
        self.integrityWarnings = integrityWarnings.sortedDeterministically()
        self.medicationInventoryRecords = medicationInventoryRecords.sortedDeterministically()
    }

    var queryResults: [HealthKitQueryResult] { queryManifest.results }

    /// Records and failed queries both count as diagnostically meaningful data. A successful empty query does not.
    var hasRecordsOrFailures: Bool {
        !records.isEmpty ||
        !medicationInventoryRecords.isEmpty ||
        queryManifest.results.contains { $0.status == .failure }
    }

    /// Returns a deterministic archive containing only information needed by the enabled metrics.
    ///
    /// Directly selected records must match an enabled metric. Relationship dependencies are retained only when
    /// connected to one of those selected records; disabled selected records are never traversed as dependency
    /// bridges. Metric identifiers are intersected with the selection before being emitted.
    func filtered(enabledMetricIDs: Set<String>) -> HealthKitRecordArchive {
        let recordsByUUID = Dictionary(grouping: records, by: \.originalUUID)
        let directlyRetained = records.filter {
            $0.includedBecause == .selectedMetric && !$0.selectedMetricIDsSet.isDisjoint(with: enabledMetricIDs)
        }

        var retainedUUIDs = Set(directlyRetained.map(\.originalUUID))
        var frontier = retainedUUIDs

        while !frontier.isEmpty {
            let currentFrontier = frontier
            frontier.removeAll(keepingCapacity: true)

            for record in records where record.includedBecause == .relationshipDependency && !retainedUUIDs.contains(record.originalUUID) {
                let dependencyTargets = Set(record.relationships.compactMap(\.targetUUID))
                let isTargetedByRetainedRecord = currentFrontier.contains { retainedUUID in
                    recordsByUUID[retainedUUID, default: []].contains { retainedRecord in
                        retainedRecord.relationships.contains { $0.targetUUID == record.originalUUID }
                    }
                }
                let targetsRetainedRecord = !dependencyTargets.isDisjoint(with: retainedUUIDs)

                if isTargetedByRetainedRecord || targetsRetainedRecord {
                    retainedUUIDs.insert(record.originalUUID)
                    frontier.insert(record.originalUUID)
                }
            }
        }

        let retainedRecordsBeforeRelationshipFiltering = records
            .filter { retainedUUIDs.contains($0.originalUUID) }
            .map { $0.filteringMetricIDs(to: enabledMetricIDs) }

        let directlyRetainedExternalIdentifiers = Set(
            medicationInventoryRecords
                .filter {
                    $0.includedBecause == .selectedMetric &&
                    !$0.selectedMetricIDsSet.isDisjoint(with: enabledMetricIDs)
                }
                .map(\.externalIdentifier)
        )
        var relationshipTargetExternalIdentifiers = Set<String>()
        for record in retainedRecordsBeforeRelationshipFiltering {
            relationshipTargetExternalIdentifiers.formUnion(
                record.relationships.compactMap(\.targetExternalIdentifier)
            )
        }

        let retainedMedicationInventory = medicationInventoryRecords
            .filter {
                directlyRetainedExternalIdentifiers.contains($0.externalIdentifier) ||
                ($0.includedBecause == .relationshipDependency &&
                    relationshipTargetExternalIdentifiers.contains($0.externalIdentifier))
            }
            .map { $0.filteringMetricIDs(to: enabledMetricIDs) }
        let retainedExternalIdentifiers = Set(retainedMedicationInventory.map(\.externalIdentifier))

        let allRecordUUIDs = Set(records.map(\.originalUUID))
        let allExternalIdentifiers = Set(medicationInventoryRecords.map(\.externalIdentifier))
        let retainedRecords = retainedRecordsBeforeRelationshipFiltering.map { record in
            record.filteringRelationships { relationship in
                if let targetUUID = relationship.targetUUID,
                   allRecordUUIDs.contains(targetUUID) {
                    return retainedUUIDs.contains(targetUUID)
                }
                if let targetExternalIdentifier = relationship.targetExternalIdentifier,
                   allExternalIdentifiers.contains(targetExternalIdentifier) {
                    return retainedExternalIdentifiers.contains(targetExternalIdentifier)
                }
                // A relationship may intentionally point into another day's archive.
                return true
            }
        }

        let retainedWarnings = integrityWarnings.compactMap { warning -> HealthKitRecordIntegrityWarning? in
            let filteredMetricIDs = warning.metricIDs.filter(enabledMetricIDs.contains)
            let filteredRecordUUIDs = warning.recordUUIDs.filter(retainedUUIDs.contains)
            let isGlobal = warning.metricIDs.isEmpty && warning.recordUUIDs.isEmpty
            guard isGlobal || !filteredMetricIDs.isEmpty || !filteredRecordUUIDs.isEmpty else { return nil }
            return HealthKitRecordIntegrityWarning(
                code: warning.code,
                message: warning.message,
                metricIDs: filteredMetricIDs,
                recordUUIDs: filteredRecordUUIDs
            )
        }

        return HealthKitRecordArchive(
            captureStatus: captureStatus,
            dailyOwnership: dailyOwnership,
            records: retainedRecords,
            queryManifest: queryManifest.filtered(enabledMetricIDs: enabledMetricIDs),
            integrityWarnings: retainedWarnings,
            medicationInventoryRecords: retainedMedicationInventory,
            schemaIdentifier: schemaIdentifier,
            recordSchemaVersion: recordSchemaVersion
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaIdentifier
        case recordSchemaVersion
        case captureStatus
        case dailyOwnership
        case records
        case queryManifest
        case integrityWarnings
        case medicationInventoryRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            captureStatus: try container.decode(HealthKitRecordCaptureStatus.self, forKey: .captureStatus),
            dailyOwnership: try container.decode(HealthKitDailyOwnershipMetadata.self, forKey: .dailyOwnership),
            records: try container.decodeIfPresent([HealthKitRecord].self, forKey: .records) ?? [],
            queryManifest: try container.decodeIfPresent(HealthKitQueryManifest.self, forKey: .queryManifest) ?? HealthKitQueryManifest(),
            integrityWarnings: try container.decodeIfPresent([HealthKitRecordIntegrityWarning].self, forKey: .integrityWarnings) ?? [],
            medicationInventoryRecords: try container.decodeIfPresent([HealthKitMedicationInventoryRecord].self, forKey: .medicationInventoryRecords) ?? [],
            schemaIdentifier: try container.decodeIfPresent(String.self, forKey: .schemaIdentifier) ?? Self.canonicalSchemaIdentifier,
            recordSchemaVersion: try container.decodeIfPresent(Int.self, forKey: .recordSchemaVersion) ?? Self.currentRecordSchemaVersion
        )
    }
}

// MARK: - Common record provenance

enum HealthKitRecordKind: Equatable, Sendable {
    case quantity
    case category
    case correlation
    case workout
    case clinical
    case audiogram
    case electrocardiogram
    case visionPrescription
    case stateOfMind
    case medicationDoseEvent
    case document
    case other(String)

    var rawValue: String {
        switch self {
        case .quantity: return "quantity"
        case .category: return "category"
        case .correlation: return "correlation"
        case .workout: return "workout"
        case .clinical: return "clinical"
        case .audiogram: return "audiogram"
        case .electrocardiogram: return "electrocardiogram"
        case .visionPrescription: return "visionPrescription"
        case .stateOfMind: return "stateOfMind"
        case .medicationDoseEvent: return "medicationDoseEvent"
        case .document: return "document"
        case .other(let value): return value
        }
    }
}

extension HealthKitRecordKind: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "quantity": self = .quantity
        case "category": self = .category
        case "correlation": self = .correlation
        case "workout": self = .workout
        case "clinical": self = .clinical
        case "audiogram": self = .audiogram
        case "electrocardiogram": self = .electrocardiogram
        case "visionPrescription": self = .visionPrescription
        case "stateOfMind": self = .stateOfMind
        case "medicationDoseEvent": self = .medicationDoseEvent
        case "document": self = .document
        default: self = .other(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum HealthKitRecordInclusionReason: Equatable, Sendable {
    case selectedMetric
    case relationshipDependency
    case other(String)

    var rawValue: String {
        switch self {
        case .selectedMetric: return "selectedMetric"
        case .relationshipDependency: return "relationshipDependency"
        case .other(let value): return value
        }
    }
}

extension HealthKitRecordInclusionReason: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "selectedMetric": self = .selectedMetric
        case "relationshipDependency": self = .relationshipDependency
        default: self = .other(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct HealthKitSourceRevision: Codable, Equatable, Sendable {
    let name: String
    let bundleIdentifier: String
    let version: String?
    let productType: String?
    let operatingSystemVersion: String?

    init(
        name: String,
        bundleIdentifier: String,
        version: String? = nil,
        productType: String? = nil,
        operatingSystemVersion: String? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.productType = productType
        self.operatingSystemVersion = operatingSystemVersion
    }
}

/// Foundation representation of every public `HKDevice` field. HealthKit allows all of them to be absent.
struct HealthKitDeviceProvenance: Codable, Equatable, Sendable {
    let name: String?
    let manufacturer: String?
    let model: String?
    let hardwareVersion: String?
    let firmwareVersion: String?
    let softwareVersion: String?
    let localIdentifier: String?
    let udiDeviceIdentifier: String?

    init(
        name: String? = nil,
        manufacturer: String? = nil,
        model: String? = nil,
        hardwareVersion: String? = nil,
        firmwareVersion: String? = nil,
        softwareVersion: String? = nil,
        localIdentifier: String? = nil,
        udiDeviceIdentifier: String? = nil
    ) {
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.hardwareVersion = hardwareVersion
        self.firmwareVersion = firmwareVersion
        self.softwareVersion = softwareVersion
        self.localIdentifier = localIdentifier
        self.udiDeviceIdentifier = udiDeviceIdentifier
    }
}

struct HealthKitRecord: Codable, Equatable, Sendable {
    let originalUUID: UUID
    let objectTypeIdentifier: String
    let recordKind: HealthKitRecordKind
    let selectedMetricIDs: [String]
    let includedBecause: HealthKitRecordInclusionReason
    let startDate: Date
    let endDate: Date
    let sourceRevision: HealthKitSourceRevision
    let device: HealthKitDeviceProvenance?
    let metadata: [String: HealthKitMetadataValue]
    let payload: HealthKitRecordPayload
    let relationships: [HealthKitRecordRelationship]

    init(
        originalUUID: UUID,
        objectTypeIdentifier: String,
        recordKind: HealthKitRecordKind,
        selectedMetricIDs: [String],
        includedBecause: HealthKitRecordInclusionReason,
        startDate: Date,
        endDate: Date,
        sourceRevision: HealthKitSourceRevision,
        device: HealthKitDeviceProvenance? = nil,
        metadata: [String: HealthKitMetadataValue] = [:],
        payload: HealthKitRecordPayload,
        relationships: [HealthKitRecordRelationship] = []
    ) {
        self.originalUUID = originalUUID
        self.objectTypeIdentifier = objectTypeIdentifier
        self.recordKind = recordKind
        self.selectedMetricIDs = Array(Set(selectedMetricIDs)).sorted()
        self.includedBecause = includedBecause
        self.startDate = startDate
        self.endDate = endDate
        self.sourceRevision = sourceRevision
        self.device = device
        self.metadata = metadata
        self.payload = payload
        self.relationships = relationships.sortedDeterministically()
    }

    fileprivate var selectedMetricIDsSet: Set<String> { Set(selectedMetricIDs) }

    fileprivate func filteringMetricIDs(to enabledMetricIDs: Set<String>) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: originalUUID,
            objectTypeIdentifier: objectTypeIdentifier,
            recordKind: recordKind,
            selectedMetricIDs: selectedMetricIDs.filter(enabledMetricIDs.contains),
            includedBecause: includedBecause,
            startDate: startDate,
            endDate: endDate,
            sourceRevision: sourceRevision,
            device: device,
            metadata: metadata,
            payload: payload,
            relationships: relationships
        )
    }

    fileprivate func filteringRelationships(
        _ shouldInclude: (HealthKitRecordRelationship) -> Bool
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: originalUUID,
            objectTypeIdentifier: objectTypeIdentifier,
            recordKind: recordKind,
            selectedMetricIDs: selectedMetricIDs,
            includedBecause: includedBecause,
            startDate: startDate,
            endDate: endDate,
            sourceRevision: sourceRevision,
            device: device,
            metadata: metadata,
            payload: payload,
            relationships: relationships.filter(shouldInclude)
        )
    }

    /// Stable ordering for canonical archives. UUID is the final identity-preserving tie breaker.
    static func sortedDeterministically(_ records: [HealthKitRecord]) -> [HealthKitRecord] {
        records.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
            if lhs.objectTypeIdentifier != rhs.objectTypeIdentifier {
                return lhs.objectTypeIdentifier < rhs.objectTypeIdentifier
            }
            return lhs.originalUUID.uuidString < rhs.originalUUID.uuidString
        }
    }
}

// MARK: - Typed metadata

struct HealthKitMetadataQuantity: Codable, Equatable, Sendable {
    let value: Double
    let unit: String
    let rawDescription: String

    init(value: Double, unit: String, rawDescription: String) {
        self.value = value
        self.unit = unit
        self.rawDescription = rawDescription
    }
}

/// Lossless recursive representation of values supported by HealthKit metadata dictionaries.
indirect enum HealthKitMetadataValue: Equatable, Sendable {
    case null
    case string(String)
    case bool(Bool)
    case signedInteger(Int64)
    case unsignedInteger(UInt64)
    case floatingPoint(Double)
    case date(Date)
    case data(Data)
    case url(URL)
    case quantity(HealthKitMetadataQuantity)
    case array([HealthKitMetadataValue])
    case dictionary([String: HealthKitMetadataValue])
    case unsupported(typeName: String, description: String)
}

extension HealthKitMetadataValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case unit
        case rawDescription
        case typeName
        case description
    }

    private enum Tag: String {
        case null
        case string
        case bool
        case signedInteger
        case unsignedInteger
        case floatingPoint
        case date
        case data
        case url
        case quantity
        case array
        case dictionary
        case unsupported
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTag = (try? container.decode(String.self, forKey: .type)) ?? "missing_type_tag"
        guard let tag = Tag(rawValue: rawTag) else {
            self = .unsupported(
                typeName: rawTag,
                description: (try? container.decode(String.self, forKey: .description)) ?? "Unsupported metadata tag"
            )
            return
        }

        switch tag {
        case .null:
            self = .null
        case .string:
            guard let value = try? container.decode(String.self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid string metadata value")
                return
            }
            self = .string(value)
        case .bool:
            guard let value = try? container.decode(Bool.self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid Boolean metadata value")
                return
            }
            self = .bool(value)
        case .signedInteger:
            guard let value = try? container.decode(Int64.self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid signed integer metadata value")
                return
            }
            self = .signedInteger(value)
        case .unsignedInteger:
            guard let value = try? container.decode(UInt64.self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid unsigned integer metadata value")
                return
            }
            self = .unsignedInteger(value)
        case .floatingPoint:
            guard let value = try? container.decode(Double.self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid floating-point metadata value")
                return
            }
            self = .floatingPoint(value)
        case .date:
            guard let value = try? container.decode(Date.self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid date metadata value")
                return
            }
            self = .date(value)
        case .data:
            guard let value = try? container.decode(Data.self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid data metadata value")
                return
            }
            self = .data(value)
        case .url:
            guard let value = try? container.decode(URL.self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid URL metadata value")
                return
            }
            self = .url(value)
        case .quantity:
            guard let value = try? container.decode(Double.self, forKey: .value),
                  let unit = try? container.decode(String.self, forKey: .unit),
                  let rawDescription = try? container.decode(String.self, forKey: .rawDescription) else {
                self = .unsupported(typeName: rawTag, description: "Invalid quantity metadata value")
                return
            }
            self = .quantity(HealthKitMetadataQuantity(value: value, unit: unit, rawDescription: rawDescription))
        case .array:
            guard let value = try? container.decode([HealthKitMetadataValue].self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid array metadata value")
                return
            }
            self = .array(value)
        case .dictionary:
            guard let value = try? container.decode([String: HealthKitMetadataValue].self, forKey: .value) else {
                self = .unsupported(typeName: rawTag, description: "Invalid dictionary metadata value")
                return
            }
            self = .dictionary(value)
        case .unsupported:
            self = .unsupported(
                typeName: (try? container.decode(String.self, forKey: .typeName)) ?? "Unknown",
                description: (try? container.decode(String.self, forKey: .description)) ?? ""
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(Tag.null.rawValue, forKey: .type)
        case .string(let value):
            try container.encode(Tag.string.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(Tag.bool.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .signedInteger(let value):
            try container.encode(Tag.signedInteger.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .unsignedInteger(let value):
            try container.encode(Tag.unsignedInteger.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .floatingPoint(let value):
            try container.encode(Tag.floatingPoint.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode(Tag.date.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .data(let value):
            try container.encode(Tag.data.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .url(let value):
            try container.encode(Tag.url.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .quantity(let value):
            try container.encode(Tag.quantity.rawValue, forKey: .type)
            try container.encode(value.value, forKey: .value)
            try container.encode(value.unit, forKey: .unit)
            try container.encode(value.rawDescription, forKey: .rawDescription)
        case .array(let value):
            try container.encode(Tag.array.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .dictionary(let value):
            try container.encode(Tag.dictionary.rawValue, forKey: .type)
            try container.encode(value, forKey: .value)
        case .unsupported(let typeName, let description):
            try container.encode(Tag.unsupported.rawValue, forKey: .type)
            try container.encode(typeName, forKey: .typeName)
            try container.encode(description, forKey: .description)
        }
    }
}

// MARK: - Payloads

struct HealthKitQuantityPayload: Codable, Equatable, Sendable {
    let value: Double
    let unit: String
}

struct HealthKitCategoryPayload: Codable, Equatable, Sendable {
    let rawValue: Int64
    let symbolicValue: String?
}

struct HealthKitBinaryArtifactReference: Codable, Equatable, Sendable {
    let identifier: String
    let mediaType: String?
    let filename: String?
    let byteCount: UInt64?
    let sha256: String?

    init(
        identifier: String,
        mediaType: String? = nil,
        filename: String? = nil,
        byteCount: UInt64? = nil,
        sha256: String? = nil
    ) {
        self.identifier = identifier
        self.mediaType = mediaType
        self.filename = filename
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

enum HealthKitRecordPayload: Equatable, Sendable {
    case quantity(HealthKitQuantityPayload)
    case category(HealthKitCategoryPayload)
    case correlation(componentUUIDs: [UUID])
    case structured(kind: String, fields: [String: HealthKitMetadataValue])
    case binaryArtifactReference(HealthKitBinaryArtifactReference)
    case unknown(kind: String, fields: [String: HealthKitMetadataValue])
}

extension HealthKitRecordPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case unit
        case rawValue
        case symbolicValue
        case componentUUIDs
        case kind
        case fields
        case artifact
    }

    private enum Tag: String {
        case quantity
        case category
        case correlation
        case structured
        case binaryArtifactReference
        case unknown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTag = (try? container.decode(String.self, forKey: .type)) ?? "missing_type_tag"
        let fields = (try? container.decode([String: HealthKitMetadataValue].self, forKey: .fields)) ?? [:]

        switch Tag(rawValue: rawTag) {
        case .quantity:
            guard let value = try? container.decode(Double.self, forKey: .value),
                  let unit = try? container.decode(String.self, forKey: .unit) else {
                self = .unknown(kind: rawTag, fields: fields)
                return
            }
            self = .quantity(HealthKitQuantityPayload(value: value, unit: unit))
        case .category:
            guard let rawValue = try? container.decode(Int64.self, forKey: .rawValue) else {
                self = .unknown(kind: rawTag, fields: fields)
                return
            }
            self = .category(HealthKitCategoryPayload(
                rawValue: rawValue,
                symbolicValue: try? container.decodeIfPresent(String.self, forKey: .symbolicValue)
            ))
        case .correlation:
            guard let componentUUIDs = try? container.decode([UUID].self, forKey: .componentUUIDs) else {
                self = .unknown(kind: rawTag, fields: fields)
                return
            }
            self = .correlation(componentUUIDs: componentUUIDs)
        case .structured:
            self = .structured(
                kind: (try? container.decode(String.self, forKey: .kind)) ?? "unknown",
                fields: fields
            )
        case .binaryArtifactReference:
            guard let artifact = try? container.decode(HealthKitBinaryArtifactReference.self, forKey: .artifact) else {
                self = .unknown(kind: rawTag, fields: fields)
                return
            }
            self = .binaryArtifactReference(artifact)
        case .unknown:
            self = .unknown(
                kind: (try? container.decode(String.self, forKey: .kind)) ?? "unknown",
                fields: fields
            )
        case nil:
            // Future payload tags retain their exact tag and any typed extension fields.
            self = .unknown(kind: rawTag, fields: fields)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .quantity(let quantity):
            try container.encode(Tag.quantity.rawValue, forKey: .type)
            try container.encode(quantity.value, forKey: .value)
            try container.encode(quantity.unit, forKey: .unit)
        case .category(let category):
            try container.encode(Tag.category.rawValue, forKey: .type)
            try container.encode(category.rawValue, forKey: .rawValue)
            try container.encodeIfPresent(category.symbolicValue, forKey: .symbolicValue)
        case .correlation(let componentUUIDs):
            try container.encode(Tag.correlation.rawValue, forKey: .type)
            try container.encode(componentUUIDs, forKey: .componentUUIDs)
        case .structured(let kind, let fields):
            try container.encode(Tag.structured.rawValue, forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(fields, forKey: .fields)
        case .binaryArtifactReference(let artifact):
            try container.encode(Tag.binaryArtifactReference.rawValue, forKey: .type)
            try container.encode(artifact, forKey: .artifact)
        case .unknown(let kind, let fields):
            try container.encode(Tag.unknown.rawValue, forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(fields, forKey: .fields)
        }
    }
}

// MARK: - Relationships

enum HealthKitRecordRelationshipTarget: Codable, Equatable, Sendable {
    case uuid(UUID)
    case externalIdentifier(String)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Tag: String, Codable { case uuid, externalIdentifier }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Tag.self, forKey: .type) {
        case .uuid: self = .uuid(try container.decode(UUID.self, forKey: .value))
        case .externalIdentifier: self = .externalIdentifier(try container.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .uuid(let value):
            try container.encode(Tag.uuid, forKey: .type)
            try container.encode(value, forKey: .value)
        case .externalIdentifier(let value):
            try container.encode(Tag.externalIdentifier, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

struct HealthKitRecordRelationship: Codable, Equatable, Sendable {
    let target: HealthKitRecordRelationshipTarget
    let role: String
    let kind: String
    let targetOwnerDate: String

    init(target: HealthKitRecordRelationshipTarget, role: String, kind: String, targetOwnerDate: String) {
        self.target = target
        self.role = role
        self.kind = kind
        self.targetOwnerDate = targetOwnerDate
    }

    init(targetUUID: UUID, role: String, kind: String, targetOwnerDate: String) {
        self.init(target: .uuid(targetUUID), role: role, kind: kind, targetOwnerDate: targetOwnerDate)
    }

    init(targetExternalIdentifier: String, role: String, kind: String, targetOwnerDate: String) {
        self.init(target: .externalIdentifier(targetExternalIdentifier), role: role, kind: kind, targetOwnerDate: targetOwnerDate)
    }

    var targetUUID: UUID? {
        guard case .uuid(let value) = target else { return nil }
        return value
    }

    var targetExternalIdentifier: String? {
        guard case .externalIdentifier(let value) = target else { return nil }
        return value
    }
}

private extension Array where Element == HealthKitRecordRelationship {
    func sortedDeterministically() -> [HealthKitRecordRelationship] {
        sorted { lhs, rhs in
            let lhsTarget = lhs.targetUUID?.uuidString ?? lhs.targetExternalIdentifier ?? ""
            let rhsTarget = rhs.targetUUID?.uuidString ?? rhs.targetExternalIdentifier ?? ""
            if lhs.targetOwnerDate != rhs.targetOwnerDate { return lhs.targetOwnerDate < rhs.targetOwnerDate }
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            if lhs.role != rhs.role { return lhs.role < rhs.role }
            return lhsTarget < rhsTarget
        }
    }
}

// MARK: - Query manifest

struct HealthKitQueryInterval: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date
}

enum HealthKitQueryResultStatus: String, Codable, CaseIterable, Sendable {
    case success
    case failure
    case unsupported
    case skipped
}

struct HealthKitQueryError: Codable, Equatable, Sendable {
    let domain: String
    let code: Int64
    let description: String
    let isRecoverable: Bool?

    init(domain: String, code: Int64, description: String, isRecoverable: Bool? = nil) {
        self.domain = domain
        self.code = code
        self.description = description
        self.isRecoverable = isRecoverable
    }

    init(error: NSError, isRecoverable: Bool? = nil) {
        self.init(
            domain: error.domain,
            code: Int64(error.code),
            description: error.localizedDescription,
            isRecoverable: isRecoverable
        )
    }
}

struct HealthKitQueryResult: Codable, Equatable, Sendable {
    let identifier: String
    let objectTypeIdentifier: String?
    let operation: String
    let metricIDs: [String]
    let interval: HealthKitQueryInterval
    let status: HealthKitQueryResultStatus
    let recordCount: Int
    let error: HealthKitQueryError?
    let statusDescription: String?

    init(
        identifier: String,
        objectTypeIdentifier: String? = nil,
        operation: String,
        metricIDs: [String],
        interval: HealthKitQueryInterval,
        status: HealthKitQueryResultStatus,
        recordCount: Int,
        error: HealthKitQueryError? = nil,
        statusDescription: String? = nil
    ) {
        self.identifier = identifier
        self.objectTypeIdentifier = objectTypeIdentifier
        self.operation = operation
        self.metricIDs = Array(Set(metricIDs)).sorted()
        self.interval = interval
        self.status = status
        self.recordCount = recordCount
        self.error = error
        self.statusDescription = statusDescription
    }

    fileprivate func filteringMetricIDs(to enabledMetricIDs: Set<String>) -> HealthKitQueryResult {
        HealthKitQueryResult(
            identifier: identifier,
            objectTypeIdentifier: objectTypeIdentifier,
            operation: operation,
            metricIDs: metricIDs.filter(enabledMetricIDs.contains),
            interval: interval,
            status: status,
            recordCount: recordCount,
            error: error,
            statusDescription: statusDescription
        )
    }
}

struct HealthKitQueryManifest: Codable, Equatable, Sendable {
    let results: [HealthKitQueryResult]

    init(results: [HealthKitQueryResult] = []) {
        self.results = results
    }

    func filtered(enabledMetricIDs: Set<String>) -> HealthKitQueryManifest {
        HealthKitQueryManifest(results: results
            .filter { !Set($0.metricIDs).isDisjoint(with: enabledMetricIDs) }
            .map { $0.filteringMetricIDs(to: enabledMetricIDs) }
        ).sortedDeterministically()
    }

    fileprivate func sortedDeterministically() -> HealthKitQueryManifest {
        HealthKitQueryManifest(results: results.sorted { lhs, rhs in
            if lhs.interval.startDate != rhs.interval.startDate {
                return lhs.interval.startDate < rhs.interval.startDate
            }
            if lhs.interval.endDate != rhs.interval.endDate {
                return lhs.interval.endDate < rhs.interval.endDate
            }
            if lhs.operation != rhs.operation { return lhs.operation < rhs.operation }
            return lhs.identifier < rhs.identifier
        })
    }
}

// MARK: - Diagnostics and medication inventory

struct HealthKitRecordIntegrityWarning: Codable, Equatable, Sendable {
    let code: String
    let message: String
    let metricIDs: [String]
    let recordUUIDs: [UUID]

    init(code: String, message: String, metricIDs: [String] = [], recordUUIDs: [UUID] = []) {
        self.code = code
        self.message = message
        self.metricIDs = Array(Set(metricIDs)).sorted()
        self.recordUUIDs = Array(Set(recordUUIDs)).sorted { $0.uuidString < $1.uuidString }
    }
}

private extension Array where Element == HealthKitRecordIntegrityWarning {
    func sortedDeterministically() -> [HealthKitRecordIntegrityWarning] {
        sorted { lhs, rhs in
            if lhs.code != rhs.code { return lhs.code < rhs.code }
            if lhs.message != rhs.message { return lhs.message < rhs.message }
            return lhs.metricIDs.lexicographicallyPrecedes(rhs.metricIDs)
        }
    }
}

struct HealthKitMedicationInventoryRecord: Codable, Equatable, Sendable {
    let externalIdentifier: String
    let selectedMetricIDs: [String]
    let includedBecause: HealthKitRecordInclusionReason
    let displayName: String?
    let fields: [String: HealthKitMetadataValue]

    init(
        externalIdentifier: String,
        selectedMetricIDs: [String],
        includedBecause: HealthKitRecordInclusionReason = .selectedMetric,
        displayName: String? = nil,
        fields: [String: HealthKitMetadataValue] = [:]
    ) {
        self.externalIdentifier = externalIdentifier
        self.selectedMetricIDs = Array(Set(selectedMetricIDs)).sorted()
        self.includedBecause = includedBecause
        self.displayName = displayName
        self.fields = fields
    }

    fileprivate var selectedMetricIDsSet: Set<String> { Set(selectedMetricIDs) }

    fileprivate func filteringMetricIDs(to enabledMetricIDs: Set<String>) -> HealthKitMedicationInventoryRecord {
        HealthKitMedicationInventoryRecord(
            externalIdentifier: externalIdentifier,
            selectedMetricIDs: selectedMetricIDs.filter(enabledMetricIDs.contains),
            includedBecause: includedBecause,
            displayName: displayName,
            fields: fields
        )
    }
}

private extension Array where Element == HealthKitMedicationInventoryRecord {
    func sortedDeterministically() -> [HealthKitMedicationInventoryRecord] {
        sorted { lhs, rhs in
            if lhs.externalIdentifier != rhs.externalIdentifier {
                return lhs.externalIdentifier < rhs.externalIdentifier
            }
            return (lhs.displayName ?? "") < (rhs.displayName ?? "")
        }
    }
}
