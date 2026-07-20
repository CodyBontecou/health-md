import Foundation

/// Deterministic public serialization for the lossless HealthKit record archive.
///
/// The archive models also conform to `Codable` for app persistence and device sync. Those
/// representations are intentionally separate from this long-lived export contract.
nonisolated enum HealthKitRecordArchiveSerializer {
    static func data(for archive: HealthKitRecordArchive) throws -> Data {
        try encoder().encode(CanonicalArchive(archive))
    }

    static func string(for archive: HealthKitRecordArchive) throws -> String {
        try string(from: data(for: archive))
    }

    static func jsonObject(for archive: HealthKitRecordArchive) throws -> [String: Any] {
        try object(from: data(for: archive))
    }

    static func recordData(for record: HealthKitRecord) throws -> Data {
        try encoder().encode(CanonicalRecord(record))
    }

    static func recordString(for record: HealthKitRecord) throws -> String {
        try string(from: recordData(for: record))
    }

    static func externalRecordData(for record: HealthKitExternalRecord) throws -> Data {
        try encoder().encode(CanonicalExternalRecord(record))
    }

    static func externalRecordString(for record: HealthKitExternalRecord) throws -> String {
        try string(from: externalRecordData(for: record))
    }

    static func manifestString(for archive: HealthKitRecordArchive) throws -> String {
        try string(from: encoder().encode(CanonicalArchiveManifest(archive)))
    }

    static func queryResultString(for result: HealthKitQueryResult) throws -> String {
        try string(from: encoder().encode(CanonicalQueryResult(result)))
    }

    static func integrityWarningString(for warning: HealthKitRecordIntegrityWarning) throws -> String {
        try string(from: encoder().encode(CanonicalIntegrityWarning(warning)))
    }

    static func medicationInventoryRecordString(
        for record: HealthKitMedicationInventoryRecord
    ) throws -> String {
        try string(from: encoder().encode(CanonicalMedicationInventoryRecord(record)))
    }

    static func captureStatusString(_ status: HealthKitRecordCaptureStatus) -> String {
        switch status {
        case .complete: return "complete"
        case .partial: return "partial"
        case .notRequested: return "not_requested"
        case .legacyUnavailable: return "legacy_unavailable"
        }
    }

    static func sortedWarnings(
        _ warnings: [HealthKitRecordIntegrityWarning]
    ) -> [HealthKitRecordIntegrityWarning] {
        canonicalSort(warnings) { (try? integrityWarningString(for: $0)) ?? "" }
    }

    static func sortedExternalRecords(
        _ records: [HealthKitExternalRecord]
    ) -> [HealthKitExternalRecord] {
        canonicalSort(records) { (try? externalRecordString(for: $0)) ?? "" }
    }

    static func sortedMedicationInventory(
        _ records: [HealthKitMedicationInventoryRecord]
    ) -> [HealthKitMedicationInventoryRecord] {
        canonicalSort(records) { (try? medicationInventoryRecordString(for: $0)) ?? "" }
    }

    static func sortedQueryResults(_ results: [HealthKitQueryResult]) -> [HealthKitQueryResult] {
        canonicalSort(results) { (try? queryResultString(for: $0)) ?? "" }
    }

    /// Decorate-sort-undecorate ensures each potentially large canonical value
    /// is encoded once rather than again for every sorting comparison.
    private static func canonicalSort<Value>(
        _ values: [Value],
        key: (Value) -> String
    ) -> [Value] {
        values.enumerated().map { index, value in
            (key: key(value), index: index, value: value)
        }.sorted { lhs, rhs in
            lhs.key != rhs.key ? lhs.key < rhs.key : lhs.index < rhs.index
        }.map(\.value)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CanonicalRFC3339UTC.string(from: date))
        }
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }

    private static func string(from data: Data) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw SerializationError.invalidUTF8
        }
        return string
    }

    private static func object(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SerializationError.invalidJSONObject
        }
        return object
    }

    private enum SerializationError: Error {
        case invalidUTF8
        case invalidJSONObject
    }
}

/// RFC 3339 UTC timestamps with an explicit nanosecond-width fractional component.
/// Nine digits retain all meaningful precision available from Foundation `Date` at modern epochs.
nonisolated enum CanonicalRFC3339UTC {
    private static let formatterThreadKey = "healthmd.canonical-rfc3339-whole-seconds"

    private static func cachedFormatterForCurrentThread() -> ISO8601DateFormatter {
        if let formatter = Thread.current.threadDictionary[formatterThreadKey]
            as? ISO8601DateFormatter {
            return formatter
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        Thread.current.threadDictionary[formatterThreadKey] = formatter
        return formatter
    }

    static func string(from date: Date) -> String {
        let interval = date.timeIntervalSince1970
        var wholeSeconds = floor(interval)
        var nanoseconds = Int(((interval - wholeSeconds) * 1_000_000_000).rounded())
        if nanoseconds == 1_000_000_000 {
            wholeSeconds += 1
            nanoseconds = 0
        }

        let whole = cachedFormatterForCurrentThread().string(
            from: Date(timeIntervalSince1970: wholeSeconds)
        )
        let prefix = whole.hasSuffix("Z") ? String(whole.dropLast()) : whole
        return String(format: "%@.%09dZ", prefix, nanoseconds)
    }
}

/// RFC 4180 field escaping shared by all daily CSV rows that can contain arbitrary text.
nonisolated enum CSVFieldEscaper {
    static func escape(_ value: String) -> String {
        let sanitized = escapingUnsupportedControlCharacters(in: value)
        guard sanitized.contains(",") || sanitized.contains("\"") ||
                sanitized.contains("\r") || sanitized.contains("\n") else {
            return sanitized
        }
        return "\"\(sanitized.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func escapingUnsupportedControlCharacters(in value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)

        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x0A, 0x0D:
                escaped.unicodeScalars.append(scalar)
            case 0x00...0x08, 0x0B...0x0C, 0x0E...0x1F, 0x7F...0x9F, 0x2028, 0x2029:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }

        return escaped
    }
}

// MARK: - Canonical archive documents

nonisolated private struct CanonicalArchive: Encodable {
    let schema: String
    let schemaVersion: Int
    let captureStatus: String
    let ownership: CanonicalOwnership
    let records: [CanonicalRecord]
    let externalRecords: [CanonicalExternalRecord]?
    let queryManifest: CanonicalQueryManifest
    let integrityWarnings: [CanonicalIntegrityWarning]
    let medicationInventory: [CanonicalMedicationInventoryRecord]

    init(_ archive: HealthKitRecordArchive) {
        schema = archive.schemaIdentifier
        schemaVersion = archive.recordSchemaVersion
        captureStatus = HealthKitRecordArchiveSerializer.captureStatusString(archive.captureStatus)
        ownership = CanonicalOwnership(archive.dailyOwnership)
        // `HealthKitRecordArchive` normalizes this array in every initializer, including decoding.
        records = archive.records.map(CanonicalRecord.init)
        externalRecords = archive.externalRecords.isEmpty ? nil :
            HealthKitRecordArchiveSerializer.sortedExternalRecords(archive.externalRecords)
                .map(CanonicalExternalRecord.init)
        queryManifest = CanonicalQueryManifest(archive.queryManifest)
        integrityWarnings = HealthKitRecordArchiveSerializer.sortedWarnings(archive.integrityWarnings)
            .map(CanonicalIntegrityWarning.init)
        medicationInventory = HealthKitRecordArchiveSerializer.sortedMedicationInventory(
            archive.medicationInventoryRecords
        ).map(CanonicalMedicationInventoryRecord.init)
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureStatus = "capture_status"
        case ownership
        case records
        case externalRecords = "external_records"
        case queryManifest = "query_manifest"
        case integrityWarnings = "integrity_warnings"
        case medicationInventory = "medication_inventory"
    }
}

/// Everything in an archive except the records, which CSV emits as individual lossless rows.
nonisolated private struct CanonicalArchiveManifest: Encodable {
    let schema: String
    let schemaVersion: Int
    let captureStatus: String
    let ownership: CanonicalOwnership
    let queryManifest: CanonicalQueryManifest
    let integrityWarnings: [CanonicalIntegrityWarning]
    let medicationInventory: [CanonicalMedicationInventoryRecord]

    init(_ archive: HealthKitRecordArchive) {
        schema = archive.schemaIdentifier
        schemaVersion = archive.recordSchemaVersion
        captureStatus = HealthKitRecordArchiveSerializer.captureStatusString(archive.captureStatus)
        ownership = CanonicalOwnership(archive.dailyOwnership)
        queryManifest = CanonicalQueryManifest(archive.queryManifest)
        integrityWarnings = HealthKitRecordArchiveSerializer.sortedWarnings(archive.integrityWarnings)
            .map(CanonicalIntegrityWarning.init)
        medicationInventory = HealthKitRecordArchiveSerializer.sortedMedicationInventory(
            archive.medicationInventoryRecords
        ).map(CanonicalMedicationInventoryRecord.init)
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureStatus = "capture_status"
        case ownership
        case queryManifest = "query_manifest"
        case integrityWarnings = "integrity_warnings"
        case medicationInventory = "medication_inventory"
    }
}

nonisolated private struct CanonicalOwnership: Encodable {
    let ownerDate: String
    let intervalStart: Date
    let intervalEnd: Date
    let calendarIdentifier: String
    let calendarTimeZoneIdentifier: String
    let assignmentRule: String

    init(_ ownership: HealthKitDailyOwnershipMetadata) {
        ownerDate = ownership.ownerDate
        intervalStart = ownership.intervalStart
        intervalEnd = ownership.intervalEnd
        calendarIdentifier = ownership.calendarIdentifier
        calendarTimeZoneIdentifier = ownership.calendarTimeZoneIdentifier
        assignmentRule = ownership.assignmentRule
    }

    enum CodingKeys: String, CodingKey {
        case ownerDate = "owner_date"
        case intervalStart = "interval_start"
        case intervalEnd = "interval_end"
        case calendarIdentifier = "calendar_identifier"
        case calendarTimeZoneIdentifier = "calendar_timezone_identifier"
        case assignmentRule = "assignment_rule"
    }
}

nonisolated private struct CanonicalRecord: Encodable {
    let originalUUID: String
    let objectTypeIdentifier: String
    let recordKind: String
    let selectedMetricIDs: [String]
    let includedBecause: String
    let metricAttribution: CanonicalMetricAttribution?
    let startDate: Date
    let endDate: Date
    let hasUndeterminedDuration: Bool
    let sourceRevision: CanonicalSourceRevision
    let device: CanonicalDevice?
    let metadata: [String: CanonicalMetadataValue]
    let payload: CanonicalPayload
    let relationships: [CanonicalRelationship]

    init(_ record: HealthKitRecord) {
        originalUUID = record.originalUUID.uuidString
        objectTypeIdentifier = record.objectTypeIdentifier
        recordKind = Self.recordKindString(record.recordKind)
        selectedMetricIDs = record.selectedMetricIDs.sorted()
        includedBecause = Self.inclusionReasonString(record.includedBecause)
        metricAttribution = record.metricAttribution.map(CanonicalMetricAttribution.init)
        startDate = record.startDate
        endDate = record.endDate
        hasUndeterminedDuration = record.hasUndeterminedDuration
        sourceRevision = CanonicalSourceRevision(record.sourceRevision)
        device = record.device.map(CanonicalDevice.init)
        metadata = record.metadata.mapValues(CanonicalMetadataValue.init)
        payload = CanonicalPayload(record.payload)
        relationships = record.relationships.map(CanonicalRelationship.init)
    }

    static func inclusionReasonString(_ reason: HealthKitRecordInclusionReason) -> String {
        switch reason {
        case .selectedMetric: return "selected_metric"
        case .relationshipDependency: return "relationship_dependency"
        case .other(let value): return value
        }
    }

    static func recordKindString(_ kind: HealthKitRecordKind) -> String {
        switch kind {
        case .quantity: return "quantity"
        case .category: return "category"
        case .correlation: return "correlation"
        case .workout: return "workout"
        case .workoutRoute: return "workout_route"
        case .heartbeatSeries: return "heartbeat_series"
        case .activitySummary: return "activity_summary"
        case .characteristic: return "characteristic"
        case .clinical: return "clinical"
        case .verifiableClinicalRecord: return "verifiable_clinical_record"
        case .audiogram: return "audiogram"
        case .electrocardiogram: return "electrocardiogram"
        case .visionPrescription: return "vision_prescription"
        case .stateOfMind: return "state_of_mind"
        case .medicationDoseEvent: return "medication_dose_event"
        case .scoredAssessment: return "scored_assessment"
        case .document: return "document"
        case .attachment: return "attachment"
        case .other(let value): return value
        }
    }

    enum CodingKeys: String, CodingKey {
        case originalUUID = "original_uuid"
        case objectTypeIdentifier = "object_type_identifier"
        case recordKind = "record_kind"
        case selectedMetricIDs = "selected_metric_ids"
        case includedBecause = "included_because"
        case metricAttribution = "metric_attribution"
        case startDate = "start_date"
        case endDate = "end_date"
        case hasUndeterminedDuration = "has_undetermined_duration"
        case sourceRevision = "source_revision"
        case device
        case metadata
        case payload
        case relationships
    }
}

nonisolated private struct CanonicalExternalRecord: Encodable {
    let externalIdentifier: String
    let externalIdentityKind: String
    let objectTypeIdentifier: String
    let recordKind: String
    let selectedMetricIDs: [String]
    let includedBecause: String
    let metricAttribution: CanonicalMetricAttribution?
    let fields: [String: CanonicalMetadataValue]
    let relationships: [CanonicalRelationship]

    init(_ record: HealthKitExternalRecord) {
        externalIdentifier = record.externalIdentifier
        externalIdentityKind = record.externalIdentityKind.rawValue
        objectTypeIdentifier = record.objectTypeIdentifier
        recordKind = CanonicalRecord.recordKindString(record.recordKind)
        selectedMetricIDs = record.selectedMetricIDs.sorted()
        includedBecause = CanonicalRecord.inclusionReasonString(record.includedBecause)
        metricAttribution = record.metricAttribution.map(CanonicalMetricAttribution.init)
        fields = record.fields.mapValues(CanonicalMetadataValue.init)
        relationships = record.relationships.map(CanonicalRelationship.init)
    }

    enum CodingKeys: String, CodingKey {
        case externalIdentifier = "external_identifier"
        case externalIdentityKind = "external_identity_kind"
        case objectTypeIdentifier = "object_type_identifier"
        case recordKind = "record_kind"
        case selectedMetricIDs = "selected_metric_ids"
        case includedBecause = "included_because"
        case metricAttribution = "metric_attribution"
        case fields
        case relationships
    }
}

nonisolated private struct CanonicalMetricAttribution: Encodable {
    let directMetricIDs: [String]
    let dependencyMetricIDs: [String]

    init(_ attribution: HealthKitMetricAttribution) {
        directMetricIDs = attribution.directMetricIDs.sorted()
        dependencyMetricIDs = attribution.dependencyMetricIDs.sorted()
    }

    enum CodingKeys: String, CodingKey {
        case directMetricIDs = "direct_metric_ids"
        case dependencyMetricIDs = "dependency_metric_ids"
    }
}

nonisolated private struct CanonicalSourceRevision: Encodable {
    let name: String
    let bundleIdentifier: String
    let version: String?
    let productType: String?
    let operatingSystemVersion: CanonicalOperatingSystemVersion?

    init(_ source: HealthKitSourceRevision) {
        name = source.name
        bundleIdentifier = source.bundleIdentifier
        version = source.version
        productType = source.productType
        operatingSystemVersion = source.operatingSystemVersion.map(CanonicalOperatingSystemVersion.init)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case bundleIdentifier = "bundle_identifier"
        case version
        case productType = "product_type"
        case operatingSystemVersion = "operating_system_version"
    }
}

nonisolated private struct CanonicalOperatingSystemVersion: Encodable {
    let majorVersion: Int
    let minorVersion: Int
    let patchVersion: Int

    init(_ version: HealthKitOperatingSystemVersion) {
        majorVersion = version.majorVersion
        minorVersion = version.minorVersion
        patchVersion = version.patchVersion
    }

    enum CodingKeys: String, CodingKey {
        case majorVersion = "major_version"
        case minorVersion = "minor_version"
        case patchVersion = "patch_version"
    }
}

nonisolated private struct CanonicalDevice: Encodable {
    let name: String?
    let manufacturer: String?
    let model: String?
    let hardwareVersion: String?
    let firmwareVersion: String?
    let softwareVersion: String?
    let localIdentifier: String?
    let udiDeviceIdentifier: String?

    init(_ device: HealthKitDeviceProvenance) {
        name = device.name
        manufacturer = device.manufacturer
        model = device.model
        hardwareVersion = device.hardwareVersion
        firmwareVersion = device.firmwareVersion
        softwareVersion = device.softwareVersion
        localIdentifier = device.localIdentifier
        udiDeviceIdentifier = device.udiDeviceIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case name
        case manufacturer
        case model
        case hardwareVersion = "hardware_version"
        case firmwareVersion = "firmware_version"
        case softwareVersion = "software_version"
        case localIdentifier = "local_identifier"
        case udiDeviceIdentifier = "udi_device_identifier"
    }
}

// MARK: - Metadata and payloads

nonisolated private struct CanonicalMetadataValue: Encodable {
    let metadataValue: HealthKitMetadataValue

    init(_ value: HealthKitMetadataValue) {
        metadataValue = value
    }

    enum CodingKeys: String, CodingKey {
        case type
        case value
        case unit
        case rawDescription = "raw_description"
        case typeName = "type_name"
        case description
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch metadataValue {
        case .null:
            try container.encode("null", forKey: .type)
        case .string(let value):
            try container.encode("string", forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode("bool", forKey: .type)
            try container.encode(value, forKey: .value)
        case .signedInteger(let value):
            try container.encode("signed_integer", forKey: .type)
            try container.encode(value, forKey: .value)
        case .unsignedInteger(let value):
            try container.encode("unsigned_integer", forKey: .type)
            try container.encode(value, forKey: .value)
        case .floatingPoint(let value):
            try container.encode("floating_point", forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode("date", forKey: .type)
            try container.encode(value, forKey: .value)
        case .data(let value):
            try container.encode("data", forKey: .type)
            try container.encode(value.base64EncodedString(), forKey: .value)
        case .url(let value):
            try container.encode("url", forKey: .type)
            try container.encode(value.absoluteString, forKey: .value)
        case .quantity(let quantity):
            try container.encode("quantity", forKey: .type)
            try container.encodeIfPresent(quantity.value, forKey: .value)
            try container.encodeIfPresent(quantity.unit, forKey: .unit)
            try container.encode(quantity.rawDescription, forKey: .rawDescription)
        case .array(let values):
            try container.encode("array", forKey: .type)
            try container.encode(values.map(CanonicalMetadataValue.init), forKey: .value)
        case .dictionary(let values):
            try container.encode("dictionary", forKey: .type)
            try container.encode(values.mapValues(CanonicalMetadataValue.init), forKey: .value)
        case .unsupported(let typeName, let description):
            try container.encode("unsupported", forKey: .type)
            try container.encode(typeName, forKey: .typeName)
            try container.encode(description, forKey: .description)
        }
    }
}

nonisolated private struct CanonicalPayload: Encodable {
    let payload: HealthKitRecordPayload

    init(_ payload: HealthKitRecordPayload) {
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case type
        case value
        case unit
        case sampleSubclass = "sample_subclass"
        case sampleKind = "sample_kind"
        case count
        case minimum
        case average
        case maximum
        case mostRecent = "most_recent"
        case mostRecentDateInterval = "most_recent_date_interval"
        case sum
        case series
        case rawValue = "raw_value"
        case symbolicValue = "symbolic_value"
        case componentUUIDs = "component_uuids"
        case kind
        case fields
        case artifact
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch payload {
        case .quantity(let quantity):
            try container.encode("quantity", forKey: .type)
            try container.encode(quantity.value, forKey: .value)
            try container.encode(quantity.unit, forKey: .unit)
            try container.encodeIfPresent(quantity.sampleSubclass, forKey: .sampleSubclass)
            try container.encodeIfPresent(quantity.sampleKind, forKey: .sampleKind)
            try container.encodeIfPresent(quantity.count, forKey: .count)
            try container.encodeIfPresent(quantity.minimum.map(CanonicalExactQuantity.init), forKey: .minimum)
            try container.encodeIfPresent(quantity.average.map(CanonicalExactQuantity.init), forKey: .average)
            try container.encodeIfPresent(quantity.maximum.map(CanonicalExactQuantity.init), forKey: .maximum)
            try container.encodeIfPresent(quantity.mostRecent.map(CanonicalExactQuantity.init), forKey: .mostRecent)
            try container.encodeIfPresent(
                quantity.mostRecentDateInterval.map(CanonicalQuantityDateInterval.init),
                forKey: .mostRecentDateInterval
            )
            try container.encodeIfPresent(quantity.sum.map(CanonicalExactQuantity.init), forKey: .sum)
            try container.encodeIfPresent(quantity.series?.map(CanonicalQuantitySeriesPoint.init), forKey: .series)
        case .category(let category):
            try container.encode("category", forKey: .type)
            try container.encode(category.rawValue, forKey: .rawValue)
            try container.encodeIfPresent(category.symbolicValue, forKey: .symbolicValue)
        case .correlation(let componentUUIDs):
            try container.encode("correlation", forKey: .type)
            try container.encode(componentUUIDs.map(\.uuidString).sorted(), forKey: .componentUUIDs)
        case .structured(let kind, let fields):
            try container.encode("structured", forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(fields.mapValues(CanonicalMetadataValue.init), forKey: .fields)
        case .binaryArtifactReference(let artifact):
            try container.encode("binary_artifact_reference", forKey: .type)
            try container.encode(CanonicalBinaryArtifactReference(artifact), forKey: .artifact)
        case .unknown(let kind, let fields):
            try container.encode("unknown", forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(fields.mapValues(CanonicalMetadataValue.init), forKey: .fields)
        }
    }
}

nonisolated private struct CanonicalExactQuantity: Encodable {
    let value: Double
    let unit: String

    init(_ quantity: HealthKitExactQuantity) {
        value = quantity.value
        unit = quantity.unit
    }
}

nonisolated private struct CanonicalQuantityDateInterval: Encodable {
    let startDate: Date
    let endDate: Date

    init(_ interval: HealthKitQuantityDateInterval) {
        startDate = interval.startDate
        endDate = interval.endDate
    }

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

nonisolated private struct CanonicalQuantitySeriesPoint: Encodable {
    let quantity: CanonicalExactQuantity
    let dateInterval: CanonicalQuantityDateInterval
    let owningSampleUUID: String
    let owningSampleTypeIdentifier: String

    init(_ point: HealthKitQuantitySeriesPoint) {
        quantity = CanonicalExactQuantity(point.quantity)
        dateInterval = CanonicalQuantityDateInterval(point.dateInterval)
        owningSampleUUID = point.owningSampleUUID.uuidString
        owningSampleTypeIdentifier = point.owningSampleTypeIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case quantity
        case dateInterval = "date_interval"
        case owningSampleUUID = "owning_sample_uuid"
        case owningSampleTypeIdentifier = "owning_sample_type_identifier"
    }
}

nonisolated private struct CanonicalBinaryArtifactReference: Encodable {
    let identifier: String
    let mediaType: String?
    let filename: String?
    let byteCount: UInt64?
    let sha256: String?

    init(_ artifact: HealthKitBinaryArtifactReference) {
        identifier = artifact.identifier
        mediaType = artifact.mediaType
        filename = artifact.filename
        byteCount = artifact.byteCount
        sha256 = artifact.sha256
    }

    enum CodingKeys: String, CodingKey {
        case identifier
        case mediaType = "media_type"
        case filename
        case byteCount = "byte_count"
        case sha256
    }
}

// MARK: - Relationships, query manifest, and diagnostics

nonisolated private struct CanonicalRelationship: Encodable {
    let target: CanonicalRelationshipTarget
    let role: String
    let kind: String
    let targetOwnerDate: String?

    init(_ relationship: HealthKitRecordRelationship) {
        target = CanonicalRelationshipTarget(relationship.target)
        role = relationship.role
        kind = relationship.kind
        targetOwnerDate = relationship.targetOwnerDate
    }

    enum CodingKeys: String, CodingKey {
        case target
        case role
        case kind
        case targetOwnerDate = "target_owner_date"
    }
}

nonisolated private struct CanonicalRelationshipTarget: Encodable {
    let type: String
    let value: String

    init(_ target: HealthKitRecordRelationshipTarget) {
        switch target {
        case .uuid(let uuid):
            type = "uuid"
            value = uuid.uuidString
        case .externalIdentifier(let identifier):
            type = "external_identifier"
            value = identifier
        }
    }
}

nonisolated private struct CanonicalQueryManifest: Encodable {
    let results: [CanonicalQueryResult]

    init(_ manifest: HealthKitQueryManifest) {
        results = HealthKitRecordArchiveSerializer.sortedQueryResults(manifest.results)
            .map(CanonicalQueryResult.init)
    }
}

nonisolated private struct CanonicalQueryResult: Encodable {
    let identifier: String
    let objectTypeIdentifier: String?
    let operation: String
    let metricIDs: [String]
    let metricAttribution: CanonicalMetricAttribution?
    let interval: CanonicalQueryInterval
    let status: String
    let recordCount: Int
    let error: CanonicalQueryError?
    let statusDescription: String?

    init(_ result: HealthKitQueryResult) {
        identifier = result.identifier
        objectTypeIdentifier = result.objectTypeIdentifier
        operation = result.operation
        metricIDs = result.metricIDs.sorted()
        metricAttribution = result.metricAttribution.map(CanonicalMetricAttribution.init)
        interval = CanonicalQueryInterval(result.interval)
        status = result.status.rawValue
        recordCount = result.recordCount
        error = result.error.map(CanonicalQueryError.init)
        statusDescription = result.statusDescription
    }

    enum CodingKeys: String, CodingKey {
        case identifier
        case objectTypeIdentifier = "object_type_identifier"
        case operation
        case metricIDs = "metric_ids"
        case metricAttribution = "metric_attribution"
        case interval
        case status
        case recordCount = "record_count"
        case error
        case statusDescription = "status_description"
    }
}

nonisolated private struct CanonicalQueryInterval: Encodable {
    let startDate: Date
    let endDate: Date

    init(_ interval: HealthKitQueryInterval) {
        startDate = interval.startDate
        endDate = interval.endDate
    }

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

nonisolated private struct CanonicalQueryError: Encodable {
    let domain: String
    let code: Int64
    let description: String
    let isRecoverable: Bool?

    init(_ error: HealthKitQueryError) {
        domain = error.domain
        code = error.code
        description = error.description
        isRecoverable = error.isRecoverable
    }

    enum CodingKeys: String, CodingKey {
        case domain
        case code
        case description
        case isRecoverable = "is_recoverable"
    }
}

nonisolated private struct CanonicalIntegrityWarning: Encodable {
    let code: String
    let message: String
    let metricIDs: [String]
    let recordUUIDs: [String]

    init(_ warning: HealthKitRecordIntegrityWarning) {
        code = warning.code
        message = warning.message
        metricIDs = warning.metricIDs.sorted()
        recordUUIDs = warning.recordUUIDs.map(\.uuidString).sorted()
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case metricIDs = "metric_ids"
        case recordUUIDs = "record_uuids"
    }
}

nonisolated private struct CanonicalMedicationInventoryRecord: Encodable {
    let externalIdentifier: String
    let objectTypeIdentifier: String?
    let selectedMetricIDs: [String]
    let includedBecause: String
    let displayName: String?
    let fields: [String: CanonicalMetadataValue]

    init(_ record: HealthKitMedicationInventoryRecord) {
        externalIdentifier = record.externalIdentifier
        objectTypeIdentifier = record.objectTypeIdentifier
        selectedMetricIDs = record.selectedMetricIDs.sorted()
        includedBecause = CanonicalRecord.inclusionReasonString(record.includedBecause)
        displayName = record.displayName
        fields = record.fields.mapValues(CanonicalMetadataValue.init)
    }

    enum CodingKeys: String, CodingKey {
        case externalIdentifier = "external_identifier"
        case objectTypeIdentifier = "object_type_identifier"
        case selectedMetricIDs = "selected_metric_ids"
        case includedBecause = "included_because"
        case displayName = "display_name"
        case fields
    }
}

// MARK: - Daily partial failure diagnostics

nonisolated enum ExportDiagnosticSerializer {
    static func jsonObject(for failure: ExportPartialFailure) throws -> [String: Any] {
        let data = try encoder().encode(CanonicalPartialFailure(failure))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SerializationError.invalidJSONObject
        }
        return object
    }

    static func string(for failure: ExportPartialFailure) throws -> String {
        let data = try encoder().encode(CanonicalPartialFailure(failure))
        guard let string = String(data: data, encoding: .utf8) else {
            throw SerializationError.invalidUTF8
        }
        return string
    }

    static func sorted(_ failures: [ExportPartialFailure]) -> [ExportPartialFailure] {
        failures.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.dataType != rhs.dataType { return lhs.dataType < rhs.dataType }
            if lhs.dateRangeDescription != rhs.dateRangeDescription {
                return lhs.dateRangeDescription < rhs.dateRangeDescription
            }
            return lhs.errorDescription < rhs.errorDescription
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CanonicalRFC3339UTC.string(from: date))
        }
        return encoder
    }

    private enum SerializationError: Error {
        case invalidUTF8
        case invalidJSONObject
    }
}

nonisolated private struct CanonicalPartialFailure: Encodable {
    let date: Date
    let dataType: String
    let dateRangeDescription: String
    let errorDescription: String

    init(_ failure: ExportPartialFailure) {
        date = failure.date
        dataType = failure.dataType
        dateRangeDescription = failure.dateRangeDescription
        errorDescription = failure.errorDescription
    }

    enum CodingKeys: String, CodingKey {
        case date
        case dataType = "data_type"
        case dateRangeDescription = "date_range_description"
        case errorDescription = "error_description"
    }
}
