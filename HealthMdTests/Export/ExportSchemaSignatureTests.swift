//
//  ExportSchemaSignatureTests.swift
//  HealthMdTests
//
//  Guards the public export schema contract. If any exporter shape, metric key,
//  unit, or data-dictionary metadata changes, this test fails until the schema
//  version is intentionally bumped after a production release and the
//  versioned signature fixture is regenerated.
//

import XCTest
import CryptoKit
@testable import HealthMd

private enum ExportSchemaSignatureFixtures {
    static let metricCustomization: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .metric
        return c
    }()

    static let imperialCustomization: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .imperial
        return c
    }()
}

final class ExportSchemaSignatureTests: XCTestCase {
    func testSchemaMetadataConstantsRemainStableForInitialProductionRollout() {
        XCTAssertEqual(HealthMdExportSchema.identifier, "healthmd.health_data")
        XCTAssertEqual(HealthMdExportSchema.version, 2)
        XCTAssertEqual(HealthMdExportSchema.dataDictionaryFilename, "_healthmd_data_dictionary.json")
        XCTAssertEqual(HealthRollupExportSchema.identifier, "healthmd.rollup_summary")
        XCTAssertNotEqual(HealthRollupExportSchema.identifier, HealthMdExportSchema.identifier)
    }

    @MainActor
    func testExportSchemaSignatureMatchesVersionedFixture() throws {
        let current = try ExportSchemaSignatureSnapshot.current()
        let fixtureURL = Self.fixtureURL(for: current.schemaVersion)
        let existing = try Self.readSnapshotIfPresent(at: fixtureURL)
        let environment = ProcessInfo.processInfo.environment
        let shouldUpdate = environment["UPDATE_EXPORT_SCHEMA_SIGNATURE"] == "1"
            || FileManager.default.fileExists(atPath: Self.updateMarkerURL.path)
        let allowUnshippedVersionRewrite = environment["ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE"] == "1"

        if shouldUpdate {
            if let existing,
               existing.schemaVersion == current.schemaVersion,
               existing.fingerprint != current.fingerprint,
               !allowUnshippedVersionRewrite {
                XCTFail("""
                Refusing to update export schema signature for an existing schema version.

                Current schema_version: \(current.schemaVersion)
                Existing fingerprint: \(existing.fingerprint)
                Current fingerprint:  \(current.fingerprint)

                If this schema version has already shipped, bump HealthMdExportSchema.version
                first, then rerun scripts/update-export-schema-signature.sh.

                If this schema version has not shipped yet, rerun with
                ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE=1 and review the fixture diff.
                """)
                return
            }

            try Self.encoder.encode(current).write(to: Self.updateOutputURL, options: .atomic)
            return
        }

        guard let existing else {
            XCTFail("""
            Missing export schema signature fixture:
            \(fixtureURL.path)

            Run scripts/update-export-schema-signature.sh after confirming
            HealthMdExportSchema.version is correct for the current schema.
            """)
            return
        }

        XCTAssertEqual(existing.schema, current.schema)
        XCTAssertEqual(existing.schemaVersion, current.schemaVersion, """
        Export schema signature fixture is for schema_version \(existing.schemaVersion),
        but code declares schema_version \(current.schemaVersion).
        Run scripts/update-export-schema-signature.sh after intentional version changes.
        """)

        XCTAssertEqual(existing.fingerprint, current.fingerprint, """
        Export schema changed but its versioned signature fixture was not updated.

        Schema: \(current.schema)
        schema_version: \(current.schemaVersion)
        Expected fingerprint: \(existing.fingerprint)
        Current fingerprint:  \(current.fingerprint)

        Policy:
        - Bump HealthMdExportSchema.version for intentional schema changes after a production release.
        - Keep the same version only for schemas that have not shipped yet, and review the fixture diff.
        - Then run scripts/update-export-schema-signature.sh.
        - Do not update the fixture to hide accidental export-schema drift.
        """)

        XCTAssertEqual(existing.payload, current.payload)
    }

    private static func fixtureURL(for schemaVersion: Int) -> URL {
        fixturesDirectory.appendingPathComponent("export_schema_signature_v\(schemaVersion).json")
    }

    private static var updateMarkerURL: URL {
        fixturesDirectory.appendingPathComponent(".update-export-schema-signature")
    }

    private static var updateOutputURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("healthmd-export-schema-signature-current.json")
    }

    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Export
            .deletingLastPathComponent() // HealthMdTests
            .appendingPathComponent("Fixtures/Export")
    }

    private static func readSnapshotIfPresent(at url: URL) throws -> ExportSchemaSignatureSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(ExportSchemaSignatureSnapshot.self, from: Data(contentsOf: url))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

private struct ExportSchemaSignatureSnapshot: Codable, Equatable {
    let schema: String
    let schemaVersion: Int
    let fingerprint: String
    let payload: ExportSchemaSignaturePayload

    @MainActor
    static func current() throws -> ExportSchemaSignatureSnapshot {
        let payload = try ExportSchemaSignaturePayload.current()
        let canonicalPayload = try ExportSchemaSignatureTestsEncoder.encode(payload)
        let fingerprint = SHA256.hash(data: canonicalPayload)
            .map { String(format: "%02x", $0) }
            .joined()

        return ExportSchemaSignatureSnapshot(
            schema: HealthMdExportSchema.identifier,
            schemaVersion: HealthMdExportSchema.version,
            fingerprint: fingerprint,
            payload: payload
        )
    }
}

private struct ExportSchemaSignaturePayload: Codable, Equatable {
    let schema: String
    let markdownFrontmatterTopLevelKeys: [String]
    let obsidianBasesFrontmatterTopLevelKeys: [String]
    let jsonShapePaths: [String]
    let csvHeader: [String]
    let csvRowContracts: [CSVRowContract]
    let dataDictionaryMetric: [DataDictionaryEntrySignature]
    let dataDictionaryImperial: [DataDictionaryEntrySignature]

    @MainActor
    static func current() throws -> ExportSchemaSignaturePayload {
        let metric = ExportSchemaSignatureFixtures.metricCustomization
        let imperial = ExportSchemaSignatureFixtures.imperialCustomization

        return ExportSchemaSignaturePayload(
            schema: HealthMdExportSchema.identifier,
            markdownFrontmatterTopLevelKeys: Self.frontmatterTopLevelKeys(
                ExportFixtures.fullDay.toMarkdown(customization: metric)
            ),
            obsidianBasesFrontmatterTopLevelKeys: Self.frontmatterTopLevelKeys(
                ExportFixtures.fullDay.toObsidianBases(customization: metric)
            ),
            jsonShapePaths: try Self.jsonShapePaths(
                ExportFixtures.fullDay.toJSON(customization: metric)
            ),
            csvHeader: Self.csvHeader(ExportFixtures.fullDay.toCSV(customization: metric)),
            csvRowContracts: Self.csvRowContracts(ExportFixtures.fullDay.toCSV(customization: metric)),
            dataDictionaryMetric: Self.dataDictionaryEntries(using: metric),
            dataDictionaryImperial: Self.dataDictionaryEntries(using: imperial)
        )
    }

    private static func frontmatterTopLevelKeys(_ output: String) -> [String] {
        let lines = output.components(separatedBy: "\n")
        guard lines.first == "---" else { return [] }

        var keys: [String] = []
        for line in lines.dropFirst() {
            if line == "---" { break }
            guard !line.hasPrefix(" "), let separator = line.firstIndex(of: ":") else { continue }
            keys.append(String(line[..<separator]))
        }
        return Array(Set(keys)).sorted()
    }

    private static func jsonShapePaths(_ jsonString: String) throws -> [String] {
        let data = Data(jsonString.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return Self.jsonShapePaths(for: object, path: "$", includeSelf: false).sorted()
    }

    private static func jsonShapePaths(for value: Any, path: String, includeSelf: Bool = true) -> [String] {
        var paths: [String] = []

        if value is NSNull {
            if includeSelf { paths.append("\(path):null") }
            return paths
        }

        if let dict = value as? [String: Any] {
            if includeSelf { paths.append("\(path):object") }
            for key in dict.keys.sorted() {
                if let child = dict[key] {
                    paths.append(contentsOf: jsonShapePaths(for: child, path: "\(path).\(key)"))
                }
            }
            return paths
        }

        if let array = value as? [Any] {
            if includeSelf { paths.append("\(path):array") }
            if let first = array.first {
                paths.append(contentsOf: jsonShapePaths(for: first, path: "\(path)[]"))
            } else {
                paths.append("\(path)[]:empty")
            }
            return paths
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                paths.append("\(path):bool")
            } else {
                paths.append("\(path):number")
            }
            return paths
        }

        if value is String {
            paths.append("\(path):string")
            return paths
        }

        paths.append("\(path):unknown")
        return paths
    }

    private static func csvHeader(_ csv: String) -> [String] {
        csv.components(separatedBy: "\n")
            .first?
            .components(separatedBy: ",") ?? []
    }

    private static func csvRowContracts(_ csv: String) -> [CSVRowContract] {
        csv.components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty }
            .map { line in
                let columns = line.components(separatedBy: ",")
                let category = columns.count > 1 ? columns[1] : ""
                let metric = columns.count > 2 ? columns[2] : ""
                let value = columns.count > 3 ? columns[3] : ""
                let unit = columns.count > 4 ? columns[4] : ""
                let timestamp = columns.count > 5 ? columns[5] : ""

                // Capture metadata values that are schema-identifying but omit the
                // schema_version value itself so bumping the integer does not change
                // the fingerprint payload.
                let metadataValue = category == "Metadata" && metric != "schema_version" ? value : nil

                return CSVRowContract(
                    category: category,
                    metric: metric,
                    unit: unit,
                    hasTimestamp: !timestamp.isEmpty,
                    metadataValue: metadataValue
                )
            }
            .sorted()
    }

    @MainActor
    private static func dataDictionaryEntries(using customization: FormatCustomization) -> [DataDictionaryEntrySignature] {
        HealthMetricDataDictionary.entries(using: customization)
            .map(DataDictionaryEntrySignature.init)
            .sorted()
    }
}

private struct CSVRowContract: Codable, Comparable, Equatable {
    let category: String
    let metric: String
    let unit: String
    let hasTimestamp: Bool
    let metadataValue: String?

    static func < (lhs: CSVRowContract, rhs: CSVRowContract) -> Bool {
        if lhs.category != rhs.category { return lhs.category < rhs.category }
        if lhs.metric != rhs.metric { return lhs.metric < rhs.metric }
        if lhs.unit != rhs.unit { return lhs.unit < rhs.unit }
        if lhs.hasTimestamp != rhs.hasTimestamp { return lhs.hasTimestamp.description < rhs.hasTimestamp.description }
        return (lhs.metadataValue ?? "") < (rhs.metadataValue ?? "")
    }
}

private struct DataDictionaryRollupSignature: Codable, Equatable {
    let primary: String
    let statistics: [String]
    let periods: [String]
    let preferredSource: String
    let nullHandling: String
    let weightedBy: String?
    let notes: String?

    init(_ rollup: HealthMetricRollupRule) {
        primary = rollup.primary
        statistics = rollup.statistics
        periods = rollup.periods
        preferredSource = rollup.preferredSource
        nullHandling = rollup.nullHandling
        weightedBy = rollup.weightedBy
        notes = rollup.notes
    }
}

private struct DataDictionaryEntrySignature: Codable, Comparable, Equatable {
    let key: String
    let canonicalKey: String
    let metricId: String
    let displayName: String
    let category: String
    let unit: String
    let healthKitIdentifier: String?
    let aggregation: String
    let dailyAggregation: String
    let healthKitAggregation: String
    let rollup: DataDictionaryRollupSignature
    let metricType: String

    init(_ entry: HealthMetricDataDictionaryEntry) {
        key = entry.key
        canonicalKey = entry.canonicalKey
        metricId = entry.metricId
        displayName = entry.displayName
        category = entry.category
        unit = entry.unit
        healthKitIdentifier = entry.healthKitIdentifier
        aggregation = entry.aggregation
        dailyAggregation = entry.dailyAggregation
        healthKitAggregation = entry.healthKitAggregation
        rollup = DataDictionaryRollupSignature(entry.rollup)
        metricType = entry.metricType
    }

    static func < (lhs: DataDictionaryEntrySignature, rhs: DataDictionaryEntrySignature) -> Bool {
        if lhs.key != rhs.key { return lhs.key < rhs.key }
        if lhs.canonicalKey != rhs.canonicalKey { return lhs.canonicalKey < rhs.canonicalKey }
        return lhs.metricId < rhs.metricId
    }
}

private enum ExportSchemaSignatureTestsEncoder {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
