import CryptoKit
import Foundation
@testable import HealthMd

/// Builds committed reference artifacts exclusively from production models and serializers.
@MainActor
enum GeneratedExportDocumentation {
    static let relativeGeneratedDirectory = "docs/reference/generated/core"

    static func files() throws -> [String: Data] {
        let customization = FormatCustomization()
        customization.unitPreference = .metric

        let summary = DocumentationExportFixtures.exhaustiveSummaryDay
        let lossless = DocumentationExportFixtures.exhaustiveLosslessDay
        let archive = DocumentationExportFixtures.canonicalArchive
        let summaryJSON = try summary.toJSONThrowing(customization: customization)
        let losslessJSON = try lossless.toJSONThrowing(customization: customization)
        let archiveJSON = try HealthKitRecordArchiveSerializer.string(for: archive)
        let summaryCSV = try summary.toCSVThrowing(customization: customization)
        let losslessCSV = try lossless.toCSVThrowing(customization: customization)
        let dictionaryEntries = HealthMetricDataDictionary.entries(using: customization)

        var generated: [String: Data] = [:]
        generated["summary-day.json"] = text(summaryJSON)
        generated["summary-day.csv"] = text(summaryCSV)
        generated["summary-day.md"] = text(summary.toMarkdown(customization: customization))
        generated["summary-day-bases.md"] = text(summary.toObsidianBases(customization: customization))
        generated["lossless-day.json"] = text(losslessJSON)
        generated["lossless-day.csv"] = text(losslessCSV)
        generated["lossless-day.md"] = text(lossless.toMarkdown(customization: customization))
        generated["lossless-day-bases.md"] = text(lossless.toObsidianBases(customization: customization))
        generated["canonical-archive.json"] = text(archiveJSON)
        generated["data-dictionary.json"] = try encodedJSON(dictionaryEntries)
        generated["metric-catalog.md"] = text(metricCatalog(
            metrics: HealthMetrics.all,
            dictionaryEntries: dictionaryEntries
        ))
        generated["metric-examples.md"] = text(try metricExamples(
            metrics: HealthMetrics.all,
            dictionaryEntries: dictionaryEntries,
            summary: summary,
            customization: customization
        ))
        generated["daily-json-fields.md"] = text(try pathReference(
            title: "Daily JSON fields",
            introduction: "Complete summary and lossless daily exports are traversed recursively.",
            sections: [
                ("Summary day", try jsonObject(summaryJSON)),
                ("Lossless day", try jsonObject(losslessJSON)),
            ]
        ))
        let recordObjects = try archive.records.map {
            try JSONSerialization.jsonObject(with: HealthKitRecordArchiveSerializer.recordData(for: $0))
        }
        let externalObjects = try archive.externalRecords.map {
            try JSONSerialization.jsonObject(with: HealthKitRecordArchiveSerializer.externalRecordData(for: $0))
        }
        generated["canonical-json-fields.md"] = text(try pathReference(
            title: "Canonical JSON fields",
            introduction: "The archive and every heterogeneous canonical object are traversed recursively.",
            sections: [
                ("Canonical archive", try jsonObject(archiveJSON)),
                ("Canonical record union", recordObjects),
                ("Canonical external-record union", externalObjects),
            ]
        ))
        generated["specialized-records.md"] = text(try specializedRecords(archive: archive))
        generated["csv-row-contracts.md"] = text(csvRowContracts(
            summaryCSV: summaryCSV,
            losslessCSV: losslessCSV
        ))

        for name in generated.keys where name.hasSuffix(".json") || name.hasSuffix(".csv") || name.hasSuffix(".md") {
            let value = String(decoding: generated[name] ?? Data(), as: UTF8.self)
            if name.hasPrefix("summary-day") || name.hasPrefix("lossless-day") || name == "canonical-archive.json" {
                precondition(!value.contains("...") && !value.contains("…"), "Complete example contains an ellipsis: \(name)")
            }
        }

        generated["manifest.json"] = try manifestJSON(for: generated)
        return generated
    }

    static func write(to directory: URL) throws {
        let normalizedPath = directory.standardizedFileURL.path
        guard !normalizedPath.contains("HealthMdTests/Fixtures/Export"),
              !normalizedPath.contains("export_schema_signature") else {
            throw GeneratedExportDocumentationError.refusedSchemaFixturePath(normalizedPath)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in try files() {
            let url = directory.appendingPathComponent(name)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }
    }

    static var committedDirectory: URL {
        repositoryRoot.appendingPathComponent(relativeGeneratedDirectory, isDirectory: true)
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Documentation source file
            .deletingLastPathComponent() // Documentation
            .deletingLastPathComponent() // HealthMdTests
    }

    private static func text(_ value: String) -> Data {
        Data((value.hasSuffix("\n") ? value : value + "\n").utf8)
    }

    private static func encodedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return text(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    private static func metricCatalog(
        metrics: [HealthMetricDefinition],
        dictionaryEntries: [HealthMetricDataDictionaryEntry]
    ) -> String {
        let dictionaryByMetric = Dictionary(grouping: dictionaryEntries, by: \.metricId)
        var lines = [
            "# Health metric catalog",
            "",
            "Generated from `HealthMetrics.all`, `HealthMetricExportMapping`, and `HealthMetricDataDictionary.entries`.",
            "",
            "| Metric ID | Name | Category | Source unit | Type | HealthKit aggregation | Archive only | Default | Availability | HealthKit identifier | Exported keys and rules |",
            "|---|---|---|---|---|---|---:|---:|---|---|---|",
        ]

        for metric in metrics {
            let mappedKeys = HealthMetricExportMapping.frontmatterKeys(for: metric.id)
            let entries = dictionaryByMetric[metric.id] ?? []
            let entryByCanonicalKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.canonicalKey, $0) })
            let mappedDescription = mappedKeys.isEmpty ? "Source archive only" : mappedKeys.map { key in
                guard let entry = entryByCanonicalKey[key] else { return "`\(key)` (no dictionary entry)" }
                return "`\(key)` (\(entry.unit.isEmpty ? "unitless" : entry.unit); daily \(entry.dailyAggregation); roll-up \(entry.rollup.primary))"
            }.joined(separator: "<br>")

            lines.append("| \(cell(metric.id)) | \(cell(metric.name)) | \(cell(metric.category.rawValue)) | \(cell(metric.unit.isEmpty ? "unitless" : metric.unit)) | \(metricType(metric.metricType)) | \(aggregation(metric.aggregation)) | \(metric.isArchiveOnly ? "yes" : "no") | \(metric.isEnabledByDefault ? "yes" : "no") | \(cell(metric.availability.rawValue)) | \(cell(metric.healthKitIdentifier ?? "None")) | \(cell(mappedDescription)) |")
        }

        let diagnostics = dictionaryByMetric["lossless_health_records", default: []]
        lines.append(contentsOf: [
            "",
            "## Diagnostic dictionary entries",
            "",
            "| Canonical key | Display name | Unit | Daily aggregation | Roll-up |",
            "|---|---|---|---|---|",
        ])
        for entry in diagnostics.sorted(by: { $0.canonicalKey < $1.canonicalKey }) {
            lines.append("| `\(cell(entry.canonicalKey))` | \(cell(entry.displayName)) | \(cell(entry.unit.isEmpty ? "unitless" : entry.unit)) | \(cell(entry.dailyAggregation)) | \(cell(entry.rollup.primary)) |")
        }
        return lines.joined(separator: "\n")
    }

    static let expectedSpecializedDomains = [
        "Workout and route", "ECG", "Heartbeat series", "Audiogram", "GAD-7", "PHQ-9",
        "State of Mind", "Medication dose and inventory", "Activity summary", "Characteristic",
        "Clinical and FHIR", "CDA document", "Verifiable clinical record", "Vision prescription",
        "Attachment", "Scheduled WorkoutKit plan",
    ]

    private static func metricExamples(
        metrics: [HealthMetricDefinition],
        dictionaryEntries: [HealthMetricDataDictionaryEntry],
        summary: HealthData,
        customization: FormatCustomization
    ) throws -> String {
        let metricIDs = metrics.map(\.id)
        guard metricIDs.count == Set(metricIDs).count else {
            throw GeneratedExportDocumentationError.duplicateMetricIDs
        }
        let flatValues = summary.exportSnapshot(customization: customization).frontmatterMetrics
        let dictionaryByKey = Dictionary(uniqueKeysWithValues: dictionaryEntries.map { ($0.canonicalKey, $0) })
        var emittedIDs = Set<String>()
        var lines = [
            "# Metric examples",
            "",
            "Exactly one entry is emitted for every definition in `HealthMetrics.all`.",
        ]

        for metric in metrics {
            guard emittedIDs.insert(metric.id).inserted else { throw GeneratedExportDocumentationError.duplicateMetricIDs }
            let mappedKeys = HealthMetricExportMapping.frontmatterKeys(for: metric.id)
            lines.append(contentsOf: [
                "",
                "## \(metric.id)",
                "",
                "- Name: \(metric.name)",
                "- Category: \(metric.category.rawValue)",
                "- HealthKit identifier: `\(metric.healthKitIdentifier ?? "None")`",
            ])

            if mappedKeys.isEmpty {
                guard metric.isArchiveOnly,
                      HealthMetricExportMapping.reviewedArchiveOnlyMetricIDs.contains(metric.id) else {
                    throw GeneratedExportDocumentationError.unreviewedArchiveOnlyMetric(metric.id)
                }
                let plan = HealthKitRecordCatalog.attributedSelectionPlan(enabledMetricIDs: [metric.id])
                guard !plan.isEmpty else { throw GeneratedExportDocumentationError.missingCatalogCoverage(metric.id) }
                lines.append(contentsOf: [
                    "- Export mode: `archive-only`",
                    "",
                    "| Reviewed object type | Canonical record kind | Attribution |",
                    "|---|---|---|",
                ])
                for item in plan {
                    let attribution = item.directMetricIDs.contains(metric.id) ? "direct" : "relationship dependency"
                    lines.append("| `\(cell(item.objectTypeIdentifier))` | `\(recordKindName(item.recordKind))` | \(attribution) |")
                }
            } else {
                lines.append(contentsOf: [
                    "- Export mode: `summary`",
                    "",
                    "```csv",
                    "key,value,unit,daily_aggregation",
                ])
                for key in mappedKeys {
                    guard let entry = dictionaryByKey[key] else {
                        throw GeneratedExportDocumentationError.missingDictionaryEntry(metricID: metric.id, key: key)
                    }
                    guard let value = flatValues[key] else {
                        throw GeneratedExportDocumentationError.missingSyntheticSummaryValue(metricID: metric.id, key: key)
                    }
                    let row = [key, value, entry.unit, entry.dailyAggregation]
                        .map(CSVFieldEscaper.escape)
                        .joined(separator: ",")
                    lines.append(row)
                }
                lines.append("```")
            }
        }

        guard emittedIDs == Set(HealthMetrics.all.map(\.id)), emittedIDs.count == HealthMetrics.all.count else {
            throw GeneratedExportDocumentationError.metricCoverageMismatch
        }
        return lines.joined(separator: "\n")
    }

    private static func specializedRecords(archive: HealthKitRecordArchive) throws -> String {
        func record(_ identifier: String) throws -> String {
            guard let value = archive.records.first(where: { $0.objectTypeIdentifier == identifier }) else {
                throw GeneratedExportDocumentationError.missingSpecializedDomain(identifier)
            }
            return try HealthKitRecordArchiveSerializer.recordString(for: value)
        }
        func external(_ identifier: String) throws -> String {
            guard let value = archive.externalRecords.first(where: { $0.externalIdentifier == identifier }) else {
                throw GeneratedExportDocumentationError.missingSpecializedDomain(identifier)
            }
            return try HealthKitRecordArchiveSerializer.externalRecordString(for: value)
        }
        func inventory(_ identifier: String) throws -> String {
            guard let value = archive.medicationInventoryRecords.first(where: { $0.externalIdentifier == identifier }) else {
                throw GeneratedExportDocumentationError.missingSpecializedDomain(identifier)
            }
            return try HealthKitRecordArchiveSerializer.medicationInventoryRecordString(for: value)
        }

        let domains: [(String, [String])] = [
            ("Workout and route", [try record(HealthKitRecordCatalog.workoutTypeIdentifier), try record(HealthKitRecordCatalog.workoutRouteTypeIdentifier)]),
            ("ECG", [try record(HealthKitRecordCatalog.electrocardiogramIdentifier)]),
            ("Heartbeat series", [try record(HealthKitRecordCatalog.heartbeatSeriesIdentifier)]),
            ("Audiogram", [try record(HealthKitRecordCatalog.audiogramIdentifier)]),
            ("GAD-7", [try record(HealthKitRecordCatalog.gad7AssessmentIdentifier)]),
            ("PHQ-9", [try record(HealthKitRecordCatalog.phq9AssessmentIdentifier)]),
            ("State of Mind", [try record(HealthKitRecordCatalog.stateOfMindIdentifier)]),
            ("Medication dose and inventory", [try record(HealthKitRecordCatalog.medicationDoseEventIdentifier), try inventory("rxnorm:617314")]),
            ("Activity summary", [try external("activity-summary:2026-03-15")]),
            ("Characteristic", [try external("characteristic:biological-sex")]),
            ("Clinical and FHIR", [try record(HealthKitRecordCatalog.clinicalLabResultIdentifier)]),
            ("CDA document", [try record(HealthKitRecordCatalog.cdaDocumentIdentifier)]),
            ("Verifiable clinical record", [try record(HealthKitRecordCatalog.verifiableClinicalRecordIdentifier)]),
            ("Vision prescription", [try record(HealthKitRecordCatalog.visionPrescriptionIdentifier)]),
            ("Attachment", [try external("attachment:fixture-001")]),
            ("Scheduled WorkoutKit plan", [try external("workoutkit:schedule-001")]),
        ]
        guard domains.map(\.0) == expectedSpecializedDomains else {
            throw GeneratedExportDocumentationError.specializedDomainCoverageMismatch
        }

        var lines = [
            "# Specialized canonical records",
            "",
            "Every object below is serialized by `HealthKitRecordArchiveSerializer` from a deterministic fixture that represents a production adapter domain.",
        ]
        for (domain, serializedObjects) in domains {
            lines.append(contentsOf: ["", "## \(domain)"])
            var parsed: [Any] = []
            for (index, serialized) in serializedObjects.enumerated() {
                parsed.append(try jsonObject(serialized))
                lines.append(contentsOf: [
                    "",
                    "### Canonical object \(index + 1)",
                    "",
                    "```json",
                    serialized,
                    "```",
                ])
            }
            lines.append(contentsOf: [
                "",
                "### Observed structured field paths and types",
                "",
                "| JSON path | Observed type or types |",
                "|---|---|",
            ])
            let relevantPaths = paths(in: parsed).filter {
                $0.path.contains("[\"payload\"]") || $0.path.contains("[\"fields\"]")
            }
            for item in relevantPaths {
                lines.append("| `\(cell(item.path))` | \(cell(item.types.sorted().joined(separator: ", "))) |")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func pathReference(
        title: String,
        introduction: String,
        sections: [(String, Any)]
    ) throws -> String {
        var lines = [
            "# \(title)",
            "",
            introduction,
            "",
            "Arrays are traversed exhaustively and heterogeneous element shapes are unioned at the normalized `[]` path.",
        ]
        for (sectionTitle, object) in sections {
            lines.append(contentsOf: [
                "",
                "## \(sectionTitle)",
                "",
                "| JSON path | Observed type or types |",
                "|---|---|",
            ])
            for item in paths(in: object) {
                lines.append("| `\(cell(item.path))` | \(cell(item.types.sorted().joined(separator: ", "))) |")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func csvRowContracts(summaryCSV: String, losslessCSV: String) -> String {
        let sources = [("Summary", summaryCSV), ("Lossless", losslessCSV)]
        var counts: [CSVContract: Int] = [:]
        var header: [String] = []
        for (source, csv) in sources {
            let rows = parseRFC4180(csv)
            if header.isEmpty { header = rows.first ?? [] }
            for row in rows.dropFirst() where !row.allSatisfy(\.isEmpty) {
                let contract = CSVContract(
                    source: source,
                    category: row.indices.contains(1) ? row[1] : "",
                    metric: row.indices.contains(2) ? row[2] : "",
                    fieldCount: row.count,
                    unit: row.indices.contains(4) ? row[4] : "",
                    timestampField: row.count >= 6,
                    populatedTimestamp: row.indices.contains(5) && !row[5].isEmpty
                )
                counts[contract, default: 0] += 1
            }
        }

        var lines = [
            "# CSV row contracts",
            "",
            "The production header has \(header.count) fields: `\(header.joined(separator: ","))`.",
            "",
            "Summary rows emitted by legacy direct interpolation intentionally retain five fields. Canonical, diagnostic, and provenance-aware rows emitted through the shared row writer have six fields. Consumers must accept both forms.",
            "",
            "| Example | Category | Metric | Fields | Unit | Timestamp field | Populated timestamp | Rows |",
            "|---|---|---|---:|---|---:|---:|---:|",
        ]
        for (contract, count) in counts.sorted(by: { lhs, rhs in
            let left = lhs.key
            let right = rhs.key
            return (left.source, left.category, left.metric, left.fieldCount, left.unit, left.populatedTimestamp.description) <
                (right.source, right.category, right.metric, right.fieldCount, right.unit, right.populatedTimestamp.description)
        }) {
            lines.append("| \(contract.source) | \(cell(contract.category)) | \(cell(contract.metric)) | \(contract.fieldCount) | \(cell(contract.unit.isEmpty ? "empty" : contract.unit)) | \(contract.timestampField ? "yes" : "no") | \(contract.populatedTimestamp ? "yes" : "no") | \(count) |")
        }
        return lines.joined(separator: "\n")
    }

    private static func manifestJSON(for files: [String: Data]) throws -> Data {
        let entries: [[String: Any]] = files.keys.sorted().map { name in
            let data = files[name] ?? Data()
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            return ["path": name, "bytes": data.count, "sha256": digest]
        }
        let object: [String: Any] = [
            "algorithm": "SHA-256",
            "files": entries,
            "schema": HealthMdExportSchema.identifier,
            "schema_version": HealthMdExportSchema.version,
        ]
        return text(String(decoding: try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), as: UTF8.self))
    }

    private static func paths(in object: Any) -> [JSONPathTypes] {
        var observations: [String: Set<String>] = [:]
        collectPaths(object, path: "$", observations: &observations)
        return observations.map { JSONPathTypes(path: $0.key, types: $0.value) }
            .sorted { $0.path < $1.path }
    }

    private static func collectPaths(
        _ value: Any,
        path: String,
        observations: inout [String: Set<String>]
    ) {
        if value is NSNull {
            observations[path, default: []].insert("null")
        } else if let dictionary = value as? [String: Any] {
            observations[path, default: []].insert("object")
            for key in dictionary.keys.sorted() {
                collectPaths(dictionary[key] as Any, path: "\(path)[\(quotedJSONKey(key))]", observations: &observations)
            }
        } else if let array = value as? [Any] {
            observations[path, default: []].insert("array")
            if array.isEmpty {
                observations["\(path)[]", default: []].insert("empty")
            } else {
                for element in array {
                    collectPaths(element, path: "\(path)[]", observations: &observations)
                }
            }
        } else if let number = value as? NSNumber {
            observations[path, default: []].insert(
                CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
            )
        } else if value is String {
            observations[path, default: []].insert("string")
        } else {
            observations[path, default: []].insert("unknown")
        }
    }

    private static func quotedJSONKey(_ key: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [key])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\(key)\"]"
        return String(array.dropFirst().dropLast())
    }

    private static func jsonObject(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    private static func parseRFC4180(_ csv: String) -> [[String]] {
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
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !quoted {
                row.append(field)
                field = ""
                if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                row = []
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func recordKindName(_ kind: HealthKitRecordKind) -> String {
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

    private static func metricType(_ value: HealthMetricDefinition.MetricType) -> String {
        switch value {
        case .quantity: return "quantity"
        case .category: return "category"
        case .workout: return "workout"
        }
    }

    private static func aggregation(_ value: HealthMetricDefinition.AggregationType) -> String {
        switch value {
        case .cumulative: return "cumulative"
        case .discreteAvg: return "discreteAvg"
        case .discreteMin: return "discreteMin"
        case .discreteMax: return "discreteMax"
        case .mostRecent: return "mostRecent"
        case .duration: return "duration"
        case .count: return "count"
        }
    }

    private static func cell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}

private struct JSONPathTypes {
    let path: String
    let types: Set<String>
}

private struct CSVContract: Hashable {
    let source: String
    let category: String
    let metric: String
    let fieldCount: Int
    let unit: String
    let timestampField: Bool
    let populatedTimestamp: Bool
}

private enum GeneratedExportDocumentationError: Error, CustomStringConvertible {
    case duplicateMetricIDs
    case metricCoverageMismatch
    case missingCatalogCoverage(String)
    case missingDictionaryEntry(metricID: String, key: String)
    case missingSpecializedDomain(String)
    case missingSyntheticSummaryValue(metricID: String, key: String)
    case refusedSchemaFixturePath(String)
    case specializedDomainCoverageMismatch
    case unreviewedArchiveOnlyMetric(String)

    var description: String {
        switch self {
        case .duplicateMetricIDs:
            return "HealthMetrics.all contains duplicate metric IDs"
        case .metricCoverageMismatch:
            return "Metric example IDs do not exactly match HealthMetrics.all"
        case .missingCatalogCoverage(let metricID):
            return "Missing production record catalog coverage for \(metricID)"
        case .missingDictionaryEntry(let metricID, let key):
            return "Missing data dictionary entry for \(metricID) key \(key)"
        case .missingSpecializedDomain(let identifier):
            return "Missing specialized fixture object \(identifier)"
        case .missingSyntheticSummaryValue(let metricID, let key):
            return "Missing synthetic summary value for \(metricID) key \(key)"
        case .refusedSchemaFixturePath(let path):
            return "Refusing to generate documentation into schema-signature fixture path: \(path)"
        case .specializedDomainCoverageMismatch:
            return "Specialized domain fixture set does not match the reviewed expected set"
        case .unreviewedArchiveOnlyMetric(let metricID):
            return "Metric without summary keys is not reviewed archive-only: \(metricID)"
        }
    }
}
