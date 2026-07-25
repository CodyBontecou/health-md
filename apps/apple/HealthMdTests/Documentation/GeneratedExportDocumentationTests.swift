import XCTest
@testable import HealthMd

@MainActor
final class GeneratedExportDocumentationTests: XCTestCase {
    func testGeneratedExportDocumentationIsCurrent() throws {
        #if os(macOS)
        let environment = ProcessInfo.processInfo.environment
        let markerURL = GeneratedExportDocumentation.repositoryRoot
            .appendingPathComponent("HealthMdTests/Fixtures/Documentation/.generated-export-docs-output")
        let markerPath = try? String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedOutputPath = environment["GENERATED_EXPORT_DOCS_OUTPUT_DIR"] ?? markerPath
        if let outputPath = requestedOutputPath, !outputPath.isEmpty {
            let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
            XCTAssertFalse(outputURL.path.contains("HealthMdTests/Fixtures/Export"))
            XCTAssertFalse(outputURL.path.contains("export_schema_signature"))
            try GeneratedExportDocumentation.write(to: outputURL)
            XCTAssertFalse(try generatedFileNames(at: outputURL).isEmpty)
            return
        }

        let expected = try GeneratedExportDocumentation.files()
        let committedDirectory = GeneratedExportDocumentation.committedDirectory
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: committedDirectory.path),
            "Missing generated documentation. Run scripts/generated-export-docs.sh update."
        )
        let committedNames = try generatedFileNames(at: committedDirectory)
        XCTAssertEqual(
            committedNames,
            Set(expected.keys),
            "Generated export documentation file set drifted. Run scripts/generated-export-docs.sh update and review the result."
        )
        for name in expected.keys.sorted() {
            let committed = try Data(contentsOf: committedDirectory.appendingPathComponent(name))
            XCTAssertEqual(
                committed,
                expected[name],
                "Generated export documentation drifted at \(name). Run scripts/generated-export-docs.sh update and review the result."
            )
        }
        #else
        throw XCTSkip("Generated documentation byte comparison runs on macOS only.")
        #endif
    }

    func testDocumentationFixtureCoversCanonicalDiscriminators() throws {
        let archive = DocumentationExportFixtures.canonicalArchive
        XCTAssertEqual(archive.records.count, 20)
        XCTAssertEqual(archive.externalRecords.count, 4)
        XCTAssertEqual(archive.queryResults.count, 6)
        XCTAssertEqual(archive.medicationInventoryRecords.count, 2)
        XCTAssertEqual(archive.integrityWarnings.count, 2)
        XCTAssertEqual(DocumentationExportFixtures.exhaustiveLosslessDay.partialFailures.count, 2)

        var recordKinds = Set<String>()
        var payloadTypes = Set<String>()
        var metadataTypes = Set<String>()
        for record in archive.records {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: HealthKitRecordArchiveSerializer.recordData(for: record)
                ) as? [String: Any]
            )
            recordKinds.insert(try XCTUnwrap(object["record_kind"] as? String))
            let payload = try XCTUnwrap(object["payload"] as? [String: Any])
            payloadTypes.insert(try XCTUnwrap(payload["type"] as? String))
            collectMetadataTypes(object, into: &metadataTypes)
        }

        XCTAssertEqual(recordKinds, Set(DocumentationExportFixtures.recordKindNames))
        XCTAssertEqual(payloadTypes, Set(DocumentationExportFixtures.payloadCaseNames))
        XCTAssertEqual(metadataTypes, [
            "null", "string", "bool", "signed_integer", "unsigned_integer",
            "floating_point", "date", "data", "url", "quantity", "array",
            "dictionary", "unsupported",
        ])
        XCTAssertEqual(Set(archive.queryResults.map(\.status)), Set(HealthKitQueryResultStatus.allCases))

        let first = try XCTUnwrap(archive.records.first { $0.originalUUID.uuidString.hasSuffix("000000000001") })
        XCTAssertTrue(first.relationships.contains { $0.targetUUID != nil })
        XCTAssertTrue(first.relationships.contains { $0.targetExternalIdentifier != nil })
        XCTAssertNotNil(first.metricAttribution)
        XCTAssertTrue(archive.externalRecords.contains { $0.metricAttribution != nil })
        XCTAssertTrue(archive.externalRecords.contains { $0.metricAttribution == nil })
    }

    func testExamplesUseProductionSerializersAndAreComplete() throws {
        let files = try GeneratedExportDocumentation.files()
        let expectedNames: Set<String> = [
            "summary-day.json", "summary-day.csv", "summary-day.md", "summary-day-bases.md",
            "lossless-day.json", "lossless-day.csv", "lossless-day.md", "lossless-day-bases.md",
            "canonical-archive.json", "daily-json-fields.md", "canonical-json-fields.md",
            "metric-catalog.md", "metric-examples.md", "specialized-records.md",
            "data-dictionary.json", "csv-row-contracts.md", "manifest.json",
        ]
        XCTAssertEqual(Set(files.keys), expectedNames)
        for name in files.keys where name.hasPrefix("summary-day") || name.hasPrefix("lossless-day") || name == "canonical-archive.json" {
            let value = String(decoding: try XCTUnwrap(files[name]), as: UTF8.self)
            XCTAssertFalse(value.contains("..."), name)
            XCTAssertFalse(value.contains("…"), name)
        }

        let summary = DocumentationExportFixtures.exhaustiveSummaryDay
        let lossless = DocumentationExportFixtures.exhaustiveLosslessDay
        XCTAssertEqual(
            files["summary-day.json"],
            normalized(try summary.toJSONThrowing(customization: metricCustomization))
        )
        XCTAssertEqual(
            files["lossless-day.csv"],
            normalized(try lossless.toCSVThrowing(customization: metricCustomization))
        )
        XCTAssertEqual(
            files["canonical-archive.json"],
            normalized(try HealthKitRecordArchiveSerializer.string(for: DocumentationExportFixtures.canonicalArchive))
        )
    }

    func testMetricExamplesExactlyCoverHealthMetricsAll() throws {
        let files = try GeneratedExportDocumentation.files()
        let markdown = String(decoding: try XCTUnwrap(files["metric-examples.md"]), as: UTF8.self)
        let emittedIDs = markdown.components(separatedBy: "\n")
            .filter { $0.hasPrefix("## ") }
            .map { String($0.dropFirst(3)) }
        XCTAssertEqual(emittedIDs.count, HealthMetrics.all.count)
        XCTAssertEqual(Set(emittedIDs), Set(HealthMetrics.all.map(\.id)))
    }

    func testSpecializedRecordsExactlyCoverExpectedDomains() throws {
        let files = try GeneratedExportDocumentation.files()
        let markdown = String(decoding: try XCTUnwrap(files["specialized-records.md"]), as: UTF8.self)
        let domains = markdown.components(separatedBy: "\n")
            .filter { $0.hasPrefix("## ") }
            .map { String($0.dropFirst(3)) }
        XCTAssertEqual(domains, GeneratedExportDocumentation.expectedSpecializedDomains)
        XCTAssertEqual(
            markdown.components(separatedBy: "\n").filter { $0 == "### Observed structured field paths and types" }.count,
            GeneratedExportDocumentation.expectedSpecializedDomains.count
        )
        XCTAssertGreaterThanOrEqual(
            markdown.components(separatedBy: "\n").filter { $0.hasPrefix("### Canonical object ") }.count,
            GeneratedExportDocumentation.expectedSpecializedDomains.count
        )
    }

    private var metricCustomization: FormatCustomization {
        let customization = FormatCustomization()
        customization.unitPreference = .metric
        return customization
    }

    private func normalized(_ value: String) -> Data {
        Data((value.hasSuffix("\n") ? value : value + "\n").utf8)
    }

    private func collectMetadataTypes(_ value: Any, into result: inout Set<String>) {
        if let dictionary = value as? [String: Any] {
            let tags: Set<String> = [
                "null", "string", "bool", "signed_integer", "unsigned_integer",
                "floating_point", "date", "data", "url", "quantity", "array",
                "dictionary", "unsupported",
            ]
            if let type = dictionary["type"] as? String, tags.contains(type) {
                result.insert(type)
            }
            for child in dictionary.values { collectMetadataTypes(child, into: &result) }
        } else if let array = value as? [Any] {
            for child in array { collectMetadataTypes(child, into: &result) }
        }
    }

    private func generatedFileNames(at directory: URL) throws -> Set<String> {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return Set(try contents.compactMap { url in
            try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                ? url.lastPathComponent
                : nil
        })
    }
}
