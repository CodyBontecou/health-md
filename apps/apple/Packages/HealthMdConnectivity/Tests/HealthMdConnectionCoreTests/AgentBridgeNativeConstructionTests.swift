import Foundation
import XCTest
import HealthMdConnectionCore

final class AgentBridgeNativeConstructionTests: XCTestCase {
    /// Assembly below uses Swift DTO constructors, never candidate JSON or a generic JSON tree.
    /// Expected bytes are loaded only AFTER actual native payloads have been assembled and encoded.
    func testGenerateCandidateVectorsFromIndependentNativeDTOs() throws {
        let peer = AgentBridgePeer(sourceInstallationID: try id(1), hostInstallationID: try id(2), platform: .android)
        let destination = AgentBridgeDestination(bindingID: try id(3), identitySHA256: try digest("1"), revision: 1, hostInstallationID: try id(2))
        let settings = output()
        let selection = AgentBridgeSelection(metricIDs: [try AgentBridgeID("steps")], categoryIDs: [], sourceIDs: [try AgentBridgeID("health_connect")], providerIDs: [], allMetrics: false)
        let dates = AgentBridgeDates.exact(.init(startDate: try AgentBridgeDate("2000-01-01"), endDate: try AgentBridgeDate("2000-01-02")))
        let intent = AgentBridgeGeneratedIntent(intentID: try id(4), peer: peer, destination: destination, dates: dates, calendarTimezone: try AgentBridgeZone("Etc/UTC"), captureScope: .init(selection: selection, compatibilityDetail: .summary, nativeArchive: .none), settingsPolicy: .explicit(settings))
        let references = AgentBridgeAuthorityReferences(host: .init(authorityId: try id(13), grantRevision: 1, grantSha256: try AgentBridgeDigest("7d5a9634acce2a6ff721eb423dcd0d942e6e8fe248085efca0b2ef9b1c5126ca"), issuer: .authorizedHost), native: .init(authorityId: try id(7), grantRevision: 1, grantSha256: try AgentBridgeDigest("b158a48b9e0a5fbe9aa60417565b753427c983af5d2cee499814741b44100e35"), issuer: .nativeSource))
        let plan = AgentBridgePlan(authorityReferences: references, capabilitySha256: try AgentBridgeDigest("1b4006c54905b73e2d687a63e57abff1e89d230ae849c5f3055627d5a25e1b01"), effectiveSettings: settings, expiresAt: try AgentBridgeUTC("2000-01-03T00:10:00Z"), intent: intent, issuedAt: try AgentBridgeUTC("2000-01-03T00:00:00Z"), limitations: [], origins: origins(), pathPrediction: .exactRequestedDays, planId: try id(6), planSha256: try AgentBridgeDigest("cfd47fa65c210f933896dcbcbf980a077c6516020c1a7044f4b74d8b59f6095d"), predictedPaths: [try AgentBridgePath("2000/2000-01-01.json"), try AgentBridgePath("2000/2000-01-02.json")], requiredActions: [], resolvedDates: dates, resolvedMetricIds: [try AgentBridgeID("steps")], revisions: [], scopeSha256: try AgentBridgeDigest("096f27bed7dcf8f8acaea8692675c0b8039ec4e4706382e89803f5bb281d4663"), settingsSha256: try AgentBridgeDigest("c6f838050f052c1423ea72b3aedd4cc37a1e11fd2ace34e433eb6a3122b844ab"), sideEffects: .init())
        let binding = AgentBridgeSemantics.binding(plan)
        let approval = AgentBridgeApproval(approvalId: try id(8), approvedAt: try AgentBridgeUTC("2000-01-03T00:00:30Z"), authorityId: try id(7), binding: binding, rights: [.exportExecute])
        let execute = AgentBridgeExecute(approval: approval, idempotencyKey: try id(11), jobId: try id(10), plan: plan, requestId: try id(9))
        let requestHash = try AgentBridgeDigest(AgentBridgeV4Codec.digest(execute))
        XCTAssertEqual(requestHash.rawValue, "d3097b1981c51386765e7324f2a7ec15679f10cbf53450feb9a5264f5fd44af5")
        let artifact = AgentBridgeArtifact(artifactId: try id(20), byteCount: 32, mediaType: .applicationJson, profile: .androidAnalyticalV5, relativePath: try AgentBridgePath("2000/2000-01-01.json"), sha256: try digest("a"), writeMode: .append)
        let manifest = AgentBridgeArtifactManifest(artifacts: [artifact], binding: binding, branchStatuses: [.init(recordCount: 1, selectorId: try AgentBridgeID("steps"), status: .success)], captureStatus: .complete, jobId: try id(10), requestSha256: requestHash)
        let commit = AgentBridgeCommitReceipt(afterSha256: try digest("c"), artifactId: try id(20), beforeSha256: try digest("b"), commitKey: try AgentBridgeDigest("d796d485cb5df9808d06ca7e70bd0bf60c12f1923dff189251c6e46630783446"), destination: destination, inputSha256: try digest("a"), jobId: try id(10), manifestSha256: try digest("6"), peer: peer, relativePath: try AgentBridgePath("2000/2000-01-01.json"), requestSha256: requestHash, status: .committed, writeMode: .append)
        let request = AgentBridgeDiscoveryRequest(requestID: try id(100), peer: peer)
        let discovery = try discovery(peer: peer, reference: references.native)
        let receipt = AgentBridgeExecutionReceipt(artifactCount: 1, binding: binding, committedPartitionCount: 1, expiresAt: try AgentBridgeUTC("2000-01-10T00:00:00Z"), frontierSha256: try digest("7"), jobId: try id(10), manifestSha256: try digest("6"), requestSha256: requestHash, sourceAcknowledged: true, status: .complete)
        let payloads: [(Int, AgentBridgeDocument)] = [(35, .discoveryRequest(request)), (36, .discovery(discovery)), (38, .plan(plan)), (41, .execute(execute)), (43, .receipt(receipt)), (45, .manifest(manifest)), (46, .commit(commit))]
        let actual = try payloads.map { index, document in
            let envelope = try AgentBridgeEnvelope(payload: document)
            let bytes = try AgentBridgeV4Codec.encode(envelope)
            return Candidate(vector_index: index, value: envelope, canonical_base64: bytes.base64EncodedString(), sha256: AgentBridgeV4Codec.sha256(bytes))
        }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        let expected = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("packages/contracts/agent-bridge/v1/fixtures/conformance.json")))
        XCTAssertEqual(actual.count, 7)
        for candidate in actual {
            XCTAssertEqual(candidate.canonical_base64, expected.canonical_vectors[candidate.vector_index].canonical_base64, "native vector \(candidate.vector_index)")
            XCTAssertEqual(candidate.sha256, expected.canonical_vectors[candidate.vector_index].sha256, "native vector \(candidate.vector_index)")
        }
        if ProcessInfo.processInfo.environment["HEALTHMD_GENERATE_AGENT_BRIDGE_V4"] == "1" {
            guard let path = ProcessInfo.processInfo.environment["HEALTHMD_AGENT_BRIDGE_CANDIDATES"], !path.isEmpty else { throw AgentBridgeValidationError.invalidRequest }
            let output = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let repository = root.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix("/"), !output.path.hasPrefix(repository + "/") else { throw AgentBridgeValidationError.invalidRequest }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(CandidateOutput(language: "swift", coverage: .init(typed_constructor_vectors: actual.count, generic_tree_vectors: 0, runtime_authorization: false), vectors: actual)).write(to: output, options: .atomic)
        }
    }

    private func id(_ value: Int) throws -> AgentBridgeUUID { try .init(String(format: "00000000-0000-4000-8000-%012x", value)) }
    private func digest(_ digit: String) throws -> AgentBridgeDigest { try .init(String(repeating: digit, count: 64)) }
    private struct Fixture: Decodable { let canonical_vectors: [Vector] }
    private struct Vector: Decodable { let canonical_base64: String; let sha256: String }
    private struct Candidate: Encodable { let vector_index: Int; let value: AgentBridgeEnvelope; let canonical_base64: String; let sha256: String }
    private struct CandidateOutput: Encodable { let language: String; let coverage: Coverage; let vectors: [Candidate] }
    private struct Coverage: Encodable { let typed_constructor_vectors: Int; let generic_tree_vectors: Int; let runtime_authorization: Bool }

    private func discovery(peer: AgentBridgePeer, reference: AgentBridgeAuthorityReference) throws -> AgentBridgeDiscovery {
        let pointers = origins().map(\.pointer).filter { $0.hasPrefix("/effective_settings/") }.map { String($0.dropFirst("/effective_settings".count)) }
        let support = AgentBridgeOutputSupport(compatibilityDetail: [.selectedTimeSeries, .summary], formats: [.csv, .json, .markdown, .obsidianBases], maxArtifacts: 4096, maxPathBytes: 4096, nativeArchiveProducts: [.androidProviderNativeSnapshotV1, .none], pathTokens: [.category, .date, .day, .metric, .month, .recordId, .year], settingPointers: pointers, writeModes: [.append, .mergeMarkdown, .mergeMarkdownPreservingPreamble, .overwrite])
        let operations = try ["coverage", "derive_packet", "metric_catalog", "metric_series", "period_comparison", "sleep_session_listing", "source_record_listing", "workout_listing", "workout_sleep_alignment"].map(AgentBridgeID.init)
        return .init(authorityReferences: [reference], budgets: .init(cursorIdleSeconds: 600, cursorLifetimeSeconds: 3600, maxCalendarDays: 366000, maxCaptureSeconds: 120, maxPageBytes: 1048576, maxPageItems: 1000, maxSnapshotBytes: 67108864), capabilityRevision: 1, capabilitySha256: try AgentBridgeDigest("aeae0ca3504452a895d24b570217125c05c0f6607e2486629787b7b98d9eb89f"), configurationProtection: .locked, controlOperations: [], entitlement: .required, expiresAt: try AgentBridgeUTC("2000-01-03T00:10:00Z"), features: [.boundExecution, .explicitSettings, .sourceQuery, .zeroHealthPlan], issuedAt: try AgentBridgeUTC("2000-01-03T00:00:00Z"), lifecycle: .androidUserStartedServiceAfterFirstUnlock, nativeGrants: .unverified, outputProfiles: [.androidAnalyticalV5, .androidFrozenV4], outputSupport: support, peer: peer, projectionCatalogSha256: try digest("0"), projectionProducts: [], queryCatalogSha256: try AgentBridgeDigest("34b1c6c551a54eef982aaecee02e7c088679aee81ab84cb5964022e5cb5021bd"), queryOperations: operations, requestId: try id(100), requiredActions: [.grantHealthAccess], settingsPolicies: [.explicit, .profile, .savedDeviceSettings], sourceCalendarTimezone: try AgentBridgeZone("Etc/UTC"))
    }

    private func output() -> AgentBridgeOutputSettings {
        .init(formats: [.json], outputProfile: .androidAnalyticalV5, subfolder: "", folderTemplate: "{year}", filenameTemplate: "{date}", writeMode: .overwrite, presentation: .init(displayUnits: .metric, locale: "en-US", includeMetadata: true, groupByCategory: true, frontmatter: .init(enabledFieldIDs: [], customFields: [], includeUnits: true, includeCaptureDiagnostics: true), markdown: .init(style: .tables, customTemplate: "", placeholderIDs: [])), individualEntries: .init(enabled: false, metricIDs: [], folderTemplate: "entries/{year}", filenameTemplate: "{date}-{record_id}", categoryFolders: false), dailyNotes: .init(enabled: false, only: false, folderTemplate: "notes/{year}", filenameTemplate: "{date}", createIfMissing: false, sectionIDs: []), packaging: .looseFiles, dictionary: .none)
    }
    private func origins() -> [AgentBridgeOrigin] {
        // Explicit leaf inventory, independent of both the fixture tree and production leaf walker.
        let pointers = ["/calendar_timezone", "/capture_scope/compatibility_detail", "/capture_scope/native_archive/type", "/capture_scope/selection/all_metrics", "/capture_scope/selection/category_ids", "/capture_scope/selection/metric_ids", "/capture_scope/selection/provider_ids", "/capture_scope/selection/source_ids", "/effective_settings/daily_notes/create_if_missing", "/effective_settings/daily_notes/enabled", "/effective_settings/daily_notes/filename_template", "/effective_settings/daily_notes/folder_template", "/effective_settings/daily_notes/only", "/effective_settings/daily_notes/section_ids", "/effective_settings/dictionary/type", "/effective_settings/filename_template", "/effective_settings/folder_template", "/effective_settings/formats", "/effective_settings/individual_entries/category_folders", "/effective_settings/individual_entries/enabled", "/effective_settings/individual_entries/filename_template", "/effective_settings/individual_entries/folder_template", "/effective_settings/individual_entries/metric_ids", "/effective_settings/output_profile", "/effective_settings/packaging/type", "/effective_settings/presentation/display_units", "/effective_settings/presentation/frontmatter/custom_fields", "/effective_settings/presentation/frontmatter/enabled_field_ids", "/effective_settings/presentation/frontmatter/include_capture_diagnostics", "/effective_settings/presentation/frontmatter/include_units", "/effective_settings/presentation/group_by_category", "/effective_settings/presentation/include_metadata", "/effective_settings/presentation/locale", "/effective_settings/presentation/machine_units", "/effective_settings/presentation/markdown/custom_template", "/effective_settings/presentation/markdown/placeholder_ids", "/effective_settings/presentation/markdown/style", "/effective_settings/subfolder", "/effective_settings/write_mode", "/resolved_dates"]
        return pointers.map { .init(origin: $0 == "/resolved_dates" ? .resolvedCalendar : .request, pointer: $0, revision: 0) }
    }
}
