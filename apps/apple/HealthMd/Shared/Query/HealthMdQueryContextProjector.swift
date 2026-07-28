import Foundation

/// Explicit information supplied by a capture/corpus caller when it knows more
/// than a decoded `HealthData` value can express on its own.
nonisolated struct HealthMdContextProjectionOptions: Sendable {
    /// Nil means the current default-enabled catalog plus every metric named by
    /// summary/archive evidence. A non-nil set is authoritative.
    let enabledMetricIDs: Set<String>?
    /// Used for corpus facts such as a day or provider branch known not to have
    /// synchronized. Overrides never replace a value that is actually present.
    let unavailableMetricStatuses: [String: HealthMdAvailabilityStatus]
    /// False for provider-only context acquisition. In that mode the placeholder
    /// HealthData value supplies date ownership only and must not emit Apple
    /// Health metric/workout/session placeholders.
    let includesAppleHealth: Bool

    init(
        enabledMetricIDs: Set<String>? = nil,
        unavailableMetricStatuses: [String: HealthMdAvailabilityStatus] = [:],
        includesAppleHealth: Bool = true
    ) {
        self.enabledMetricIDs = enabledMetricIDs
        self.unavailableMetricStatuses = unavailableMetricStatuses
        self.includesAppleHealth = includesAppleHealth
    }
}

/// Pure, deterministic projection from one captured daily source value into the
/// compact query contract. It performs no HealthKit, file, network, or store I/O.
@MainActor
enum HealthMdQueryContextProjector {
    static func project(
        _ healthData: HealthData,
        externalProviderRecords: [ExternalDailyRecord] = [],
        options: HealthMdContextProjectionOptions = .init()
    ) throws -> HealthMdCompactContextDay {
        let ownership = ownership(for: healthData)
        let ownerDate = ownership.ownerDate
        let definitions = Dictionary(uniqueKeysWithValues: HealthMetrics.all.map { ($0.id, $0) })
        let dictionaryEntries = HealthMetricDataDictionary.entries()
        let entriesByKey = Dictionary(uniqueKeysWithValues: dictionaryEntries.map { ($0.canonicalKey, $0) })
        let archive = options.includesAppleHealth ? healthData.healthKitRecordArchive : nil

        let flat = options.includesAppleHealth
            ? ExportFrontmatterMetricBuilder.build(
                from: healthData,
                converter: UnitConverter(preference: .metric),
                timeFormat: .hour24,
                timeZone: ownership.timeZone
            )
            : [:]

        var enabled = options.includesAppleHealth
            ? (options.enabledMetricIDs ?? Set(
                HealthMetrics.all.lazy.filter(\.isEnabledByDefault).map(\.id)
            ))
            : []
        if options.enabledMetricIDs == nil {
            enabled.formUnion(flat.keys.compactMap { entriesByKey[$0]?.metricId })
            enabled.formUnion(archiveMetricIDs(archive))
        }

        var evidenceDrafts: [EvidenceDraft] = []
        var metricEvidence: [String: Set<String>] = [:]

        func appendEvidence(
            locator: HealthMdEvidenceLocator,
            sourceID: String,
            providerID: String? = nil,
            value: HealthMdQueryValue? = nil,
            note: String? = nil,
            metricIDs: [String] = []
        ) throws {
            let draft = EvidenceDraft(
                locator: locator,
                sourceID: sourceID,
                providerID: providerID,
                value: value,
                note: note,
                metricIDs: Array(Set(metricIDs)).sorted()
            )
            let id = try draft.stableID()
            if !evidenceDrafts.contains(where: { $0.id == id }) { evidenceDrafts.append(draft.withID(id)) }
            for metricID in metricIDs { metricEvidence[metricID, default: []].insert(id) }
        }

        // Every represented summary key is independently addressable. This also
        // retains secondary v7 keys (min/max/provenance/list fields) even though
        // the compact metric observation uses the dictionary's primary key.
        for key in flat.keys.sorted() {
            let entry = entriesByKey[key]
            let value = typedSummaryValue(flat[key]!, key: key, entry: entry, healthData: healthData)
            try appendEvidence(
                locator: .summaryKey(ownerDate: ownerDate, key: key),
                sourceID: HealthMdEvidenceSourceIDs.healthMdSummary,
                value: value,
                note: entry.map { "daily_aggregation=\($0.dailyAggregation)" },
                metricIDs: entry.map { [$0.metricId] } ?? []
            )
        }

        if let archive {
            for record in archive.records {
                let ids = directMetricIDs(record)
                try appendEvidence(
                    locator: .canonicalUUID(ownerDate: ownerDate, uuid: record.originalUUID.uuidString.lowercased()),
                    sourceID: HealthMdEvidenceSourceIDs.appleHealth,
                    value: recordDetail(record),
                    note: "\(record.objectTypeIdentifier); kind=\(record.recordKind.rawValue)",
                    metricIDs: ids
                )
            }
            for record in archive.externalRecords {
                let ids = directMetricIDs(record)
                try appendEvidence(
                    locator: .externalIdentity(ownerDate: ownerDate, identifier: record.externalIdentifier),
                    sourceID: HealthMdEvidenceSourceIDs.appleHealth,
                    value: externalRecordDetail(record),
                    note: "\(record.objectTypeIdentifier); identity=\(record.externalIdentityKind.rawValue)",
                    metricIDs: ids
                )
            }
            for record in archive.medicationInventoryRecords {
                try appendEvidence(
                    locator: .externalIdentity(ownerDate: ownerDate, identifier: record.externalIdentifier),
                    sourceID: HealthMdEvidenceSourceIDs.appleHealth,
                    value: .unknown(type: "medication_inventory", value: .object([
                        "display_name": record.displayName.map(HealthMdJSONValue.string) ?? .null,
                        "fields": .object(record.fields.mapValues(metadataJSON))
                    ])),
                    note: record.objectTypeIdentifier,
                    metricIDs: record.selectedMetricIDs
                )
            }
            for result in archive.queryResults {
                try appendEvidence(
                    locator: .queryManifest(ownerDate: ownerDate, identifier: result.identifier),
                    sourceID: HealthMdEvidenceSourceIDs.appleHealth,
                    value: queryResultDetail(result),
                    note: result.statusDescription ?? result.error?.description,
                    metricIDs: result.metricIDs
                )
            }
            for warning in archive.integrityWarnings {
                try appendEvidence(
                    locator: .warning(ownerDate: ownerDate, code: warning.code),
                    sourceID: HealthMdEvidenceSourceIDs.appleHealth,
                    value: .array(warning.recordUUIDs.map { .string($0.uuidString.lowercased()) }),
                    note: warning.message,
                    metricIDs: warning.metricIDs
                )
            }
        }

        for failure in options.includesAppleHealth
            ? ExportDiagnosticSerializer.sorted(healthData.partialFailures) : [] {
            let identifier = try stableFailureIdentifier(failure)
            let matched = matchedMetricIDs(failure.dataType, definitions: definitions)
            try appendEvidence(
                locator: .partialFailure(ownerDate: ownerDate, identifier: identifier),
                sourceID: HealthMdEvidenceSourceIDs.appleHealth,
                value: .unknown(type: "partial_failure", value: .object([
                    "data_type": .string(failure.dataType),
                    "date_range": .string(failure.dateRangeDescription),
                    "error": .string(failure.errorDescription)
                ])),
                note: failure.summary,
                metricIDs: matched
            )
        }

        // Provider sidecars remain provider-native. They are evidence, not
        // silently normalized Apple Health metrics. A separate fetch diagnostic
        // links the exact requested metric scope to each provider/day so fresh
        // completion can verify every requested source without inventing values.
        for record in externalProviderRecords
            .filter({ $0.date == ownerDate })
            .sorted(by: providerRecordOrder) {
            let providerStatus = providerRecordStatus(record)
            let providerMetricIDs = options.enabledMetricIDs.map { Array($0).sorted() } ?? []
            let diagnosticMetricIDs: [String?] = providerMetricIDs.isEmpty
                ? [nil] : providerMetricIDs.map(Optional.some)
            for metricID in diagnosticMetricIDs {
                let metricIDs = metricID.map { [$0] } ?? []
                try appendEvidence(
                    locator: .queryManifest(
                        ownerDate: ownerDate,
                        identifier: ["provider_daily_fetch", record.provider.rawValue, metricID]
                            .compactMap { $0 }
                            .joined(separator: ":")
                    ),
                    sourceID: HealthMdEvidenceSourceIDs.providerNative,
                    providerID: record.provider.rawValue,
                    value: .unknown(type: "external_provider_fetch_result", value: .object([
                        "status": .string(providerStatus.rawValue),
                        "metric_ids": .array(metricIDs.map(HealthMdJSONValue.string)),
                        "payload_count": .integer(Int64(record.payloads.count)),
                        "warning_count": .integer(Int64(record.warnings.count))
                    ])),
                    note: "Provider-native daily fetch result",
                    metricIDs: metricIDs
                )
            }
            for payload in record.payloads.sorted(by: providerPayloadOrder) {
                let identity = try providerIdentity(record: record, payload: payload)
                try appendEvidence(
                    locator: .externalIdentity(ownerDate: ownerDate, identifier: identity),
                    sourceID: HealthMdEvidenceSourceIDs.providerNative,
                    providerID: record.provider.rawValue,
                    value: .unknown(type: "external_provider_payload", value: .object([
                        "provider": .string(record.provider.rawValue),
                        "name": .string(payload.name),
                        "endpoint": .string(safeProviderEndpoint(payload.endpoint)),
                        "status_code": .integer(Int64(payload.statusCode)),
                        "fetched_at": .string(CanonicalRFC3339UTC.string(from: payload.fetchedAt)),
                        "data": payload.data.map(providerJSON) ?? .null,
                        "error": payload.error.map(HealthMdJSONValue.string) ?? .null
                    ])),
                    note: "Provider-native daily sidecar payload"
                )
            }
            for warning in record.warnings.sorted() {
                let code = "provider.\(record.provider.rawValue).\(try shortHash(warning))"
                try appendEvidence(
                    locator: .warning(ownerDate: ownerDate, code: code),
                    sourceID: HealthMdEvidenceSourceIDs.providerNative,
                    providerID: record.provider.rawValue,
                    note: warning
                )
            }
        }

        var metricDrafts: [MetricDraft] = []
        for metricID in enabled.sorted() {
            let definition = definitions[metricID]
            let keys = HealthMetricExportMapping.frontmatterKeys(for: metricID)
            let selectedKey = keys.first(where: { flat[$0] != nil })
            let entry = selectedKey.flatMap { entriesByKey[$0] }
            let summaryValue = selectedKey.flatMap { key in
                flat[key].map { typedSummaryValue($0, key: key, entry: entry, healthData: healthData) }
            }
            let archiveValue = summaryValue == nil
                ? aggregateArchiveValue(metricID: metricID, definition: definition, archive: archive)
                : nil
            let value = summaryValue ?? archiveValue
            var evidenceIDs = metricEvidence[metricID, default: []]
            let availability = metricAvailability(
                metricID: metricID,
                hasValue: value != nil,
                archive: archive,
                captureStatus: healthData.healthKitRecordCaptureStatus,
                partialFailures: healthData.partialFailures,
                override: options.unavailableMetricStatuses[metricID],
                explicitSummarySelection: options.enabledMetricIDs != nil
            )
            if options.includesAppleHealth,
               options.enabledMetricIDs != nil,
               evidenceIDs.isEmpty {
                try appendEvidence(
                    locator: .queryManifest(
                        ownerDate: ownerDate,
                        identifier: "summary_capture:\(metricID)"
                    ),
                    sourceID: HealthMdEvidenceSourceIDs.appleHealth,
                    value: .unknown(type: "healthmd_summary_capture_result", value: .object([
                        "status": .string(availability.rawValue),
                        "metric_ids": .array([.string(metricID)])
                    ])),
                    note: "Request-scoped Apple Health summary capture result",
                    metricIDs: [metricID]
                )
                evidenceIDs = metricEvidence[metricID, default: []]
            }
            let aggregation = entry.flatMap { HealthMdDailyAggregation(rawValue: $0.dailyAggregation) }
                ?? definition.map(dailyAggregation)
            let limitations = metricLimitations(metricID: metricID, archive: archive)
            metricDrafts.append(.init(
                observationID: "summary:\(ownerDate):\(metricID)",
                metricID: metricID,
                displayName: definition?.name ?? metricID,
                value: value,
                status: availability,
                dailyAggregation: aggregation,
                evidenceIDs: evidenceIDs.sorted(),
                limitations: limitations
            ))
        }

        let workoutDrafts = (options.includesAppleHealth ? healthData.workouts : []).map { workout -> WorkoutDraft in
            let sourceUUID = workout.sourceUUID ?? workout.id
            var ids = Set<String>()
            let canonicalID = try? EvidenceDraft(
                locator: .canonicalUUID(ownerDate: ownerDate, uuid: sourceUUID.uuidString.lowercased()),
                sourceID: HealthMdEvidenceSourceIDs.appleHealth,
                providerID: nil,
                value: nil,
                note: nil,
                metricIDs: []
            ).stableID()
            if let canonicalID, evidenceDrafts.contains(where: { $0.id == canonicalID }) {
                ids.insert(canonicalID)
            }
            let summaryKey = "workouts[id=\(sourceUUID.uuidString.lowercased())]"
            let summaryDraft = EvidenceDraft(
                locator: .summaryKey(ownerDate: ownerDate, key: summaryKey),
                sourceID: HealthMdEvidenceSourceIDs.healthMdSummary,
                providerID: nil,
                value: workoutDetail(workout),
                note: "Workout compatibility summary",
                metricIDs: []
            )
            if let summaryID = try? summaryDraft.stableID() {
                if !evidenceDrafts.contains(where: { $0.id == summaryID }) {
                    evidenceDrafts.append(summaryDraft.withID(summaryID))
                }
                ids.insert(summaryID)
            }
            return WorkoutDraft(
                workoutID: sourceUUID.uuidString.lowercased(),
                activity: workout.workoutSportName,
                start: workout.startTime,
                end: workout.endTime,
                details: workoutDetails(workout),
                evidenceIDs: ids.sorted()
            )
        }.sorted { $0.start != $1.start ? $0.start < $1.start : $0.workoutID < $1.workoutID }

        // A sleep-session result discloses total/session structure, so its
        // evidence is pinned to the `sleep_total` authorization rather than the
        // union of every narrower sleep metric.
        let sleepEvidenceIDs = (metricEvidence["sleep_total"] ?? []).sorted()
        let sleepSessions = options.includesAppleHealth
            ? try HealthMdSleepSessionQuery.contextSessions(
                sleep: healthData.sleep,
                ownerDate: ownerDate,
                ownerIntervalStart: ownership.intervalStart,
                calendarTimeZone: ownership.timeZone.identifier,
                evidenceIDs: sleepEvidenceIDs
            )
            : []

        evidenceDrafts.sort { $0.id < $1.id }
        metricDrafts.sort { $0.metricID < $1.metricID }
        let digest = try HealthMdQueryCanonicalSerializer.sha256(of: DigestMaterial(
            sourceSchema: HealthMdExportSchema.identifier,
            sourceSchemaVersion: HealthMdExportSchema.version,
            ownerDate: ownerDate,
            intervalStart: ownership.intervalStart,
            intervalEnd: ownership.intervalEnd,
            calendarTimeZone: ownership.timeZone.identifier,
            captureStatus: healthData.healthKitRecordCaptureStatus.rawValue,
            metrics: metricDrafts,
            workouts: workoutDrafts,
            sleepSessions: sleepSessions,
            evidence: evidenceDrafts
        ))
        let source = HealthMdSourceDescriptor(
            schema: HealthMdExportSchema.identifier,
            schemaVersion: HealthMdExportSchema.version,
            digest: digest
        )
        let evidence = evidenceDrafts.map { draft in
            HealthMdContextEvidence(
                reference: .init(
                    evidenceID: draft.id,
                    locator: draft.locator,
                    source: source,
                    sourceID: draft.sourceID,
                    providerID: draft.providerID
                ),
                value: draft.value,
                note: draft.note,
                metricIDs: draft.metricIDs
            )
        }
        let metrics = metricDrafts.map { draft in
            HealthMdContextMetric(
                observationID: draft.observationID,
                metricID: draft.metricID,
                displayName: draft.displayName,
                value: draft.value,
                status: draft.status,
                dailyAggregation: draft.dailyAggregation,
                evidenceIDs: draft.evidenceIDs,
                limitations: draft.limitations
            )
        }
        let workouts = workoutDrafts.map { draft in
            HealthMdContextWorkout(
                workoutID: draft.workoutID,
                activity: draft.activity,
                start: draft.start,
                end: draft.end,
                details: draft.details,
                evidenceIDs: draft.evidenceIDs
            )
        }
        let limitations = dayLimitations(
            healthData: healthData,
            externalProviderRecords: externalProviderRecords,
            ownerDate: ownerDate,
            includesAppleHealth: options.includesAppleHealth
        )
        return HealthMdCompactContextDay(
            ownerDate: ownerDate,
            intervalStart: ownership.intervalStart,
            intervalEnd: ownership.intervalEnd,
            calendarTimeZone: ownership.timeZone.identifier,
            source: source,
            status: options.includesAppleHealth
                ? dayAvailability(
                    healthData: healthData,
                    metrics: metrics,
                    workouts: workouts,
                    sleepSessions: sleepSessions
                )
                : providerAvailability(
                    externalProviderRecords,
                    ownerDate: ownerDate
                ),
            metrics: metrics,
            workouts: workouts,
            sleepSessions: sleepSessions,
            evidence: evidence,
            limitations: limitations
        )
    }

    // MARK: Source ownership and availability

    private struct Ownership {
        let ownerDate: String
        let intervalStart: Date
        let intervalEnd: Date
        let timeZone: TimeZone
    }

    private static func ownership(for data: HealthData) -> Ownership {
        if let source = data.healthKitRecordArchive?.dailyOwnership {
            return Ownership(
                ownerDate: source.ownerDate,
                intervalStart: source.intervalStart,
                intervalEnd: source.intervalEnd,
                timeZone: TimeZone(identifier: source.calendarTimeZoneIdentifier) ?? data.timeContext.calendarTimeZone
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = data.timeContext.calendarTimeZone
        let start = calendar.startOfDay(for: data.date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return Ownership(
            ownerDate: HealthKitDailyOwnershipMetadata.ownerDate(
                for: start,
                calendarTimeZoneIdentifier: calendar.timeZone.identifier
            ),
            intervalStart: start,
            intervalEnd: end,
            timeZone: calendar.timeZone
        )
    }

    private static func metricAvailability(
        metricID: String,
        hasValue: Bool,
        archive: HealthKitRecordArchive?,
        captureStatus: HealthKitRecordCaptureStatus,
        partialFailures: [ExportPartialFailure],
        override: HealthMdAvailabilityStatus?,
        explicitSummarySelection: Bool
    ) -> HealthMdAvailabilityStatus {
        if hasValue { return .available }
        if let override { return override }
        if partialFailures.contains(where: { matchedMetricIDs($0.dataType, definitions: Dictionary(uniqueKeysWithValues: HealthMetrics.all.map { ($0.id, $0) })).contains(metricID) }) {
            return .partial
        }
        guard let archive else {
            switch captureStatus {
            case .notRequested: return explicitSummarySelection ? .completeEmpty : .notRequested
            case .legacyUnavailable: return .legacyUnavailable
            case .partial: return .partial
            case .complete: return .notSynchronized
            }
        }
        let relevant = archive.queryResults.filter { $0.metricIDs.contains(metricID) }
        if !relevant.isEmpty {
            let statuses = Set(relevant.map(\.status))
            if statuses.count > 1 { return .partial }
            switch statuses.first! {
            case .failure: return .failed
            case .unsupported: return .unsupported
            case .skipped: return .skipped
            case .cancelled: return .cancelled
            case .success:
                return relevant.allSatisfy { $0.recordCount == 0 } ? .completeEmpty : .notSynchronized
            }
        }
        switch archive.captureStatus {
        case .complete: return .notSynchronized
        case .partial: return .partial
        case .notRequested: return .notRequested
        case .legacyUnavailable: return .legacyUnavailable
        }
    }

    private static func dayAvailability(
        healthData: HealthData,
        metrics: [HealthMdContextMetric],
        workouts: [HealthMdContextWorkout],
        sleepSessions: [HealthMdContextSleepSession]
    ) -> HealthMdAvailabilityStatus {
        switch healthData.healthKitRecordCaptureStatus {
        case .partial: return .partial
        case .notRequested: return .notRequested
        case .legacyUnavailable: return .legacyUnavailable
        case .complete:
            return metrics.contains(where: { $0.status == .available })
                || !workouts.isEmpty
                || !sleepSessions.isEmpty
                ? .available : .completeEmpty
        }
    }

    private static func providerAvailability(
        _ records: [ExternalDailyRecord],
        ownerDate: String
    ) -> HealthMdAvailabilityStatus {
        let matching = records.filter { $0.date == ownerDate }
        guard !matching.isEmpty else { return .notSynchronized }
        let statuses = Set(matching.map(providerRecordStatus))
        if statuses.count == 1 { return statuses.first! }
        if statuses.allSatisfy({ $0 == .available || $0 == .completeEmpty }) {
            return statuses.contains(.available) ? .available : .completeEmpty
        }
        return .partial
    }

    private static func providerRecordStatus(
        _ record: ExternalDailyRecord
    ) -> HealthMdAvailabilityStatus {
        let successfulPayloads = record.payloads.filter {
            $0.error == nil && (200..<300).contains($0.statusCode)
        }.count
        let failedPayloads = record.payloads.count - successfulPayloads
        if failedPayloads > 0 || !record.warnings.isEmpty {
            return successfulPayloads > 0 ? .partial : .failed
        }
        return successfulPayloads > 0 ? .available : .completeEmpty
    }

    private static func dayLimitations(
        healthData: HealthData,
        externalProviderRecords: [ExternalDailyRecord],
        ownerDate: String,
        includesAppleHealth: Bool
    ) -> [HealthMdLimitation] {
        var values: [HealthMdLimitation] = []
        if includesAppleHealth, healthData.healthKitRecordCaptureStatus != .complete {
            values.append(.init(
                code: "source_capture_\(healthData.healthKitRecordCaptureStatus.rawValue)",
                message: "Lossless source capture status is \(healthData.healthKitRecordCaptureStatus.rawValue)."
            ))
        }
        if externalProviderRecords.contains(where: { $0.date != ownerDate }) {
            values.append(.init(
                code: "external_provider_date_mismatch",
                message: "Provider records for another owner date were not projected into this day."
            ))
        }
        return values
    }

    private static func metricLimitations(metricID: String, archive: HealthKitRecordArchive?) -> [HealthMdLimitation] {
        guard let archive else { return [] }
        return archive.integrityWarnings
            .filter { $0.metricIDs.contains(metricID) }
            .map { HealthMdLimitation(code: "source_warning.\($0.code)", message: $0.message) }
    }

    // MARK: Summary values and aggregation

    private static func typedSummaryValue(
        _ raw: String,
        key: String,
        entry: HealthMetricDataDictionaryEntry?,
        healthData: HealthData
    ) -> HealthMdQueryValue {
        if key == "sleep_bedtime", let date = healthData.sleep.sessionStart { return .timestamp(date) }
        if key == "sleep_wake", let date = healthData.sleep.sessionEnd { return .timestamp(date) }
        if key == "vo2_max_source_start", let date = healthData.activity.vo2MaxSourceStartDate { return .timestamp(date) }
        if key == "vo2_max_source_end", let date = healthData.activity.vo2MaxSourceEndDate { return .timestamp(date) }
        if key == "vo2_max_carried_forward" { return .boolean(raw == "true") }
        if key == "vo2_max_source_uuid" { return .string(raw.lowercased()) }
        if raw.hasPrefix("["), raw.hasSuffix("]") {
            let content = raw.dropFirst().dropLast()
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .array([]) }
            return .array(content.split(separator: ",").map {
                .string($0.trimmingCharacters(in: .whitespacesAndNewlines))
            })
        }
        let aggregation = entry.flatMap { HealthMdDailyAggregation(rawValue: $0.dailyAggregation) }
        if aggregation == .categoryLatest {
            return .category(.init(identifier: raw, display: raw.replacingOccurrences(of: "_", with: " ")))
        }
        guard let number = Double(raw), number.isFinite else { return .string(raw) }
        if aggregation == .count || key.hasSuffix("_count") { return .count(Int64(number)) }
        let unit = entry?.unit ?? ""
        if aggregation == .durationSum || (unit == "hours" && aggregation != .count) || unit == "min" {
            let seconds = unit == "hours" ? number * 3_600 : (unit == "min" ? number * 60 : number)
            return .duration(seconds: seconds)
        }
        return .quantity(value: number, unit: unit.isEmpty ? "1" : unit)
    }

    private static func dailyAggregation(_ definition: HealthMetricDefinition) -> HealthMdDailyAggregation {
        switch definition.aggregation {
        case .cumulative: return .sum
        case .discreteAvg: return .average
        case .discreteMin: return .minimum
        case .discreteMax: return .maximum
        case .mostRecent: return definition.metricType == .category ? .categoryLatest : .latest
        case .duration: return .durationSum
        case .count: return .count
        }
    }

    private static func aggregateArchiveValue(
        metricID: String,
        definition: HealthMetricDefinition?,
        archive: HealthKitRecordArchive?
    ) -> HealthMdQueryValue? {
        guard let archive else { return nil }
        let records = archive.records.filter { directMetricIDs($0).contains(metricID) }
        let external = archive.externalRecords.filter { directMetricIDs($0).contains(metricID) }
        guard !records.isEmpty || !external.isEmpty else { return nil }
        let aggregation = definition.map(dailyAggregation) ?? .latest
        if aggregation == .count { return .count(Int64(records.count + external.count)) }
        if aggregation == .durationSum {
            return .duration(seconds: records.reduce(0) { $0 + max(0, $1.endDate.timeIntervalSince($1.startDate)) })
        }
        let quantities = records.compactMap { record -> (Double, String, Date)? in
            guard case .quantity(let payload) = record.payload, payload.value.isFinite else { return nil }
            return (payload.value, payload.unit, record.startDate)
        }
        if !quantities.isEmpty, Set(quantities.map(\.1)).count == 1 {
            let value: Double
            switch aggregation {
            case .sum: value = quantities.reduce(0) { $0 + $1.0 }
            case .average, .weightedAverage: value = quantities.reduce(0) { $0 + $1.0 } / Double(quantities.count)
            case .minimum: value = quantities.map(\.0).min()!
            case .maximum: value = quantities.map(\.0).max()!
            default: value = quantities.max(by: { $0.2 < $1.2 })!.0
            }
            return .quantity(value: value, unit: quantities[0].1)
        }
        if let latest = records.max(by: { $0.startDate < $1.startDate }),
           case .category(let category) = latest.payload {
            return .category(.init(
                identifier: category.symbolicValue ?? "raw_\(category.rawValue)",
                display: category.symbolicValue,
                rawValue: category.rawValue
            ))
        }
        let details = records.map(recordDetail) + external.map(externalRecordDetail)
        return .array(details)
    }

    // MARK: Workouts

    private static func workoutDetails(_ workout: WorkoutData) -> [String: HealthMdQueryValue] {
        var details: [String: HealthMdQueryValue] = [
            "duration": .duration(seconds: workout.duration)
        ]
        if let value = workout.calories { details["energy"] = .quantity(value: value, unit: "kcal") }
        if let value = workout.distance { details["distance"] = .quantity(value: value, unit: "m") }
        if let value = workout.avgHeartRate { details["heart_rate_average"] = .quantity(value: value, unit: "bpm") }
        if let value = workout.minHeartRate { details["heart_rate_minimum"] = .quantity(value: value, unit: "bpm") }
        if let value = workout.maxHeartRate { details["heart_rate_maximum"] = .quantity(value: value, unit: "bpm") }
        if let value = workout.avgRunningCadence { details["running_cadence_average"] = .quantity(value: value, unit: "spm") }
        if let value = workout.avgStrideLength { details["stride_length_average"] = .quantity(value: value, unit: "m") }
        if let value = workout.avgGroundContactTime { details["ground_contact_time_average"] = .quantity(value: value, unit: "ms") }
        if let value = workout.avgVerticalOscillation { details["vertical_oscillation_average"] = .quantity(value: value, unit: "cm") }
        if let value = workout.avgCyclingCadence { details["cycling_cadence_average"] = .quantity(value: value, unit: "rpm") }
        if let value = workout.avgPower { details["power_average"] = .quantity(value: value, unit: "W") }
        if let value = workout.maxPower { details["power_maximum"] = .quantity(value: value, unit: "W") }
        if let value = workout.elevationGainMeters { details["elevation_gain"] = .quantity(value: value, unit: "m") }
        if let value = workout.elevationLossMeters { details["elevation_loss"] = .quantity(value: value, unit: "m") }
        if let value = workout.isIndoor { details["is_indoor"] = .boolean(value) }
        if let value = workout.healthKitActivityType { details["healthkit_activity"] = .string(value) }
        if let value = workout.healthKitActivityTypeRawValue { details["healthkit_activity_raw"] = .count(Int64(value)) }
        return details
    }

    private static func workoutDetail(_ workout: WorkoutData) -> HealthMdQueryValue {
        .unknown(type: "workout_summary", value: .object([
            "id": .string((workout.sourceUUID ?? workout.id).uuidString.lowercased()),
            "activity": .string(workout.workoutSportName),
            "start": .string(CanonicalRFC3339UTC.string(from: workout.startTime)),
            "end": .string(CanonicalRFC3339UTC.string(from: workout.endTime)),
            "duration_seconds": .number(workout.duration)
        ]))
    }

    // MARK: Canonical evidence details

    private static func recordDetail(_ record: HealthKitRecord) -> HealthMdQueryValue {
        var detail: [String: HealthMdJSONValue] = [
            "uuid": .string(record.originalUUID.uuidString.lowercased()),
            "object_type": .string(record.objectTypeIdentifier),
            "record_kind": .string(record.recordKind.rawValue),
            "start": .string(CanonicalRFC3339UTC.string(from: record.startDate)),
            "end": .string(CanonicalRFC3339UTC.string(from: record.endDate)),
            "metric_ids": .array(directMetricIDs(record).map(HealthMdJSONValue.string))
        ]
        switch record.payload {
        case .quantity(let value):
            detail["payload"] = .object(["type": .string("quantity"), "value": .number(value.value), "unit": .string(value.unit)])
        case .category(let value):
            detail["payload"] = .object(["type": .string("category"), "raw_value": .integer(value.rawValue), "symbolic_value": value.symbolicValue.map(HealthMdJSONValue.string) ?? .null])
        case .correlation(let uuids):
            detail["payload"] = .object(["type": .string("correlation"), "components": .array(uuids.map { .string($0.uuidString.lowercased()) })])
        case .structured(let kind, let fields), .unknown(let kind, let fields):
            detail["payload"] = .object(["type": .string(kind), "fields": .object(fields.mapValues(metadataJSON))])
        case .binaryArtifactReference(let artifact):
            detail["payload"] = .object(["type": .string("binary_artifact"), "identifier": .string(artifact.identifier), "sha256": artifact.sha256.map(HealthMdJSONValue.string) ?? .null])
        }
        return .unknown(type: "canonical_healthkit_record", value: .object(detail))
    }

    private static func externalRecordDetail(_ record: HealthKitExternalRecord) -> HealthMdQueryValue {
        .unknown(type: "canonical_healthkit_external_record", value: .object([
            "external_identifier": .string(record.externalIdentifier),
            "identity_kind": .string(record.externalIdentityKind.rawValue),
            "object_type": .string(record.objectTypeIdentifier),
            "record_kind": .string(record.recordKind.rawValue),
            "metric_ids": .array(directMetricIDs(record).map(HealthMdJSONValue.string)),
            "fields": .object(record.fields.mapValues(metadataJSON))
        ]))
    }

    private static func queryResultDetail(_ result: HealthKitQueryResult) -> HealthMdQueryValue {
        .unknown(type: "healthkit_query_result", value: .object([
            "identifier": .string(result.identifier),
            "operation": .string(result.operation),
            "status": .string(result.status.rawValue),
            "record_count": .integer(Int64(result.recordCount)),
            "metric_ids": .array(result.metricIDs.map(HealthMdJSONValue.string)),
            "interval_start": .string(CanonicalRFC3339UTC.string(from: result.interval.startDate)),
            "interval_end": .string(CanonicalRFC3339UTC.string(from: result.interval.endDate))
        ]))
    }

    private static func metadataJSON(_ value: HealthKitMetadataValue) -> HealthMdJSONValue {
        switch value {
        case .null: return .null
        case .string(let value): return .string(value)
        case .bool(let value): return .boolean(value)
        case .signedInteger(let value): return .integer(value)
        case .unsignedInteger(let value): return .unsignedInteger(value)
        case .floatingPoint(let value): return value.isFinite ? .number(value) : .string(String(describing: value))
        case .date(let value): return .string(CanonicalRFC3339UTC.string(from: value))
        case .data(let value): return .string(value.base64EncodedString())
        case .url(let value): return .string(value.absoluteString)
        case .quantity(let value): return .object([
            "value": value.value.map(HealthMdJSONValue.number) ?? .null,
            "unit": value.unit.map(HealthMdJSONValue.string) ?? .null,
            "raw_description": .string(value.rawDescription)
        ])
        case .array(let values): return .array(values.map(metadataJSON))
        case .dictionary(let values): return .object(values.mapValues(metadataJSON))
        case .unsupported(let type, let description): return .object(["type": .string(type), "description": .string(description)])
        }
    }

    private static func providerJSON(_ value: JSONValue) -> HealthMdJSONValue {
        switch value {
        case .null: return .null
        case .bool(let value): return .boolean(value)
        case .number(let value): return .number(value)
        case .string(let value): return .string(value)
        case .array(let values): return .array(values.map(providerJSON))
        case .object(let values): return .object(values.mapValues(providerJSON))
        }
    }

    // MARK: Identity and deterministic material

    private static func archiveMetricIDs(_ archive: HealthKitRecordArchive?) -> Set<String> {
        guard let archive else { return [] }
        return Set(archive.records.flatMap(directMetricIDs)
            + archive.externalRecords.flatMap(directMetricIDs)
            + archive.medicationInventoryRecords.flatMap(\.selectedMetricIDs)
            + archive.queryResults.flatMap(\.metricIDs))
    }

    private static func directMetricIDs(_ record: HealthKitRecord) -> [String] {
        if let attribution = record.metricAttribution { return attribution.directMetricIDs }
        return record.includedBecause == .selectedMetric ? record.selectedMetricIDs : []
    }

    private static func directMetricIDs(_ record: HealthKitExternalRecord) -> [String] {
        if let attribution = record.metricAttribution { return attribution.directMetricIDs }
        return record.includedBecause == .selectedMetric ? record.selectedMetricIDs : []
    }

    private static func matchedMetricIDs(
        _ dataType: String,
        definitions: [String: HealthMetricDefinition]
    ) -> [String] {
        let normalized = dataType.lowercased().replacingOccurrences(of: " ", with: "_")
        let exact = definitions.keys.filter { normalized == $0 || normalized.contains($0) }
        return exact.sorted()
    }

    private static func stableFailureIdentifier(_ failure: ExportPartialFailure) throws -> String {
        "failure:\(try shortHash("\(CanonicalRFC3339UTC.string(from: failure.date))|\(failure.dataType)|\(failure.dateRangeDescription)|\(failure.errorDescription)"))"
    }

    private static func providerIdentity(record: ExternalDailyRecord, payload: ExternalProviderPayload) throws -> String {
        let material = ProviderIdentityMaterial(
            name: payload.name,
            endpoint: safeProviderEndpoint(payload.endpoint),
            statusCode: payload.statusCode,
            data: payload.data.map(providerJSON),
            error: payload.error
        )
        let digest = HealthMdQueryCanonicalSerializer.sha256(
            data: try HealthMdQueryCanonicalSerializer.data(for: material)
        )
        return "provider:\(record.provider.rawValue):\(record.date):\(String(digest.prefix(20)))"
    }

    private static func safeProviderEndpoint(_ value: String) -> String {
        guard let url = URL(string: value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return value
        }
        let sensitive = Set(["accesstoken", "clientsecret", "refreshtoken", "code", "nexttoken"])
        components.queryItems = components.queryItems?.map { item in
            let name = item.name.lowercased().filter(\.isLetter)
            return URLQueryItem(name: item.name, value: sensitive.contains(name) ? "[redacted]" : item.value)
        }
        return components.url?.absoluteString ?? value
    }

    private static func shortHash(_ value: String) throws -> String {
        String(HealthMdQueryCanonicalSerializer.sha256(data: Data(value.utf8)).prefix(20))
    }

    private static func providerRecordOrder(_ lhs: ExternalDailyRecord, _ rhs: ExternalDailyRecord) -> Bool {
        if lhs.provider.rawValue != rhs.provider.rawValue { return lhs.provider.rawValue < rhs.provider.rawValue }
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.fetchedAt < rhs.fetchedAt
    }

    private static func providerPayloadOrder(_ lhs: ExternalProviderPayload, _ rhs: ExternalProviderPayload) -> Bool {
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.endpoint != rhs.endpoint { return lhs.endpoint < rhs.endpoint }
        if lhs.statusCode != rhs.statusCode { return lhs.statusCode < rhs.statusCode }
        return lhs.fetchedAt < rhs.fetchedAt
    }

    private struct ProviderIdentityMaterial: Codable {
        let name: String
        let endpoint: String
        let statusCode: Int
        let data: HealthMdJSONValue?
        let error: String?
    }

    private struct EvidenceDraft: Codable, Equatable {
        var id: String = ""
        let locator: HealthMdEvidenceLocator
        let sourceID: String
        let providerID: String?
        let value: HealthMdQueryValue?
        let note: String?
        let metricIDs: [String]

        func stableID() throws -> String {
            let material = EvidenceIdentity(locator: locator)
            return "ev:\(HealthMdQueryCanonicalSerializer.sha256(data: try HealthMdQueryCanonicalSerializer.data(for: material)))"
        }

        func withID(_ id: String) -> EvidenceDraft {
            EvidenceDraft(
                id: id,
                locator: locator,
                sourceID: sourceID,
                providerID: providerID,
                value: value,
                note: note,
                metricIDs: metricIDs
            )
        }
    }

    private struct EvidenceIdentity: Codable {
        let locator: HealthMdEvidenceLocator
    }

    private struct MetricDraft: Codable {
        let observationID: String
        let metricID: String
        let displayName: String
        let value: HealthMdQueryValue?
        let status: HealthMdAvailabilityStatus
        let dailyAggregation: HealthMdDailyAggregation?
        let evidenceIDs: [String]
        let limitations: [HealthMdLimitation]
    }

    private struct WorkoutDraft: Codable {
        let workoutID: String
        let activity: String
        let start: Date
        let end: Date
        let details: [String: HealthMdQueryValue]
        let evidenceIDs: [String]
    }

    private struct DigestMaterial: Codable {
        let sourceSchema: String
        let sourceSchemaVersion: Int
        let ownerDate: String
        let intervalStart: Date
        let intervalEnd: Date
        let calendarTimeZone: String
        let captureStatus: String
        let metrics: [MetricDraft]
        let workouts: [WorkoutDraft]
        let sleepSessions: [HealthMdContextSleepSession]
        let evidence: [EvidenceDraft]
    }
}
