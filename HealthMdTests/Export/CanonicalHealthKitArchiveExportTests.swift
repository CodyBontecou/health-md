import XCTest
@testable import HealthMd

final class CanonicalHealthKitArchiveExportTests: XCTestCase {
    private static let customization: FormatCustomization = {
        let customization = FormatCustomization()
        customization.unitPreference = .metric
        return customization
    }()

    func testDailyJSONPreservesSummariesAndAddsCanonicalArchive() throws {
        let json = try parseJSON(ExportFixtures.losslessDay.toJSON(customization: Self.customization))

        XCTAssertEqual(json["raw_capture_status"] as? String, "partial")
        let summaryKeys = [
            "sleep", "activity", "heart", "vitals", "body", "nutrition",
            "mindfulness", "mobility", "hearing", "workouts", "medications"
        ]
        for key in summaryKeys {
            XCTAssertNotNil(json[key], "Lossless raw capture must not remove the existing \(key) summary")
        }

        let archive = try XCTUnwrap(json["healthkit_record_archive"] as? [String: Any])
        XCTAssertEqual(archive["schema"] as? String, "healthmd.healthkit_records")
        XCTAssertEqual(archive["schema_version"] as? Int, 1)
        XCTAssertEqual(archive["capture_status"] as? String, "partial")
        XCTAssertNotNil(archive["ownership"] as? [String: Any])
        XCTAssertNotNil(archive["query_manifest"] as? [String: Any])
        XCTAssertNotNil(archive["integrity_warnings"] as? [[String: Any]])
        XCTAssertNotNil(archive["medication_inventory"] as? [[String: Any]])

        let diagnostics = try XCTUnwrap(json["diagnostics"] as? [String: Any])
        let partialFailures = try XCTUnwrap(diagnostics["partial_failures"] as? [[String: Any]])
        XCTAssertEqual(partialFailures.count, 1)
        XCTAssertEqual(partialFailures[0]["data_type"] as? String, "vitals, secondary")
        XCTAssertEqual(partialFailures[0]["date"] as? String, "2026-03-15T00:03:20.125000000Z")
    }

    func testCanonicalRecordsPreserveIdentityMetadataProvenanceRelationshipsAndPayloads() throws {
        let json = try parseJSON(ExportFixtures.losslessDay.toJSON(customization: Self.customization))
        let archive = try XCTUnwrap(json["healthkit_record_archive"] as? [String: Any])
        let records = try XCTUnwrap(archive["records"] as? [[String: Any]])

        XCTAssertEqual(records.count, 7)
        let identifiers = records.compactMap { $0["original_uuid"] as? String }
        XCTAssertEqual(Set(identifiers).count, 7)
        XCTAssertTrue(identifiers.contains("10000000-0000-0000-0000-000000000001"))
        XCTAssertTrue(identifiers.contains("10000000-0000-0000-0000-000000000002"))

        let first = try XCTUnwrap(records.first { ($0["original_uuid"] as? String)?.hasSuffix("0001") == true })
        XCTAssertEqual(first["start_date"] as? String, "2026-03-15T00:00:01.125000000Z")
        XCTAssertEqual(first["end_date"] as? String, "2026-03-15T00:00:02.500000000Z")
        XCTAssertEqual(first["has_undetermined_duration"] as? Bool, true)
        XCTAssertEqual(first["selected_metric_ids"] as? [String], ["heart_rate_avg", "heart_rate_max"])

        let source = try XCTUnwrap(first["source_revision"] as? [String: Any])
        XCTAssertEqual(source["bundle_identifier"] as? String, "com.example.\"health\"")
        XCTAssertEqual(source["product_type"] as? String, "Watch7,5")
        XCTAssertEqual(
            (source["operating_system_version"] as? [String: Any])?["patch_version"] as? Int,
            2
        )
        let device = try XCTUnwrap(first["device"] as? [String: Any])
        XCTAssertEqual(device["local_identifier"] as? String, "local,watch")
        XCTAssertEqual(device["udi_device_identifier"] as? String, "udi-\"watch\"")

        let relationships = try XCTUnwrap(first["relationships"] as? [[String: Any]])
        XCTAssertEqual(relationships.count, 2)
        let relationshipTypes = Set(relationships.compactMap {
            ($0["target"] as? [String: Any])?["type"] as? String
        })
        XCTAssertEqual(relationshipTypes, ["uuid", "external_identifier"])

        let metadata = try XCTUnwrap(first["metadata"] as? [String: Any])
        let metadataTypes = Set(metadata.values.compactMap {
            ($0 as? [String: Any])?["type"] as? String
        })
        XCTAssertEqual(metadataTypes, [
            "null", "string", "bool", "signed_integer", "unsigned_integer", "floating_point",
            "date", "data", "url", "quantity", "array", "dictionary", "unsupported"
        ])
        XCTAssertEqual((metadata["null"] as? [String: Any])?["type"] as? String, "null")
        XCTAssertEqual((metadata["signed"] as? [String: Any])?["type"] as? String, "signed_integer")
        XCTAssertEqual(
            ((metadata["signed"] as? [String: Any])?["value"] as? NSNumber)?.int64Value,
            Int64.min
        )
        XCTAssertEqual((metadata["unsigned"] as? [String: Any])?["type"] as? String, "unsigned_integer")
        XCTAssertEqual(
            ((metadata["unsigned"] as? [String: Any])?["value"] as? NSNumber)?.uint64Value,
            UInt64.max
        )
        let recursive = try XCTUnwrap((metadata["dictionary"] as? [String: Any])?["value"] as? [String: Any])
        XCTAssertEqual(
            (((recursive["nested"] as? [String: Any])?["value"] as? [String: Any])?["flag"] as? [String: Any])?["type"] as? String,
            "bool"
        )
        XCTAssertEqual((metadata["date"] as? [String: Any])?["value"] as? String, first["start_date"] as? String)
        XCTAssertEqual((metadata["unsupported"] as? [String: Any])?["type_name"] as? String, "HKFutureMetadata")

        let payloadTypes = Set(records.compactMap {
            ($0["payload"] as? [String: Any])?["type"] as? String
        })
        XCTAssertEqual(payloadTypes, [
            "quantity", "category", "correlation", "structured",
            "binary_artifact_reference", "unknown"
        ])
        let unknown = try XCTUnwrap(records.first {
            (($0["payload"] as? [String: Any])?["type"] as? String) == "unknown"
        })
        XCTAssertEqual((unknown["payload"] as? [String: Any])?["kind"] as? String, "HKFuturePayload")
        let unknownFields = try XCTUnwrap((unknown["payload"] as? [String: Any])?["fields"] as? [String: Any])
        XCTAssertEqual(
            ((unknownFields["exact"] as? [String: Any])?["value"] as? NSNumber)?.uint64Value,
            UInt64.max
        )

        let binary = try XCTUnwrap(records.first {
            (($0["payload"] as? [String: Any])?["type"] as? String) == "binary_artifact_reference"
        })
        let artifact = try XCTUnwrap((binary["payload"] as? [String: Any])?["artifact"] as? [String: Any])
        XCTAssertEqual((artifact["byte_count"] as? NSNumber)?.uint64Value, UInt64.max)

        let inventory = try XCTUnwrap(archive["medication_inventory"] as? [[String: Any]])
        XCTAssertEqual(inventory.first?["external_identifier"] as? String, "rxnorm:617314")
        let inventoryFields = try XCTUnwrap(inventory.first?["fields"] as? [String: Any])
        XCTAssertEqual(
            ((inventoryFields["maximum_refills"] as? [String: Any])?["value"] as? NSNumber)?.uint64Value,
            UInt64.max
        )
    }

    func testMarkdownAndBasesExposeCompactAccurateLosslessDiagnostics() throws {
        let data = ExportFixtures.losslessDay
        let markdown = data.toMarkdown(customization: Self.customization)
        let bases = data.toObsidianBases(customization: Self.customization)

        for output in [markdown, bases] {
            XCTAssertTrue(output.contains("raw_capture_status: partial"), output)
            XCTAssertTrue(output.contains("raw_record_count: 7"), output)
            XCTAssertTrue(output.contains("raw_query_failure_count: 1"), output)
            XCTAssertTrue(output.contains("raw_integrity_warning_count: 1"), output)
            XCTAssertTrue(output.contains("raw_record_schema: healthmd.healthkit_records"), output)
            XCTAssertTrue(output.contains("raw_record_schema_version: 1"), output)
            XCTAssertTrue(output.contains("raw_record_count: records"), output)
            XCTAssertTrue(output.contains("raw_query_failure_count: queries"), output)
            XCTAssertTrue(output.contains("raw_integrity_warning_count: warnings"), output)
        }

        XCTAssertTrue(markdown.contains("## Lossless Health Records"), markdown)
        XCTAssertTrue(markdown.contains("**Source records:** 7"), markdown)
        XCTAssertTrue(markdown.contains("**Queries:** 0 succeeded · 1 empty · 1 failed · 0 unsupported · 0 skipped"), markdown)
        XCTAssertTrue(markdown.contains("**Medication inventory:** 1"), markdown)
        XCTAssertTrue(markdown.contains("| Query failure | HKQuantityTypeIdentifierHeartRate |"), markdown)
        XCTAssertTrue(markdown.contains("| Integrity warning | fixture_warning |"), markdown)
        XCTAssertTrue(markdown.contains("retry later"), markdown)
        XCTAssertFalse(markdown.contains("healthkit_record_archive"), "Markdown should summarize the archive, not dump it")
        XCTAssertFalse(markdown.contains("canonical_record_json"), "Daily Markdown should remain readable")

        let dictionary = Dictionary(uniqueKeysWithValues: HealthMetricDataDictionary.entries(using: Self.customization).map { ($0.canonicalKey, $0) })
        XCTAssertEqual(dictionary["raw_record_count"]?.unit, "records")
        XCTAssertEqual(dictionary["raw_record_count"]?.rollup.primary, "sum")
        XCTAssertEqual(dictionary["raw_capture_status"]?.rollup.primary, "latest")
    }

    func testCompleteEmptyArchiveRemainsExportableEvidence() {
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-03-15",
                intervalStart: ExportFixtures.referenceDate,
                intervalEnd: ExportFixtures.referenceDate.addingTimeInterval(86_400),
                calendarTimeZoneIdentifier: "UTC"
            ),
            queryManifest: HealthKitQueryManifest(results: [HealthKitQueryResult(
                identifier: "empty",
                objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
                operation: "sample_query",
                metricIDs: ["steps"],
                interval: HealthKitQueryInterval(
                    startDate: ExportFixtures.referenceDate,
                    endDate: ExportFixtures.referenceDate.addingTimeInterval(86_400)
                ),
                status: .success,
                recordCount: 0
            )])
        )
        let data = HealthData(
            date: ExportFixtures.referenceDate,
            timeContext: ExportFixtures.timeContext,
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )

        XCTAssertTrue(data.hasAnyData)
        XCTAssertTrue(data.toJSON(customization: Self.customization).contains("healthkit_record_archive"))
    }

    func testProductionSerializationNeverSilentlyDropsCanonicalRecord() throws {
        let source = HealthKitSourceRevision(name: "Fixture", bundleIdentifier: "com.example.fixture")
        let record = HealthKitRecord(
            originalUUID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            objectTypeIdentifier: "HKQuantityTypeIdentifierHeartRate",
            recordKind: .quantity,
            selectedMetricIDs: ["heart_rate_avg"],
            includedBecause: .selectedMetric,
            startDate: ExportFixtures.referenceDate,
            endDate: ExportFixtures.referenceDate,
            sourceRevision: source,
            payload: .quantity(HealthKitQuantityPayload(value: .nan, unit: "count/min"))
        )
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-03-15",
                intervalStart: ExportFixtures.referenceDate,
                intervalEnd: ExportFixtures.referenceDate.addingTimeInterval(86_400),
                calendarTimeZoneIdentifier: "UTC"
            ),
            records: [record]
        )
        let data = HealthData(
            date: ExportFixtures.referenceDate,
            timeContext: ExportFixtures.timeContext,
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )

        let json = try data.toJSONThrowing(customization: Self.customization)
        let csv = try data.toCSVThrowing(customization: Self.customization)
        XCTAssertNotEqual(json, "{}")
        XCTAssertTrue(json.contains("30000000-0000-0000-0000-000000000001"))
        XCTAssertTrue(json.contains("NaN"))
        XCTAssertTrue(csv.contains("30000000-0000-0000-0000-000000000001"))
        XCTAssertTrue(csv.contains("NaN"))
    }

    func testNotRequestedMarkdownKeepsStatusInFrontmatterWithoutProminentSection() {
        let data = HealthData(
            date: ExportFixtures.referenceDate,
            timeContext: ExportFixtures.timeContext,
            healthKitRecordCaptureStatus: .notRequested
        )
        let markdown = data.toMarkdown(customization: Self.customization)

        XCTAssertTrue(markdown.contains("raw_capture_status: not_requested"), markdown)
        XCTAssertTrue(markdown.contains("raw_record_count: 0"), markdown)
        XCTAssertFalse(markdown.contains("## Lossless Health Records"), markdown)
    }

    func testQueryManifestDistinguishesEmptySuccessFromFailureAndKeepsError() throws {
        let json = try parseJSON(ExportFixtures.losslessDay.toJSON(customization: Self.customization))
        let archive = try XCTUnwrap(json["healthkit_record_archive"] as? [String: Any])
        let manifest = try XCTUnwrap(archive["query_manifest"] as? [String: Any])
        let results = try XCTUnwrap(manifest["results"] as? [[String: Any]])

        let emptySuccess = try XCTUnwrap(results.first { $0["identifier"] as? String == "success-empty" })
        XCTAssertEqual(emptySuccess["status"] as? String, "success")
        XCTAssertEqual(emptySuccess["record_count"] as? Int, 0)
        XCTAssertNil(emptySuccess["error"])

        let failure = try XCTUnwrap(results.first { $0["identifier"] as? String == "failed-heart-rate" })
        XCTAssertEqual(failure["status"] as? String, "failure")
        XCTAssertEqual(failure["record_count"] as? Int, 0)
        let error = try XCTUnwrap(failure["error"] as? [String: Any])
        XCTAssertEqual((error["code"] as? NSNumber)?.int64Value, Int64.min)
        XCTAssertEqual(error["is_recoverable"] as? Bool, true)
    }

    func testCSVHasLosslessCanonicalRowsAndJSONUUIDParity() throws {
        let data = ExportFixtures.losslessDay
        let json = try parseJSON(data.toJSON(customization: Self.customization))
        let archive = try XCTUnwrap(json["healthkit_record_archive"] as? [String: Any])
        let jsonRecords = try XCTUnwrap(archive["records"] as? [[String: Any]])
        let jsonUUIDs = jsonRecords.compactMap { $0["original_uuid"] as? String }

        let rows = parseRFC4180(data.toCSV(customization: Self.customization))
        XCTAssertEqual(rows.first, ["Date", "Category", "Metric", "Value", "Unit", "Timestamp"])

        let rawRows = rows.filter { $0.count == 6 && $0[2] == "Raw HealthKit Record" }
        XCTAssertEqual(rawRows.count, 7)
        XCTAssertTrue(rawRows.allSatisfy { $0.count == 6 && $0[4] == "json" })
        let csvRecords = try rawRows.map { try parseJSON($0[3]) }
        let csvUUIDs = csvRecords.compactMap { $0["original_uuid"] as? String }
        XCTAssertEqual(csvUUIDs, jsonUUIDs)
        XCTAssertEqual(rawRows.first?[5], "2026-03-15T00:00:01.125000000Z")
        XCTAssertEqual(csvRecords.first?["end_date"] as? String, "2026-03-15T00:00:02.500000000Z")
        XCTAssertNotNil(csvRecords.first?["source_revision"] as? [String: Any])

        let manifestRows = rows.filter { $0[2] == "Archive Manifest" }
        let queryFailureRows = rows.filter { $0[2] == "Query Failure" }
        let warningRows = rows.filter { $0[2] == "Integrity Warning" }
        let partialFailureRows = rows.filter { $0[2] == "Partial Failure" }
        XCTAssertEqual(manifestRows.count, 1)
        XCTAssertEqual(queryFailureRows.count, 1)
        XCTAssertEqual(warningRows.count, 1)
        XCTAssertEqual(partialFailureRows.count, 1)

        let manifest = try parseJSON(try XCTUnwrap(manifestRows.first?[3]))
        XCTAssertNotNil(manifest["ownership"] as? [String: Any])
        let queryManifest = try XCTUnwrap(manifest["query_manifest"] as? [String: Any])
        let queryResults = try XCTUnwrap(queryManifest["results"] as? [[String: Any]])
        XCTAssertEqual(Set(queryResults.compactMap { $0["status"] as? String }), ["success", "failure"])
        let inventory = try XCTUnwrap(manifest["medication_inventory"] as? [[String: Any]])
        XCTAssertNil(manifest["records"])

        // The canonical JSON still contains punctuation/newline content and exact integers after RFC 4180 parsing.
        let firstMetadata = try XCTUnwrap(csvRecords.first?["metadata"] as? [String: Any])
        XCTAssertEqual(
            (firstMetadata["string"] as? [String: Any])?["value"] as? String,
            "comma, quote \" and newline\nkept"
        )
        XCTAssertEqual(
            ((firstMetadata["unsigned"] as? [String: Any])?["value"] as? NSNumber)?.uint64Value,
            UInt64.max
        )
        let inventoryFields = try XCTUnwrap(inventory.first?["fields"] as? [String: Any])
        XCTAssertEqual(
            ((inventoryFields["maximum_refills"] as? [String: Any])?["value"] as? NSNumber)?.uint64Value,
            UInt64.max
        )
    }

    func testCSVFieldEscaperRoundTripsCommasQuotesAndNewlinesWithoutMutation() {
        let fields = ["plain", "comma,kept", "quote \"kept\"", "line one\nline two"]
        let csv = fields.map(CSVFieldEscaper.escape).joined(separator: ",") + "\n"
        XCTAssertEqual(parseRFC4180(csv), [fields])
        XCTAssertTrue(csv.contains("\nline two"), "A quoted newline must remain a newline, not a semicolon or space")
        XCTAssertFalse(csv.contains("comma;kept"))
    }

    func testRepeatedJSONAndCSVSerializationIsByteDeterministic() {
        let data = ExportFixtures.losslessDay
        XCTAssertEqual(
            data.toJSON(customization: Self.customization),
            data.toJSON(customization: Self.customization)
        )
        XCTAssertEqual(
            data.toCSV(customization: Self.customization),
            data.toCSV(customization: Self.customization)
        )
    }

    func testNotRequestedAndLegacyStatusesAreExplicitWithoutArchive() throws {
        let notRequested = HealthData(
            date: ExportFixtures.referenceDate,
            timeContext: ExportFixtures.timeContext,
            healthKitRecordCaptureStatus: .notRequested
        )
        let legacy = HealthData(
            date: ExportFixtures.referenceDate,
            timeContext: ExportFixtures.timeContext,
            healthKitRecordCaptureStatus: .legacyUnavailable
        )

        let notRequestedJSON = try parseJSON(notRequested.toJSON(customization: Self.customization))
        XCTAssertEqual(notRequestedJSON["raw_capture_status"] as? String, "not_requested")
        XCTAssertNil(notRequestedJSON["healthkit_record_archive"])
        let legacyJSON = try parseJSON(legacy.toJSON(customization: Self.customization))
        XCTAssertEqual(legacyJSON["raw_capture_status"] as? String, "legacy_unavailable")
        XCTAssertNil(legacyJSON["healthkit_record_archive"])

        let notRequestedRows = parseRFC4180(notRequested.toCSV(customization: Self.customization))
        XCTAssertTrue(notRequestedRows.contains {
            $0[2] == "Raw Capture Status" && $0[3] == "not_requested"
        })
        let legacyRows = parseRFC4180(legacy.toCSV(customization: Self.customization))
        XCTAssertTrue(legacyRows.contains {
            $0[2] == "Raw Capture Status" && $0[3] == "legacy_unavailable"
        })
    }

    func testFailureOnlyArchiveAndPartialFailureOnlyDayRemainDiagnostic() throws {
        let interval = HealthKitQueryInterval(
            startDate: ExportFixtures.referenceDate,
            endDate: ExportFixtures.referenceDate.addingTimeInterval(86_400)
        )
        let archive = HealthKitRecordArchive(
            captureStatus: .partial,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-03-15",
                intervalStart: interval.startDate,
                intervalEnd: interval.endDate,
                calendarTimeZoneIdentifier: "UTC"
            ),
            queryManifest: HealthKitQueryManifest(results: [HealthKitQueryResult(
                identifier: "failure-only",
                operation: "sample_query",
                metricIDs: ["steps"],
                interval: interval,
                status: .failure,
                recordCount: 0,
                error: HealthKitQueryError(domain: "HKErrorDomain", code: 5, description: "Denied")
            )])
        )
        let failureOnly = HealthData(
            date: ExportFixtures.referenceDate,
            timeContext: ExportFixtures.timeContext,
            healthKitRecordArchive: archive
        )

        let failureJSON = try parseJSON(failureOnly.toJSON(customization: Self.customization))
        let failureArchive = try XCTUnwrap(failureJSON["healthkit_record_archive"] as? [String: Any])
        XCTAssertTrue((failureArchive["records"] as? [[String: Any]])?.isEmpty == true)
        let failureRows = parseRFC4180(failureOnly.toCSV(customization: Self.customization))
        XCTAssertEqual(failureRows.filter { $0[2] == "Query Failure" }.count, 1)
        XCTAssertEqual(failureRows.filter { $0[2] == "Archive Manifest" }.count, 1)

        let partialOnly = HealthData(
            date: ExportFixtures.referenceDate,
            timeContext: ExportFixtures.timeContext,
            partialFailures: [ExportPartialFailure(
                date: ExportFixtures.referenceDate.addingTimeInterval(0.5),
                dataType: "steps",
                dateRangeDescription: "one day",
                errorDescription: "Unavailable"
            )]
        )
        let partialJSON = try parseJSON(partialOnly.toJSON(customization: Self.customization))
        XCTAssertEqual(
            ((partialJSON["diagnostics"] as? [String: Any])?["partial_failures"] as? [[String: Any]])?.count,
            1
        )
        let partialRows = parseRFC4180(partialOnly.toCSV(customization: Self.customization))
        XCTAssertEqual(partialRows.filter { $0[2] == "Partial Failure" }.count, 1)
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try XCTUnwrap(string.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Minimal RFC 4180 parser used to ensure embedded delimiters and line breaks remain inside fields.
    private func parseRFC4180(_ csv: String) -> [[String]] {
        let characters = Array(csv)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !isQuoted {
                row.append(field)
                field = ""
                if !row.allSatisfy(\.isEmpty) {
                    rows.append(row)
                }
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
}
