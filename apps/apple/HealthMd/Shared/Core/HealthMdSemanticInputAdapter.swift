import CryptoKit
import Foundation
import HealthMdCoreRust

/// Deterministic Apple post-capture adapter for `healthmd.semantic_input` v1.
///
/// HealthKit is never queried here. Existing `HealthData` values are frozen once, represented as
/// SDK aggregate facts, and sent in coarse batches. Public rendering remains native through M4.
nonisolated enum HealthMdSemanticInputAdapter {
    static let semanticInputVersion: UInt32 = 1
    static let canonicalModelVersion: UInt32 = 1
    static let registryVersion: UInt32 = 1

    enum AdapterError: Error, Equatable {
        case invalidRegistry
        case invalidTimeZone
        case duplicateOwnerDate
        case invalidArchiveOwnership
        case nonFiniteNumber
        case limitExceeded
        case invalidSessionResult
        case serializationFailed
    }

    struct ExtensionLocation: Sendable, Equatable {
        enum Collection: String, Sendable {
            case healthKitRecord
            case externalRecord
            case medicationInventory
        }

        let dayIndex: Int
        let collection: Collection
        let recordIndex: Int
    }

    struct EncodedBatch: Sendable, Equatable {
        let data: Data
        let nextSourceOrdinal: UInt64
        let retainedExtensionTokens: [String]
        /// Native side-table locations; payload objects never cross FFI.
        let extensionLocations: [String: ExtensionLocation]
    }

    @MainActor
    static func sessionConfiguration(
        sessionID: String,
        selection: MetricSelectionState,
        registry: CoreMetricRegistrySnapshot,
        customization: FormatCustomization,
        calendarTimeZoneIdentifier: String,
        retainPlatformExtensions: Bool,
        rollupPeriods: [HealthRollupPeriod]
    ) throws -> Data {
        guard registry.profileId == "apple_health_data_v7",
              registry.publicProfileId == "apple-v7",
              registry.publicSchema == HealthMdExportSchema.identifier,
              registry.publicSchemaVersion == UInt32(HealthMdExportSchema.version),
              registry.profileRevision == 1,
              registry.registryVersion == registryVersion,
              registry.registrySha256 == HealthMetrics.registrySHA256
        else { throw AdapterError.invalidRegistry }
        guard calendarTimeZoneIdentifier == "UTC"
                || TimeZone.knownTimeZoneIdentifiers.contains(calendarTimeZoneIdentifier)
        else { throw AdapterError.invalidTimeZone }

        let selected = registry.metrics
            .filter { selection.enabledMetrics.contains($0.selectionId) }
            .map(\.selectionId)
        let disabledOutputKeys = registry.outputs.filter { output in
            output.surface != "flat"
                || !customization.frontmatterConfig.isFieldEnabled(output.key)
        }.map(\.key)
        let periods = rollupPeriods.map { period in
            switch period {
            case .weekly: "iso_week"
            case .monthly: "calendar_month"
            case .yearly: "calendar_year"
            }
        }
        return try canonicalJSON([
            "schema": "healthmd.semantic_session_config",
            "semantic_input_version": semanticInputVersion,
            "canonical_model_version": canonicalModelVersion,
            "registry_version": registryVersion,
            "registry_sha256": registry.registrySha256,
            "profile_revision": registry.profileRevision,
            "session_id": sessionID,
            "profile": "apple_health_data_v7",
            "calendar_time_zone": calendarTimeZoneIdentifier,
            "selected_selection_ids": selected,
            "disabled_output_keys": disabledOutputKeys,
            "retain_platform_extensions": retainPlatformExtensions,
            "rollup_periods": periods,
        ])
    }

    /// Encodes complete daily snapshots without applying `MetricSelectionState` natively.
    /// Selection filtering therefore happens exactly once in Rust.
    @MainActor
    static func batch(
        sessionID: String,
        batchIndex: UInt32,
        finalBatch: Bool,
        healthData: [HealthData],
        registry: CoreMetricRegistrySnapshot,
        customization: FormatCustomization,
        calendarTimeZoneIdentifier: String,
        startingSourceOrdinal: UInt64 = 0
    ) throws -> EncodedBatch {
        guard registry.profileId == "apple_health_data_v7",
              registry.publicProfileId == "apple-v7",
              registry.publicSchema == HealthMdExportSchema.identifier,
              registry.publicSchemaVersion == UInt32(HealthMdExportSchema.version),
              registry.profileRevision == 1,
              registry.registryVersion == registryVersion,
              registry.registrySha256 == HealthMetrics.registrySHA256 else {
            throw AdapterError.invalidRegistry
        }
        guard (calendarTimeZoneIdentifier == "UTC"
                || TimeZone.knownTimeZoneIdentifiers.contains(calendarTimeZoneIdentifier)),
              let calendarTimeZone = TimeZone(identifier: calendarTimeZoneIdentifier),
              healthData.allSatisfy({
                  $0.timeContext.calendarTimeZoneIdentifier == calendarTimeZoneIdentifier
              }) else {
            throw AdapterError.invalidTimeZone
        }
        let capturedDays = healthData.enumerated().map { index, day in
            (index: index, day: day, ownerDate: ownerDateString(day.date, timeZone: calendarTimeZone))
        }.sorted { $0.ownerDate < $1.ownerDate }
        guard Set(capturedDays.map(\.ownerDate)).count == capturedDays.count else {
            throw AdapterError.duplicateOwnerDate
        }
        let semanticBySelection = Dictionary(
            uniqueKeysWithValues: registry.metrics.map { ($0.selectionId, $0.semanticId) }
        )
        let bloodPressureSelectionIDs = registry.metrics.map(\.selectionId).filter {
            $0.contains("systolic") || $0.contains("diastolic")
        }
        var ordinal = startingSourceOrdinal
        func advanceOrdinal() throws {
            let (next, overflow) = ordinal.addingReportingOverflow(1)
            guard !overflow else { throw AdapterError.limitExceeded }
            ordinal = next
        }
        var records: [[String: Any]] = []
        var retainedTokens: [String] = []
        var extensionLocations: [String: ExtensionLocation] = [:]

        for capturedDay in capturedDays {
            let dayIndex = capturedDay.index
            let day = capturedDay.day
            let snapshot = day.exportSnapshot(customization: customization)
            let ownerDate = capturedDay.ownerDate
            let exactDay = try exactTimestamp(day.date, calendarTimeZone: calendarTimeZone)
            for output in registry.outputs {
                guard output.surface == "flat",
                      let raw = snapshot.frontmatterMetrics[output.key],
                      let selectionID = output.selectionIds.first,
                      let semanticID = semanticBySelection[selectionID]
                else { continue }
                let attributedSelectionIDs = output.selectionIds.contains(where: {
                    $0.contains("systolic") || $0.contains("diastolic")
                }) && bloodPressureSelectionIDs.count == 2
                    ? bloodPressureSelectionIDs
                    : output.selectionIds
                try advanceOrdinal()
                records.append([
                    "record_id": "apple-daily-\(ownerDate)-\(output.key)",
                    "source_ordinal": String(ordinal),
                    "owner_date": ownerDate,
                    "semantic_id": semanticID,
                    "selection_ids": attributedSelectionIDs,
                    "attribution": "direct",
                    "kind": "sdk_aggregate",
                    "output_key": output.key,
                    "aggregation": "pass_through",
                    "start": exactDay,
                    "end": NSNull(),
                    "value": try semanticValue(
                        raw,
                        unit: output.unit,
                        outputKey: output.key,
                        day: day,
                        calendarTimeZone: calendarTimeZone
                    ),
                    "weight": NSNull(),
                    "attributes": [:],
                    "extensions": [],
                ])
            }

            if let archive = day.healthKitRecordArchive {
                guard archive.dailyOwnership.ownerDate == ownerDate,
                      archive.dailyOwnership.calendarTimeZoneIdentifier == calendarTimeZoneIdentifier
                else { throw AdapterError.invalidArchiveOwnership }
                let extensionSources: [(ExtensionLocation.Collection, Int, String, [String], HealthKitRecordInclusionReason)] =
                    archive.records.enumerated().map {
                        (.healthKitRecord, $0.offset, $0.element.originalUUID.uuidString, $0.element.selectedMetricIDs, $0.element.includedBecause)
                    } + archive.externalRecords.enumerated().map {
                        (.externalRecord, $0.offset, $0.element.externalIdentifier, $0.element.selectedMetricIDs, $0.element.includedBecause)
                    } + archive.medicationInventoryRecords.enumerated().map {
                        (.medicationInventory, $0.offset, $0.element.externalIdentifier, $0.element.selectedMetricIDs, $0.element.includedBecause)
                    }
                for (collection, recordIndex, nativeIdentity, rawSelectionIDs, inclusionReason) in extensionSources {
                    let selectionIDs = rawSelectionIDs.filter { semanticBySelection[$0] != nil }.sorted()
                    guard let selectionID = selectionIDs.first,
                          let semanticID = semanticBySelection[selectionID] else { continue }
                    try advanceOrdinal()
                    let token = stableToken(
                        namespace: "apple.\(collection.rawValue)",
                        identity: "\(ownerDate)\u{1f}\(nativeIdentity)"
                    )
                    retainedTokens.append(token)
                    extensionLocations[token] = ExtensionLocation(
                        dayIndex: dayIndex,
                        collection: collection,
                        recordIndex: recordIndex
                    )
                    let attribution = inclusionReason == .relationshipDependency ? "dependency" : "direct"
                    records.append([
                        "record_id": "apple-extension-\(token)",
                        "source_ordinal": String(ordinal),
                        "owner_date": ownerDate,
                        "semantic_id": semanticID,
                        "selection_ids": selectionIDs,
                        "attribution": attribution,
                        "kind": "extension_ref",
                        "output_key": NSNull(),
                        "aggregation": "pass_through",
                        "start": NSNull(),
                        "end": NSNull(),
                        "value": NSNull(),
                        "weight": NSNull(),
                        "attributes": [:],
                        "extensions": [[
                            "namespace": "apple.healthkit_archive",
                            "version": 1,
                            "retention_token": token,
                            "selection_ids": selectionIDs,
                        ]],
                    ])
                }
            }
        }

        let data = try canonicalJSON([
            "schema": "healthmd.semantic_input",
            "semantic_input_version": semanticInputVersion,
            "session_id": sessionID,
            "batch_index": batchIndex,
            "final_batch": finalBatch,
            "owner_dates": capturedDays.map(\.ownerDate),
            "records": records,
        ])
        return EncodedBatch(
            data: data,
            nextSourceOrdinal: ordinal,
            retainedExtensionTokens: retainedTokens,
            extensionLocations: extensionLocations
        )
    }

    /// Splits one captured model into valid coarse batches without changing stable record identity.
    @MainActor
    static func boundedBatches(
        sessionID: String,
        firstBatchIndex: UInt32 = 0,
        healthData: [HealthData],
        registry: CoreMetricRegistrySnapshot,
        customization: FormatCustomization,
        calendarTimeZoneIdentifier: String,
        startingSourceOrdinal: UInt64 = 0
    ) throws -> [EncodedBatch] {
        guard healthData.count <= 400 else {
            throw AdapterError.limitExceeded
        }
        guard (calendarTimeZoneIdentifier == "UTC"
                || TimeZone.knownTimeZoneIdentifiers.contains(calendarTimeZoneIdentifier)),
              let calendarTimeZone = TimeZone(identifier: calendarTimeZoneIdentifier) else {
            throw AdapterError.invalidTimeZone
        }
        let orderedDays = healthData.enumerated().map { index, day in
            (
                originalIndex: index,
                day: day,
                ownerDate: ownerDateString(day.date, timeZone: calendarTimeZone)
            )
        }.sorted { $0.ownerDate < $1.ownerDate }
        guard Set(orderedDays.map(\.ownerDate)).count == orderedDays.count else {
            throw AdapterError.duplicateOwnerDate
        }

        var payloads: [([String: Any], [String])] = []
        var extensionLocations: [String: ExtensionLocation] = [:]
        var sourceOrdinal = startingSourceOrdinal
        var totalRecordCount = 0
        var totalRecordBytes = 0

        for capturedDay in orderedDays {
            let encodedDay = try batch(
                sessionID: sessionID,
                batchIndex: firstBatchIndex,
                finalBatch: false,
                healthData: [capturedDay.day],
                registry: registry,
                customization: customization,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
                startingSourceOrdinal: sourceOrdinal
            )
            guard let object = try JSONSerialization.jsonObject(with: encodedDay.data) as? [String: Any],
                  let records = object["records"] as? [[String: Any]],
                  object["owner_dates"] as? [String] == [capturedDay.ownerDate] else {
                throw AdapterError.serializationFailed
            }
            let nextRecordCount = totalRecordCount.addingReportingOverflow(records.count)
            guard !nextRecordCount.overflow, nextRecordCount.partialValue <= 100_000 else {
                throw AdapterError.limitExceeded
            }
            totalRecordCount = nextRecordCount.partialValue
            for record in records {
                let count = try canonicalJSON(record).count
                let nextBytes = totalRecordBytes.addingReportingOverflow(count)
                guard count <= 64 * 1024,
                      !nextBytes.overflow,
                      nextBytes.partialValue <= 32 * 1024 * 1024 else {
                    throw AdapterError.limitExceeded
                }
                totalRecordBytes = nextBytes.partialValue
            }
            for (token, location) in encodedDay.extensionLocations {
                guard extensionLocations[token] == nil else {
                    throw AdapterError.serializationFailed
                }
                extensionLocations[token] = ExtensionLocation(
                    dayIndex: capturedDay.originalIndex,
                    collection: location.collection,
                    recordIndex: location.recordIndex
                )
            }
            sourceOrdinal = encodedDay.nextSourceOrdinal

            if records.isEmpty {
                payloads.append((batchObject(
                    sessionID: sessionID,
                    batchIndex: 0,
                    finalBatch: false,
                    ownerDates: [capturedDay.ownerDate],
                    records: []
                ), []))
                continue
            }
            var chunk: [[String: Any]] = []
            for record in records {
                let candidate = chunk + [record]
                let candidateObject = batchObject(
                    sessionID: sessionID,
                    batchIndex: 0,
                    finalBatch: false,
                    ownerDates: [capturedDay.ownerDate],
                    records: candidate
                )
                let candidateTooLarge = try canonicalJSON(candidateObject).count > 1_048_576
                if !chunk.isEmpty && (candidate.count > 4_096 || candidateTooLarge) {
                    payloads.append((batchObject(
                        sessionID: sessionID,
                        batchIndex: 0,
                        finalBatch: false,
                        ownerDates: [capturedDay.ownerDate],
                        records: chunk
                    ), extensionTokens(in: chunk)))
                    chunk = [record]
                } else {
                    chunk = candidate
                }
            }
            let finalObject = batchObject(
                sessionID: sessionID,
                batchIndex: 0,
                finalBatch: false,
                ownerDates: [capturedDay.ownerDate],
                records: chunk
            )
            guard try canonicalJSON(finalObject).count <= 1_048_576 else {
                throw AdapterError.limitExceeded
            }
            payloads.append((finalObject, extensionTokens(in: chunk)))
        }
        if payloads.isEmpty {
            payloads.append((batchObject(
                sessionID: sessionID,
                batchIndex: 0,
                finalBatch: true,
                ownerDates: [],
                records: []
            ), []))
        }

        let batches = try payloads.enumerated().map { offset, payload in
            var object = payload.0
            let (batchIndex, overflow) = firstBatchIndex.addingReportingOverflow(UInt32(offset))
            guard !overflow else { throw AdapterError.limitExceeded }
            object["batch_index"] = batchIndex
            object["final_batch"] = offset == payloads.count - 1
            let tokens = payload.1
            let nextOrdinal = (object["records"] as? [[String: Any]])?
                .compactMap { ($0["source_ordinal"] as? String).flatMap(UInt64.init) }
                .max() ?? startingSourceOrdinal
            let data = try canonicalJSON(object)
            guard data.count <= 1_048_576 else { throw AdapterError.limitExceeded }
            return EncodedBatch(
                data: data,
                nextSourceOrdinal: nextOrdinal,
                retainedExtensionTokens: tokens,
                extensionLocations: extensionLocations.filter { tokens.contains($0.key) }
            )
        }
        guard batches.reduce(0, { $0 + $1.data.count }) <= 32 * 1024 * 1024 else {
            throw AdapterError.limitExceeded
        }
        return batches
    }

    static func exactTimestamp(
        _ date: Date,
        sourceUTCOffsetSeconds: Int? = nil,
        calendarTimeZone: TimeZone
    ) throws -> [String: Any] {
        let interval = date.timeIntervalSince1970
        guard interval.isFinite else { throw AdapterError.nonFiniteNumber }
        var seconds = floor(interval)
        var nanoseconds = ((interval - seconds) * 1_000_000_000).rounded()
        if nanoseconds >= 1_000_000_000 {
            seconds += 1
            nanoseconds = 0
        }
        guard seconds >= -9_223_372_036_854_775_808.0,
              seconds < 9_223_372_036_854_775_808.0,
              nanoseconds >= 0, nanoseconds <= 999_999_999
        else { throw AdapterError.nonFiniteNumber }
        let sourceOffset: Any = if let sourceUTCOffsetSeconds {
            sourceUTCOffsetSeconds
        } else {
            NSNull()
        }
        return [
            "epoch_seconds": String(Int64(seconds)),
            "nanoseconds": Int(nanoseconds),
            "source_utc_offset_seconds": sourceOffset,
            "calendar_utc_offset_seconds": calendarTimeZone.secondsFromGMT(for: date),
        ]
    }

    static func binary64(_ value: Double, unitID: String) throws -> [String: Any] {
        guard value.isFinite else { throw AdapterError.nonFiniteNumber }
        return [
            "value_type": "number",
            "number": [
                "representation": "binary64",
                "bits": String(format: "%016llx", value.bitPattern),
            ],
            "unit": ["id": unitID],
        ]
    }

    static func canonicalJSON(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw AdapterError.serializationFailed
        }
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw AdapterError.serializationFailed
        }
    }

    private static func semanticValue(
        _ raw: String,
        unit: String,
        outputKey: String,
        day: HealthData,
        calendarTimeZone: TimeZone
    ) throws -> [String: Any] {
        let sourceTime: Date? = switch outputKey {
        case "sleep_bedtime": day.sleep.sessionStart
        case "sleep_wake": day.sleep.sessionEnd
        default: nil
        }
        if let sourceTime {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = calendarTimeZone
            let components = calendar.dateComponents([.hour, .minute], from: sourceTime)
            if let hour = components.hour, let minute = components.minute {
                return try binary64(
                    Double(hour * 60 + minute),
                    unitID: "time_of_day_minute"
                )
            }
        }
        if let minutes = minutesFromTime(raw), unit.lowercased() == "time" {
            return try binary64(Double(minutes), unitID: "time_of_day_minute")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" || trimmed == "false" {
            return ["value_type": "boolean", "boolean": trimmed == "true"]
        }
        if let unsigned = UInt64(trimmed), String(unsigned) == trimmed {
            return [
                "value_type": "number",
                "number": ["representation": "unsigned_integer", "decimal": trimmed],
                "unit": ["id": internalUnitID(unit)],
            ]
        }
        if let signed = Int64(trimmed), String(signed) == trimmed {
            return [
                "value_type": "number",
                "number": ["representation": "signed_integer", "decimal": trimmed],
                "unit": ["id": internalUnitID(unit)],
            ]
        }
        if let numeric = Double(trimmed) {
            return try binary64(numeric, unitID: internalUnitID(unit))
        }
        if let list = listValues(raw) {
            return ["value_type": "text_list", "items": list]
        }
        return ["value_type": "text", "text": raw]
    }

    private static func batchObject(
        sessionID: String,
        batchIndex: UInt32,
        finalBatch: Bool,
        ownerDates: [String],
        records: [[String: Any]]
    ) -> [String: Any] {
        [
            "schema": "healthmd.semantic_input",
            "semantic_input_version": semanticInputVersion,
            "session_id": sessionID,
            "batch_index": batchIndex,
            "final_batch": finalBatch,
            "owner_dates": ownerDates,
            "records": records,
        ]
    }

    private static func extensionTokens(in records: [[String: Any]]) -> [String] {
        records.flatMap { record in
            (record["extensions"] as? [[String: Any]])?.compactMap {
                $0["retention_token"] as? String
            } ?? []
        }.sorted()
    }

    private static func stableToken(namespace: String, identity: String) -> String {
        SHA256.hash(data: Data("\(namespace)\u{1f}\(identity)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func ownerDateString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func minutesFromTime(_ raw: String) -> Int? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["HH:mm:ss", "H:mm:ss", "HH:mm", "H:mm", "h:mm:ss a", "hh:mm:ss a", "h:mm a", "hh:mm a"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            guard let date = formatter.date(from: value) else { continue }
            let components = Calendar(identifier: .gregorian).dateComponents(
                [.hour, .minute],
                from: date
            )
            return (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
        return nil
    }

    private static func listValues(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        let body = trimmed.dropFirst().dropLast()
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        return body.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.sorted()
    }

    private static func internalUnitID(_ unit: String) -> String {
        switch unit.lowercased() {
        case "steps", "count", "entries", "drinks", "events", "falls", "floors", "pushes", "sessions", "strokes", "uses": "count"
        case "sec", "second", "seconds": "second"
        case "min", "minute", "minutes": "minute"
        case "hour", "hours": "hour"
        case "m": "meter"
        case "km": "kilometer"
        case "mi": "mile"
        case "m/s": "meter_per_second"
        case "km/h": "kilometer_per_hour"
        case "mph": "mile_per_hour"
        case "kg": "kilogram"
        case "lbs", "lb": "pound"
        case "kg/m²": "kilogram_per_square_meter"
        case "g": "gram"
        case "mg": "milligram"
        case "µg", "mcg": "microgram"
        case "l": "liter"
        case "oz", "fl oz": "fluid_ounce"
        case "kcal": "kilocalorie"
        case "kcal/hr/kg": "kilocalorie_per_hour_kilogram"
        case "bpm": "beat_per_minute"
        case "breaths/min": "breath_per_minute"
        case "ms": "millisecond"
        case "%", "percent": "percent_0_100"
        case "°c", "c": "degree_celsius"
        case "°f", "f": "degree_fahrenheit"
        case "mmhg": "millimeter_hg"
        case "mg/dl": "milligram_per_deciliter"
        case "iu": "international_unit"
        case "w": "watt"
        case "rpm": "revolution_per_minute"
        case "spm", "steps/min": "step_per_minute"
        case "cm": "centimeter"
        case "ft/in", "in": "inch"
        case "db": "decibel"
        case "µs": "microsiemens"
        case "l/min": "liter_per_minute"
        case "ml/kg/min": "milliliter_per_kilogram_minute"
        default: "unitless"
        }
    }
}

/// Executes synchronous coarse FFI batches away from the main actor and propagates task cancellation.
nonisolated enum HealthMdSemanticSessionRunner {
    static func process(configuration: Data, batches: [Data]) async throws -> Data {
        let session = try HealthMdCoreService().semanticSession(configuration: configuration)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                guard !batches.isEmpty else {
                    throw HealthMdSemanticInputAdapter.AdapterError.invalidSessionResult
                }
                var result = Data()
                for batch in batches {
                    try Task.checkCancellation()
                    result = try session.process(batch: batch)
                    if let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
                       object["state"] as? String == "cancelled" {
                        throw CancellationError()
                    }
                }
                guard let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
                      object["state"] as? String == "completed" else {
                    throw HealthMdSemanticInputAdapter.AdapterError.invalidSessionResult
                }
                return result
            }.value
        } onCancel: {
            session.cancel()
        }
    }
}

/// Compares canonical semantic results without returning values or identifiers.
nonisolated enum HealthMdSemanticShadowComparator {
    static func differences(legacy: Data, rust: Data) -> [String] {
        guard let legacyObject = try? JSONSerialization.jsonObject(with: legacy),
              let rustObject = try? JSONSerialization.jsonObject(with: rust)
        else { return ["/result/invalid_json"] }
        return JSONSerializationCanonicalComparator.differences(
            legacy: legacyObject,
            rust: rustObject
        )
    }
}

private nonisolated enum JSONSerializationCanonicalComparator {
    static func differences(legacy: Any, rust: Any, path: String = "") -> [String] {
        if let left = legacy as? [String: Any], let right = rust as? [String: Any] {
            let keys = Set(left.keys).union(right.keys).sorted()
            return keys.flatMap { key in
                guard let leftValue = left[key], let rightValue = right[key] else {
                    return ["\(path)/\(key)"]
                }
                return differences(legacy: leftValue, rust: rightValue, path: "\(path)/\(key)")
            }
        }
        if let left = legacy as? [Any], let right = rust as? [Any] {
            var result: [String] = left.count == right.count ? [] : ["\(path)/count"]
            for index in 0 ..< min(left.count, right.count) {
                result += differences(legacy: left[index], rust: right[index], path: "\(path)/\(index)")
            }
            return result
        }
        let leftData = try? JSONSerialization.data(withJSONObject: [legacy], options: [.sortedKeys])
        let rightData = try? JSONSerialization.data(withJSONObject: [rust], options: [.sortedKeys])
        return leftData == rightData ? [] : [path.isEmpty ? "/" : path]
    }
}
