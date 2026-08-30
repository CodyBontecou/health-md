import Foundation
import HealthMdCoreRust

/// Builds the internal M5 render boundary from one completed M4 result and frozen presentation facts.
/// It never queries HealthKit, opens a destination, or performs a write.
enum HealthMdRenderInputAdapter {
    enum AdapterError: Error, Equatable {
        case invalidSemanticResult
        case invalidRegistry
        case invalidPresentation
        case limitExceeded
        case serializationFailed
    }

    struct Options: Sendable, Equatable {
        var requestID: String
        var formats: [String]
        var unitSystem: String = "metric"
        var includeMetadata: Bool = true
        var groupByCategory: Bool = true
        var includePlatformExtensions: Bool = false
        var rawCaptureStatus: String = "not_requested"
        var writeMode: String = "overwrite"
        var useEmoji: Bool = true
        var sectionHeaderLevel: Int = 2
        var bullet: String = "-"
        var includeSummary: Bool = false
        var customTemplate: String?
        var includeDate: Bool = true
        var dateKey: String = "date"
        var includeType: Bool = true
        var typeKey: String = "type"
        var typeValue: String = "health-data"
        var customFrontmatter: [String: String] = [:]
        var placeholderFrontmatter: [String] = []
        var disabledFrontmatterKeys: [String] = []
        var baseDirectory: String = "Health"
        var filenameTemplate: String = "{date}"
        var folderTemplate: String = ""
        var markdownFolder: String = ""
        var basesFolder: String = ""
        var jsonFolder: String = ""
        var csvFolder: String = ""
        var rollupDirectory: String = "Rollups"
        var basesSuffix: String = "-bases"
        /// Explicit ISO-8601 generation time required when the semantic result contains roll-ups.
        var rollupGeneratedAt: String?
        var api: APIOptions?
    }

    struct APIFailureOptions: Sendable, Equatable {
        var ownerDate: String
        var timestamp: String
        var reason: String
        var errorDetails: String?
    }

    struct APIExternalRecordOptions: Sendable, Equatable {
        var ownerDate: String
        var json: Data
    }

    struct APIOptions: Sendable, Equatable {
        var envelopeVersion: Int
        var exportedAt: String
        var source: String
        var dateRangeStart: String
        var dateRangeEnd: String
        var failedDateDetails: [APIFailureOptions] = []
        var externalRecordSchema: String?
        var externalRecordSchemaVersion: Int?
        var externalRecords: [APIExternalRecordOptions] = []
        var maxDaysPerBatch: Int = 7
        var maxEncodedBytes: UInt64 = 8 * 1024 * 1024
    }

    struct EncodedInput: Sendable, Equatable {
        let configuration: Data
        let batches: [Data]
    }

    private static let maxBatchBytes = 2 * 1024 * 1024
    private static let maxFactsPerBatch = 4_096
    private static let maxSessionBytes = 32 * 1024 * 1024

    static func encode(
        semanticResult: Data,
        registry: CoreMetricRegistrySnapshot,
        calendarTimeZoneIdentifier: String,
        options: Options,
        presentationByOwnerDate: [String: HealthData] = [:],
        allowNativeProfileDocuments: Bool = true,
        presentationCustomization: FormatCustomization = FormatCustomization(),
        extensionPayloadsByOwnerDate: [String: [[String: Any]]] = [:],
        individualEntriesByOwnerDate: [String: [[String: Any]]] = [:],
        dailyNotesByOwnerDate: [String: [String: Any]] = [:]
    ) throws -> EncodedInput {
        guard let root = try JSONSerialization.jsonObject(with: semanticResult) as? [String: Any],
              root["schema"] as? String == "healthmd.semantic_result",
              root["state"] as? String == "completed",
              root["registry_sha256"] as? String == registry.registrySha256,
              let semanticProfileRevision = root["profile_revision"] as? Int,
              semanticProfileRevision == 1 || semanticProfileRevision == 2,
              let sessionID = root["session_id"] as? String,
              let profile = root["profile"] as? String,
              profile == registry.profileId,
              let days = root["days"] as? [[String: Any]],
              let semanticRollups = root["rollups"] as? [[String: Any]],
              TimeZone(identifier: calendarTimeZoneIdentifier) != nil
        else { throw AdapterError.invalidSemanticResult }
        guard allowNativeProfileDocuments || presentationByOwnerDate.isEmpty else {
            throw AdapterError.invalidPresentation
        }
        // Typed provider sections are deliberately not represented by generic
        // render extensions. Provider-bearing v8 days stay native-authoritative.
        guard presentationByOwnerDate.values.allSatisfy({ $0.providers?.isEmpty != false }) else {
            throw AdapterError.invalidPresentation
        }

        var effectiveOptions = options
        if !presentationByOwnerDate.isEmpty {
            effectiveOptions.includeDate = presentationCustomization.frontmatterConfig.includeDate
            effectiveOptions.dateKey = presentationCustomization.frontmatterConfig.customDateKey
            effectiveOptions.includeType = presentationCustomization.frontmatterConfig.includeType
            effectiveOptions.typeKey = presentationCustomization.frontmatterConfig.customTypeKey
            effectiveOptions.typeValue = presentationCustomization.frontmatterConfig.customTypeValue
            effectiveOptions.customFrontmatter = presentationCustomization.frontmatterConfig.customFields
            effectiveOptions.placeholderFrontmatter = presentationCustomization.frontmatterConfig.placeholderFields
            effectiveOptions.disabledFrontmatterKeys = registry.outputs.compactMap { output in
                presentationCustomization.frontmatterConfig.outputKey(for: output.key) == nil ? output.key : nil
            }
            effectiveOptions.useEmoji = presentationCustomization.markdownTemplate.useEmoji
            effectiveOptions.sectionHeaderLevel = presentationCustomization.markdownTemplate.sectionHeaderLevel
            effectiveOptions.bullet = presentationCustomization.markdownTemplate.bulletStyle.rawValue
            effectiveOptions.includeSummary = presentationCustomization.markdownTemplate.includeSummary
            effectiveOptions.customTemplate = presentationCustomization.markdownTemplate.style == .custom
                ? presentationCustomization.markdownTemplate.customTemplate
                : nil
        }
        let configuration = try canonicalJSON(configurationObject(
            sessionID: sessionID,
            profile: profile,
            registry: registry,
            semanticProfileRevision: semanticProfileRevision,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
            options: effectiveOptions,
            rollupOutputKeys: Set(semanticRollups.flatMap { rollup in
                (rollup["values"] as? [[String: Any]] ?? []).compactMap { $0["output_key"] as? String }
            }),
            presentationCustomization: presentationCustomization
        ))
        let renderDays = try days.map { day in
            let ownerDate = day["owner_date"] as? String ?? ""
            return try renderDay(
                day,
                registry: registry,
                presentationData: allowNativeProfileDocuments
                    ? presentationByOwnerDate[ownerDate]
                    : nil,
                presentationCustomization: presentationCustomization,
                options: effectiveOptions,
                extensionPayloads: extensionPayloadsByOwnerDate[day["owner_date"] as? String ?? ""] ?? [],
                individualEntries: individualEntriesByOwnerDate[day["owner_date"] as? String ?? ""] ?? [],
                dailyNote: dailyNotesByOwnerDate[day["owner_date"] as? String ?? ""]
            )
        }
        let batches = try boundedBatches(renderDays, sessionID: sessionID)
        return EncodedInput(configuration: configuration, batches: batches)
    }

    private static func configurationObject(
        sessionID: String,
        profile: String,
        registry: CoreMetricRegistrySnapshot,
        semanticProfileRevision: Int,
        calendarTimeZoneIdentifier: String,
        options: Options,
        rollupOutputKeys: Set<String>,
        presentationCustomization: FormatCustomization
    ) throws -> [String: Any] {
        let api: Any
        if let value = options.api {
            let externalRecords = try value.externalRecords.map { record -> Any in
                [
                    "owner_date": record.ownerDate,
                    "value": try JSONSerialization.jsonObject(with: record.json),
                ]
            }
            api = [
                "enabled": true,
                "envelope_version": value.envelopeVersion,
                "exported_at": value.exportedAt,
                "source": value.source,
                "date_range_start": value.dateRangeStart,
                "date_range_end": value.dateRangeEnd,
                "failed_date_details": value.failedDateDetails.map { failure in
                    [
                        "owner_date": failure.ownerDate,
                        "timestamp": failure.timestamp,
                        "reason": failure.reason,
                        "error_details": (failure.errorDetails as Any?) ?? NSNull(),
                    ]
                },
                "external_record_schema": (value.externalRecordSchema as Any?) ?? NSNull(),
                "external_record_schema_version": (value.externalRecordSchemaVersion as Any?) ?? NSNull(),
                "external_records": externalRecords,
                "max_days_per_batch": value.maxDaysPerBatch,
                "max_encoded_bytes": value.maxEncodedBytes,
            ]
        } else {
            api = NSNull()
        }
        let rollups: Any
        if rollupOutputKeys.isEmpty {
            rollups = NSNull()
        } else {
            guard let generatedAt = options.rollupGeneratedAt else {
                throw AdapterError.invalidPresentation
            }
            let entriesByCanonicalKey = Dictionary(
                uniqueKeysWithValues: HealthMetricDataDictionary.entries(using: presentationCustomization)
                    .map { ($0.canonicalKey, $0) }
            )
            var metrics: [String: Any] = [:]
            for outputKey in rollupOutputKeys.sorted() {
                guard let entry = entriesByCanonicalKey[outputKey] else {
                    throw AdapterError.invalidRegistry
                }
                metrics[outputKey] = [
                    "key": entry.key,
                    "canonical_key": entry.canonicalKey,
                    "display_name": entry.displayName,
                    "category": entry.category,
                    "unit": entry.unit,
                    "notes": (entry.rollup.notes as Any?) ?? NSNull(),
                    "statistic_order": entry.rollup.statistics,
                ]
            }
            rollups = ["generated_at": generatedAt, "metrics": metrics]
        }
        return [
            "schema": "healthmd.render_session_config",
            "render_input_version": 1,
            "artifact_plan_version": 1,
            "canonical_model_version": 1,
            "registry_version": Int(registry.registryVersion),
            "registry_sha256": registry.registrySha256,
            "profile_revision": semanticProfileRevision,
            "render_profile_revision": 2,
            "request_id": options.requestID,
            "session_id": sessionID,
            "profile": profile,
            "calendar_time_zone": calendarTimeZoneIdentifier,
            "locale": "en-US",
            "formats": options.formats,
            "unit_system": options.unitSystem,
            "include_metadata": options.includeMetadata,
            "group_by_category": options.groupByCategory,
            "include_platform_extensions": options.includePlatformExtensions,
            "raw_capture_status": options.rawCaptureStatus,
            "write_mode": options.writeMode,
            "markdown": [
                "use_emoji": options.useEmoji,
                "section_header_level": options.sectionHeaderLevel,
                "bullet": options.bullet,
                "include_summary": options.includeSummary,
                "custom_template": options.customTemplate ?? NSNull(),
            ],
            "frontmatter": [
                "include_date": options.includeDate,
                "date_key": options.dateKey,
                "include_type": options.includeType,
                "type_key": options.typeKey,
                "type_value": options.typeValue,
            ],
            "custom_frontmatter": options.customFrontmatter,
            "placeholder_frontmatter": options.placeholderFrontmatter.sorted(),
            "disabled_frontmatter_keys": options.disabledFrontmatterKeys.sorted(),
            "paths": [
                "base_directory": options.baseDirectory,
                "filename_template": options.filenameTemplate,
                "folder_template": options.folderTemplate,
                "format_folders": [
                    "markdown": options.markdownFolder,
                    "obsidian_bases": options.basesFolder,
                    "json": options.jsonFolder,
                    "csv": options.csvFolder,
                ],
                "rollup_directory": options.rollupDirectory,
                "bases_suffix": options.basesSuffix,
            ],
            "rollups": rollups,
            "api": api,
        ]
    }

    private static func renderDay(
        _ day: [String: Any],
        registry: CoreMetricRegistrySnapshot,
        presentationData: HealthData?,
        presentationCustomization: FormatCustomization,
        options: Options,
        extensionPayloads: [[String: Any]],
        individualEntries: [[String: Any]],
        dailyNote: [String: Any]?
    ) throws -> [String: Any] {
        guard let ownerDate = day["owner_date"] as? String,
              let values = day["values"] as? [[String: Any]]
        else { throw AdapterError.invalidSemanticResult }
        let outputByKey = Dictionary(uniqueKeysWithValues: registry.outputs.map { ($0.key, $0) })
        let metricBySelection = Dictionary(uniqueKeysWithValues: registry.metrics.map { ($0.selectionId, $0) })
        let selectedOutputKeys = try values.map { value -> String in
            guard let outputKey = value["output_key"] as? String else {
                throw AdapterError.invalidPresentation
            }
            return outputKey
        }
        let presentationSnapshot = presentationData?.exportSnapshot(customization: presentationCustomization)
        let metrics: [[String: Any]] = try values.enumerated().map { ordinal, value in
            guard let outputKey = value["output_key"] as? String,
                  let output = outputByKey[outputKey],
                  let metric = output.selectionIds.compactMap({ metricBySelection[$0] }).first,
                  let semanticValue = value["value"] as? [String: Any]
            else { throw AdapterError.invalidRegistry }
            let publicValue = try publicValue(semanticValue)
            let display = presentationSnapshot?.frontmatterMetrics[outputKey] ?? displayValue(publicValue)
            let frontmatterKey = presentationCustomization.frontmatterConfig.outputKey(for: outputKey) ?? outputKey
            let publicUnit: String
            if let snapshot = presentationSnapshot {
                publicUnit = HealthMetricDataDictionary.unit(
                    for: outputKey,
                    converter: snapshot.converter
                ) ?? ""
            } else {
                publicUnit = output.unit
            }
            return [
                "output_key": outputKey,
                "category_id": categoryIdentifier(metric.categoryId),
                "category_label": metric.categoryId,
                "label": metric.referenceName,
                "frontmatter_key": frontmatterKey,
                "json_path": [categoryIdentifier(metric.categoryId), outputKey],
                "public_value": publicValue,
                "display_value": display,
                "unit": publicUnit,
                "timestamp": NSNull(),
                "ordinal": ordinal,
            ]
        }
        let archiveDiagnostics: Any
        if let snapshot = presentationSnapshot {
            let diagnostics = snapshot.losslessArchiveDiagnostics
            archiveDiagnostics = [
                "capture_status": diagnostics.captureStatus,
                "record_count": diagnostics.recordCount,
                "query_failure_count": diagnostics.queryFailureCount,
                "integrity_warning_count": diagnostics.integrityWarningCount,
                "record_schema": (snapshot.healthKitRecordArchive?.schemaIdentifier as Any?) ?? NSNull(),
                "record_schema_version": (snapshot.healthKitRecordArchive?.recordSchemaVersion as Any?) ?? NSNull(),
            ]
        } else {
            archiveDiagnostics = NSNull()
        }
        var basesFrontmatterBlocks: [[String: Any]] = []
        if let snapshot = presentationSnapshot,
           !snapshot.workouts.isEmpty,
           presentationCustomization.frontmatterConfig.isFieldEnabled("workout_details") {
            let outputKey = presentationCustomization.frontmatterConfig.outputKey(for: "workout_details") ?? "workout_details"
            basesFrontmatterBlocks.append([
                "key": outputKey,
                "lines": snapshot.workoutFrontmatterDetailLines(),
                "ordinal": 0,
            ])
        }
        return [
            "owner_date": ownerDate,
            "title": ownerDate,
            "archive_diagnostics": archiveDiagnostics,
            "bases_frontmatter_fields": [],
            "bases_frontmatter_blocks": basesFrontmatterBlocks,
            "metrics": metrics,
            "extensions": extensionPayloads,
            "individual_entries": individualEntries,
            "daily_note": dailyNote ?? NSNull(),
            "profile_documents": try profileDocuments(
                data: presentationData,
                customization: presentationCustomization,
                options: options,
                semanticOutputKeys: selectedOutputKeys
            ),
        ]
    }

    private static func profileDocuments(
        data: HealthData?,
        customization: FormatCustomization,
        options: Options,
        semanticOutputKeys: [String]
    ) throws -> [String: Any] {
        guard let data else {
            return [
                "semantic_output_keys": [],
                "markdown_body": NSNull(),
                "csv_rows": NSNull(),
                "json_root": NSNull(),
            ]
        }
        let requested = Set(options.formats)
        let markdown: Any
        if requested.contains("markdown") {
            let rendered = data.toMarkdown(
                includeMetadata: options.includeMetadata,
                groupByCategory: options.groupByCategory,
                customization: customization
            )
            let body: String
            if options.includeMetadata, rendered.hasPrefix("---\n") {
                guard let delimiter = rendered.range(of: "\n---\n\n", range: rendered.index(rendered.startIndex, offsetBy: 4)..<rendered.endIndex)
                else { throw AdapterError.invalidPresentation }
                body = String(rendered[delimiter.upperBound...])
            } else {
                body = rendered
            }
            markdown = lineDocument(body)
        } else {
            markdown = NSNull()
        }
        let csvRows: Any
        if requested.contains("csv") {
            let parsed = try parseCSV(data.toCSVThrowing(customization: customization))
            guard parsed.first == ["Date", "Category", "Metric", "Value", "Unit", "Timestamp"]
            else { throw AdapterError.invalidPresentation }
            csvRows = parsed.dropFirst().map { row in
                ["cells": row] as [String: Any]
            }
        } else {
            csvRows = NSNull()
        }
        let jsonRoot: Any
        if requested.contains("json") || options.api != nil {
            let rendered = try data.toJSONThrowing(customization: customization)
            jsonRoot = try orderedJSON(JSONSerialization.jsonObject(with: Data(rendered.utf8)))
        } else {
            jsonRoot = NSNull()
        }
        return [
            "semantic_output_keys": semanticOutputKeys.sorted(),
            "markdown_body": markdown,
            "csv_rows": csvRows,
            "json_root": jsonRoot,
        ]
    }

    private static func lineDocument(_ value: String) -> [String: Any] {
        let trailing = value.hasSuffix("\n")
        let body = trailing ? String(value.dropLast()) : value
        return [
            "lines": body.isEmpty ? [] : body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
            "trailing_newline": trailing,
        ]
    }

    private static func parseCSV(_ value: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"", quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                cell.append("\"")
                index += 1
            } else if character == "\"" {
                quoted.toggle()
            } else if character == ",", !quoted {
                row.append(cell)
                cell = ""
            } else if character == "\n", !quoted {
                row.append(cell)
                cell = ""
                rows.append(row)
                row = []
            } else if character != "\r" || quoted {
                cell.append(character)
            }
            index += 1
        }
        guard !quoted else { throw AdapterError.invalidPresentation }
        if !cell.isEmpty || !row.isEmpty {
            row.append(cell)
            rows.append(row)
        }
        guard rows.allSatisfy({ $0.count == 5 || $0.count == 6 }) else {
            throw AdapterError.invalidPresentation
        }
        return rows
    }

    private static func orderedJSON(_ value: Any) throws -> [String: Any] {
        if value is NSNull { return ["value_type": "null"] }
        if let value = value as? String {
            return ["value_type": "string", "value": value]
        }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return ["value_type": "boolean", "value": value.boolValue]
            }
            let encoded = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            guard let decimal = String(data: encoded, encoding: .utf8) else {
                throw AdapterError.invalidPresentation
            }
            return ["value_type": "number", "decimal": decimal]
        }
        if let value = value as? [Any] {
            return ["value_type": "array", "items": try value.map { try orderedJSON($0) }]
        }
        if let value = value as? [String: Any] {
            return [
                "value_type": "object",
                "entries": try value.keys.sorted().map { key in
                    ["key": key, "value": try orderedJSON(value[key] as Any)] as [String: Any]
                },
            ]
        }
        throw AdapterError.invalidPresentation
    }

    private static func publicValue(_ value: [String: Any]) throws -> Any {
        guard let type = value["value_type"] as? String else { throw AdapterError.invalidPresentation }
        switch type {
        case "number":
            guard let number = value["number"] as? [String: Any],
                  let representation = number["representation"] as? String
            else { throw AdapterError.invalidPresentation }
            switch representation {
            case "binary64":
                guard let bits = number["bits"] as? String,
                      let raw = UInt64(bits, radix: 16)
                else { throw AdapterError.invalidPresentation }
                let result = Double(bitPattern: raw)
                guard result.isFinite else { throw AdapterError.invalidPresentation }
                return result
            case "signed_integer":
                guard let decimal = number["decimal"] as? String,
                      let result = Int64(decimal)
                else { throw AdapterError.invalidPresentation }
                return NSNumber(value: result)
            case "unsigned_integer":
                guard let decimal = number["decimal"] as? String,
                      let result = UInt64(decimal)
                else { throw AdapterError.invalidPresentation }
                return NSNumber(value: result)
            default: throw AdapterError.invalidPresentation
            }
        case "text":
            guard let text = value["text"] as? String else { throw AdapterError.invalidPresentation }
            return text
        case "boolean":
            guard let boolean = value["boolean"] as? Bool else { throw AdapterError.invalidPresentation }
            return boolean
        case "text_list":
            guard let items = value["items"] as? [String] else { throw AdapterError.invalidPresentation }
            return items
        default: throw AdapterError.invalidPresentation
        }
    }

    private static func displayValue(_ value: Any) -> String {
        if let boolean = value as? Bool { return boolean ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        if let text = value as? String { return text }
        if let list = value as? [String] { return list.joined(separator: ", ") }
        return ""
    }

    private static func boundedBatches(_ days: [[String: Any]], sessionID: String) throws -> [Data] {
        var partitions: [[[String: Any]]] = []
        var current: [[String: Any]] = []
        var totalBytes = 0
        for day in days {
            let facts = (day["metrics"] as? [Any])?.count ?? 0 + ((day["extensions"] as? [Any])?.count ?? 0)
            guard facts <= maxFactsPerBatch else { throw AdapterError.limitExceeded }
            let candidate = current + [day]
            let placeholder = try batchData(days: candidate, sessionID: sessionID, index: partitions.count, final: false)
            if !current.isEmpty && (placeholder.count > maxBatchBytes || candidate.reduce(0, { $0 + (((($1["metrics"] as? [Any])?.count) ?? 0) + ((($1["extensions"] as? [Any])?.count) ?? 0)) }) > maxFactsPerBatch) {
                partitions.append(current)
                current = [day]
            } else {
                current = candidate
            }
            guard try batchData(days: current, sessionID: sessionID, index: partitions.count, final: false).count <= maxBatchBytes else {
                throw AdapterError.limitExceeded
            }
        }
        if !current.isEmpty || days.isEmpty { partitions.append(current) }
        var result: [Data] = []
        for (index, partition) in partitions.enumerated() {
            let data = try batchData(days: partition, sessionID: sessionID, index: index, final: index + 1 == partitions.count)
            totalBytes += data.count
            guard data.count <= maxBatchBytes, totalBytes <= maxSessionBytes else { throw AdapterError.limitExceeded }
            result.append(data)
        }
        return result
    }

    private static func batchData(days: [[String: Any]], sessionID: String, index: Int, final: Bool) throws -> Data {
        guard index <= Int(UInt32.max) else { throw AdapterError.limitExceeded }
        return try canonicalJSON([
            "schema": "healthmd.render_input",
            "render_input_version": 1,
            "session_id": sessionID,
            "batch_index": index,
            "final_batch": final,
            "days": days,
        ])
    }

    private static func canonicalJSON(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw AdapterError.serializationFailed }
        do { return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
        catch { throw AdapterError.serializationFailed }
    }

    private static func categoryIdentifier(_ value: String) -> String {
        switch value {
        case "Body Measurements": return "body"
        case "Reproductive", "Reproductive Health": return "reproductive_health"
        default:
            return value.lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
    }
}
