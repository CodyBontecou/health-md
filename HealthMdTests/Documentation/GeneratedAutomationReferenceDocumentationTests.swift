import XCTest
@testable import HealthMd

#if os(macOS)
@MainActor
final class GeneratedAutomationReferenceDocumentationTests: XCTestCase {
    func testGeneratedAutomationReferenceDocumentationHasNoDrift() throws {
        if FileManager.default.fileExists(
            atPath: GeneratedAutomationReferenceDocumentation.updateMarker.path
        ) {
            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent(
                    GeneratedAutomationReferenceDocumentation.updateOutputDirectoryName,
                    isDirectory: true
                )
            XCTAssertFalse(outputURL.path.contains("HealthMdTests/Fixtures/Export"))
            XCTAssertFalse(outputURL.path.contains("export_schema_signature"))
            try GeneratedAutomationReferenceDocumentation.write(to: outputURL)
            let names = try generatedFileNames(at: outputURL)
            XCTAssertEqual(names, Set(try GeneratedAutomationReferenceDocumentation.files().keys))
            try String(names.count).write(
                to: outputURL.appendingPathComponent(".complete"),
                atomically: true,
                encoding: .utf8
            )
            return
        }

        let expected = try GeneratedAutomationReferenceDocumentation.files()
        let committedDirectory = GeneratedAutomationReferenceDocumentation.committedDirectory
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: committedDirectory.path),
            "Missing generated automation documentation. Run scripts/generated-automation-reference-docs.sh update."
        )
        XCTAssertEqual(
            try generatedFileNames(at: committedDirectory),
            Set(expected.keys),
            "Generated automation artifact set drifted. Run scripts/generated-automation-reference-docs.sh update."
        )
        for name in expected.keys.sorted() {
            XCTAssertEqual(
                try Data(contentsOf: committedDirectory.appendingPathComponent(name)),
                expected[name],
                "Generated automation documentation drifted at \(name). Run scripts/generated-automation-reference-docs.sh update."
            )
        }
    }

    func testAutomationReferenceCoversRequiredArtifactsStatusesAndSyncMessages() throws {
        let files = try GeneratedAutomationReferenceDocumentation.files()
        XCTAssertTrue(
            GeneratedAutomationReferenceDocumentation.requiredArtifactNames.isSubset(of: Set(files.keys))
        )
        XCTAssertEqual(
            try GeneratedAutomationReferenceDocumentation.documentedSyncMessageCaseNames(),
            try GeneratedAutomationReferenceDocumentation.productionSyncMessageCaseNames()
        )

        let responseFiles = files.keys.filter { $0.hasPrefix("control-export-response-") }
        let statuses = try Set(responseFiles.map { name -> String in
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(files[name])) as? [String: Any]
            )
            return try XCTUnwrap(object["status"] as? String)
        })
        XCTAssertEqual(
            statuses,
            GeneratedAutomationReferenceDocumentation.documentedControlResponseStatuses
        )

        for name in files.keys.sorted() {
            let data = try XCTUnwrap(files[name])
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains("..."), name)
            XCTAssertFalse(text.contains("…"), name)
            if name.hasSuffix(".json") {
                XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), name)
            }
        }
    }

    func testGeneratedExamplesUseProductionContractShapes() throws {
        let files = try GeneratedAutomationReferenceDocumentation.files()

        let apiV1 = try jsonObject("api-export-v1.json", files: files)
        XCTAssertEqual(apiV1["schema"] as? String, "healthmd.api_export")
        XCTAssertEqual(apiV1["schema_version"] as? Int, 1)
        XCTAssertNil(apiV1["external_records"])

        let apiV2 = try jsonObject("api-export-v2-provider-sidecar.json", files: files)
        XCTAssertEqual(apiV2["schema_version"] as? Int, 2)
        XCTAssertEqual(apiV2["external_record_schema"] as? String, ExternalDailyRecord.schema)
        XCTAssertEqual((apiV2["external_records"] as? [Any])?.count, 1)

        let status = try jsonObject("control-status.json", files: files)
        XCTAssertEqual(status["mac_app"] as? String, "running")
        XCTAssertNotNil(status["active_export"])

        let completeRaw = try jsonObject("raw-result-complete.json", files: files)
        XCTAssertEqual(completeRaw["schema"] as? String, CanonicalRawResultEnvelope.schemaIdentifier)
        XCTAssertEqual(completeRaw["schema_version"] as? Int, CanonicalRawResultEnvelope.currentSchemaVersion)
        let completeDay = try XCTUnwrap((completeRaw["days"] as? [[String: Any]])?.first)
        XCTAssertTrue(completeDay["health_data"] is [String: Any])
        XCTAssertNil(completeDay["canonical_daily_json"])

        let partialRaw = try jsonObject("raw-result-partial.json", files: files)
        XCTAssertEqual(partialRaw["missing_dates"] as? [String], ["2026-03-16"])
        let partialSummary = try XCTUnwrap(partialRaw["capture_summary"] as? [String: Any])
        XCTAssertEqual(partialSummary["partial_day_count"] as? Int, 1)
        XCTAssertEqual(partialSummary["missing_day_count"] as? Int, 1)

        let connectedDecoder = JSONDecoder()
        XCTAssertNoThrow(try connectedDecoder.decode(
            SyncPeerCapabilities.self,
            from: try XCTUnwrap(files["peer-capabilities.json"])
        ))
        XCTAssertNoThrow(try connectedDecoder.decode(
            IPhoneExportRequest.self,
            from: try XCTUnwrap(files["iphone-export-request-strict-raw.json"])
        ))
        XCTAssertNoThrow(try connectedDecoder.decode(
            ConnectedTransferStart.self,
            from: try XCTUnwrap(files["transfer-offer.json"])
        ))
        XCTAssertNoThrow(try connectedDecoder.decode(
            MacExportJob.self,
            from: try XCTUnwrap(files["mac-export-job.json"])
        ))
        XCTAssertNoThrow(try connectedDecoder.decode(
            MacExportResultPayload.self,
            from: try XCTUnwrap(files["mac-export-result-partial.json"])
        ))
    }

    func testPrivateControlRequestFixturesFollowServerTestConstructionPattern() throws {
        let files = try GeneratedAutomationReferenceDocumentation.files()
        for name in ["control-write-files-request.json", "control-strict-raw-request.json"] {
            let body = try XCTUnwrap(files[name])
            let request = HealthMdControlServer.ParsedHTTPRequest(
                method: "POST",
                path: "/v1/exports",
                headers: [
                    "content-length": String(body.count),
                    "content-type": "application/json"
                ],
                body: body
            )
            XCTAssertEqual(HealthMdControlServer.validationDecision(for: request), .valid)
            XCTAssertNotNil(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
    }

    private func jsonObject(
        _ name: String,
        files: [String: Data]
    ) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(files[name])) as? [String: Any]
        )
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
#endif
