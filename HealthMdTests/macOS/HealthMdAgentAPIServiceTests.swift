#if os(macOS)
import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class HealthMdAgentAPIServiceTests: XCTestCase {
    func testDirectQueryUsesRequestMetricSourceAndDetailScope() async throws {
        let executor = DirectAgentAPIQueryExecutor()
        let fixture = makeFixture(executor: executor)
        let query = HealthMdQueryRequest(
            metrics: .explicit(["sleep_total"]),
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: []),
            dates: .exact(.init(startDate: "2026-07-20", endDate: "2026-07-21")),
            operation: .metricSeries
        )

        let response = await fixture.service.respond(request: request(
            method: "POST",
            path: "/v1/agent/query",
            body: try JSONEncoder().encode(QueryBody(request: query, detailLevel: .lossless))
        ))

        XCTAssertEqual(response.statusCode, 200)
        let object = try jsonObject(response.body)
        XCTAssertEqual(object["schema"] as? String, "healthmd.query_response")
        let executedRequest = await executor.lastRequest()
        let executedScope = await executor.lastEvidenceScope()
        XCTAssertEqual(executedRequest, query)
        let scope = try XCTUnwrap(executedScope)
        XCTAssertEqual(scope.allowedMetricIDs, ["sleep_total"])
        XCTAssertTrue(scope.allowsEvidenceValues)
        XCTAssertNil(scope.allowedSourceIDs)
        XCTAssertEqual(scope.allowedProviderIDs, [])
    }

    func testDirectEndpointsRejectRemovedAccessFieldsInsteadOfIgnoringThem() async throws {
        let executor = DirectAgentAPIQueryExecutor()
        let fixture = makeFixture(executor: executor) { _, _, _, _ in
            Self.exportResponse(status: .success)
        }
        let query = HealthMdQueryRequest(
            metrics: .explicit(["sleep_total"]),
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: []),
            dates: .exact(.init(startDate: "2026-07-20", endDate: "2026-07-21")),
            operation: .metricSeries
        )
        var oldQuery = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(QueryBody(request: query, detailLevel: .summary))
            ) as? [String: Any]
        )
        oldQuery["grant_id"] = UUID().uuidString
        oldQuery["profile"] = ["id": UUID().uuidString]
        let queryResponse = await fixture.service.respond(request: request(
            method: "POST",
            path: "/v1/agent/query",
            body: try JSONSerialization.data(withJSONObject: oldQuery)
        ))
        XCTAssertEqual(queryResponse.statusCode, 400)
        XCTAssertEqual(
            try jsonObject(queryResponse.body)["code"] as? String,
            "invalid_query_request"
        )
        let executedRequest = await executor.lastRequest()
        XCTAssertNil(executedRequest)

        let refresh = RefreshBody(
            dates: .allAvailable,
            metrics: .explicit(["sleep_total"]),
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: []),
            detailLevel: .summary,
            waitTimeoutSeconds: 300
        )
        var oldRefresh = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(refresh)) as? [String: Any]
        )
        oldRefresh["grant_id"] = UUID().uuidString
        let refreshResponse = await fixture.service.respond(request: request(
            method: "POST",
            path: "/v1/agent/refresh",
            body: try JSONSerialization.data(withJSONObject: oldRefresh)
        ))
        XCTAssertEqual(refreshResponse.statusCode, 400)
        XCTAssertEqual(
            try jsonObject(refreshResponse.body)["code"] as? String,
            "invalid_refresh_request"
        )
    }

    func testDirectRefreshBuildsCanonicalSelectionWithoutSavedProfileState() async throws {
        let executor = DirectAgentAPIQueryExecutor()
        await executor.setScopeCompletion(HealthMdRequestedScopeCompletion(
            status: .success,
            requestedMetricIDs: ["sleep_total"],
            daysConsidered: 2,
            metricDaysConsidered: 2,
            completeMetricDays: 2,
            incompleteMetricDays: 0,
            statusCounts: ["available": 2],
            unrelatedSkips: []
        ))
        let recorder = DirectRefreshRecorder()
        let fixture = makeFixture(executor: executor) { dates, selection, identifiers, timeout in
            recorder.dates = dates
            recorder.selection = selection
            recorder.identifiers = identifiers
            recorder.timeout = timeout
            return Self.exportResponse(status: .success, jobID: UUID())
        }
        let body = RefreshBody(
            dates: .exact(.init(startDate: "2026-07-20", endDate: "2026-07-21")),
            metrics: .explicit(["sleep_total"]),
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: []),
            detailLevel: .lossless,
            waitTimeoutSeconds: 120
        )

        let response = await fixture.service.respond(request: request(
            method: "POST",
            path: "/v1/agent/refresh",
            body: try JSONEncoder().encode(body)
        ))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(recorder.dates, body.dates)
        XCTAssertEqual(recorder.identifiers, ["2026-07-20", "2026-07-21"])
        XCTAssertEqual(recorder.timeout, 120)
        XCTAssertEqual(recorder.selection?.metricIDs, ["sleep_total"])
        XCTAssertEqual(recorder.selection?.sourceIDs, ["apple_health"])
        XCTAssertEqual(recorder.selection?.detailLevel, .lossless)
        XCTAssertEqual(recorder.selection?.objectPaths, [])
        XCTAssertEqual(recorder.selection?.fieldPointers, [])
        let object = try jsonObject(response.body)
        XCTAssertEqual(object["requested_scope_status"] as? String, "success")
        XCTAssertNil(object["grant_id"])
        XCTAssertNil(object["profile"])
    }

    func testRefreshRejectsUnknownMetricAndInvalidTimeout() async throws {
        let fixture = makeFixture(executor: DirectAgentAPIQueryExecutor()) { _, _, _, _ in
            Self.exportResponse(status: .success)
        }
        let unknownMetric = RefreshBody(
            dates: .allAvailable,
            metrics: .explicit(["future_metric"]),
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: []),
            detailLevel: .summary,
            waitTimeoutSeconds: 300
        )
        let unknownResponse = await fixture.service.respond(request: request(
            method: "POST",
            path: "/v1/agent/refresh",
            body: try JSONEncoder().encode(unknownMetric)
        ))
        XCTAssertEqual(unknownResponse.statusCode, 400)
        XCTAssertEqual(try jsonObject(unknownResponse.body)["code"] as? String, "unknown_metric")

        let invalidTimeout = RefreshBody(
            dates: .allAvailable,
            metrics: .explicit(["sleep_total"]),
            sources: .explicit(sourceIDs: ["apple_health"], providerIDs: []),
            detailLevel: .summary,
            waitTimeoutSeconds: 901
        )
        let timeoutResponse = await fixture.service.respond(request: request(
            method: "POST",
            path: "/v1/agent/refresh",
            body: try JSONEncoder().encode(invalidTimeout)
        ))
        XCTAssertEqual(timeoutResponse.statusCode, 400)
        XCTAssertEqual(try jsonObject(timeoutResponse.body)["code"] as? String, "invalid_timeout")
    }

    func testProviderOnlyRefreshProducesProviderOnlyCanonicalSelection() async throws {
        let recorder = DirectRefreshRecorder()
        let fixture = makeFixture(
            executor: DirectAgentAPIQueryExecutor(),
            availableProviderIDs: ["oura"]
        ) { dates, selection, identifiers, timeout in
            recorder.dates = dates
            recorder.selection = selection
            recorder.identifiers = identifiers
            recorder.timeout = timeout
            return Self.exportResponse(status: .success)
        }
        let body = RefreshBody(
            dates: .allAvailable,
            metrics: .explicit(["sleep_total"]),
            sources: .explicit(sourceIDs: [], providerIDs: ["oura"]),
            detailLevel: .summary,
            waitTimeoutSeconds: 300
        )

        let response = await fixture.service.respond(request: request(
            method: "POST",
            path: "/v1/agent/refresh",
            body: try JSONEncoder().encode(body)
        ))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(recorder.selection?.sourceIDs, ["oura"])
        XCTAssertNil(recorder.identifiers)
    }

    func testProfilesAndActivityEndpointsAreRemoved() async throws {
        let fixture = makeFixture(executor: DirectAgentAPIQueryExecutor())
        for request in [
            request(method: "GET", path: "/v1/agent/profiles"),
            request(method: "POST", path: "/v1/agent/activity/query", body: Data("{}".utf8))
        ] {
            let response = await fixture.service.respond(request: request)
            XCTAssertEqual(response.statusCode, 410)
            XCTAssertEqual(try jsonObject(response.body)["code"] as? String, "removed_endpoint")
        }
    }

    func testCapabilitiesAdvertiseDirectScopeAndNoCredentials() async throws {
        let fixture = makeFixture(executor: DirectAgentAPIQueryExecutor())
        let response = await fixture.service.respond(request: request(
            method: "GET",
            path: "/v1/agent/capabilities"
        ))

        XCTAssertEqual(response.statusCode, 200)
        let object = try jsonObject(response.body)
        XCTAssertEqual(object["schema"] as? String, "healthmd.local_capabilities")
        XCTAssertEqual(object["request_scoped"] as? Bool, true)
        XCTAssertEqual(object["request_scoped_context_acquisition"] as? Bool, true)
        XCTAssertNil(object["scoped_fresh_acquisition"])
        XCTAssertNil(object["credentials_required"])
        XCTAssertNil(object["profiles"])
        XCTAssertNil(object["grants"])
    }

    func testReadinessReportsCacheAndIPhoneWithoutIdentityOrGrantChecks() async throws {
        let executor = DirectAgentAPIQueryExecutor()
        await executor.setStoreReadiness(.init(
            revision: "revision-1",
            ownerDateCount: 2,
            firstOwnerDate: "2026-07-20",
            lastOwnerDate: "2026-07-21"
        ))
        let fixture = makeFixture(executor: executor)
        let response = await fixture.service.respond(request: request(
            method: "GET",
            path: "/v1/agent/readiness"
        ))

        XCTAssertEqual(response.statusCode, 200)
        let object = try jsonObject(response.body)
        XCTAssertEqual(object["schema"] as? String, "healthmd.local_readiness")
        XCTAssertEqual(object["status"] as? String, "ready")
        XCTAssertNil(object["registration"])
        XCTAssertNil(object["grants"])
        let iphone = try XCTUnwrap(object["iphone"] as? [String: Any])
        XCTAssertNotNil(iphone["supports_request_scoped_context_acquisition"])
        XCTAssertNil(iphone["supports_request_scoped_acquisition"])
        let checks = try XCTUnwrap(object["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { $0["code"] as? String == "encrypted_query_store" })
        XCTAssertFalse(checks.contains { $0["code"] as? String == "agent_credential" })
        XCTAssertFalse(checks.contains { $0["code"] as? String == "active_grant" })
    }

    func testMetricCatalogRemainsAvailableWithoutAuthorizationState() async throws {
        let fixture = makeFixture(executor: DirectAgentAPIQueryExecutor())
        let response = await fixture.service.respond(request: request(
            method: "GET",
            path: "/v1/agent/metrics"
        ))
        XCTAssertEqual(response.statusCode, 200)
        let object = try jsonObject(response.body)
        XCTAssertEqual(object["schema"] as? String, "healthmd.metric_catalog")
        let metrics = try XCTUnwrap(object["metrics"] as? [[String: Any]])
        XCTAssertTrue(metrics.contains { $0["id"] as? String == "sleep_total" })
    }

    private func makeFixture(
        executor: DirectAgentAPIQueryExecutor,
        availableProviderIDs: [String] = [],
        refresh: HealthMdAgentAPIService.RefreshExecutor? = nil
    ) -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentAPIDirectScope-\(UUID().uuidString)", isDirectory: true)
        let coordinator = MacIPhoneExportRequestCoordinator(rootURL: root)
        let syncService = SyncService()
        let service = HealthMdAgentAPIService(
            exportCoordinator: coordinator,
            syncService: syncService,
            destinationStatus: { Self.destinationStatus() },
            queryExecutor: executor,
            availableProviderIDs: availableProviderIDs,
            refreshExecutor: refresh
        )
        return Fixture(service: service, root: root)
    }

    private func request(
        method: String,
        path: String,
        body: Data = Data(),
        headers: [String: String] = [:]
    ) -> HealthMdControlServer.ParsedHTTPRequest {
        HealthMdControlServer.ParsedHTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: body
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func destinationStatus() -> MacDestinationStatus {
        MacDestinationStatus(
            isConnected: false,
            isReadyForExports: false,
            destinationFolderSelected: false,
            folderAccessHealthy: false,
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: .current(platform: .macOS)
        )
    }

    private static func exportResponse(
        status: MacIPhoneExportRequestCoordinator.ExportResponse.Status,
        jobID: UUID? = nil
    ) -> MacIPhoneExportRequestCoordinator.ExportResponse {
        MacIPhoneExportRequestCoordinator.ExportResponse(
            status: status,
            jobID: jobID,
            message: "fixture",
            successCount: status == .success ? 1 : nil,
            totalCount: status == .success ? 1 : nil,
            filesWritten: 0,
            externalRecordCount: 0,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: nil,
            rawData: nil,
            rawResult: nil
        )
    }

    private struct Fixture {
        let service: HealthMdAgentAPIService
        let root: URL
    }
}

private struct QueryBody: Encodable {
    let request: HealthMdQueryRequest
    let detailLevel: HealthMdQueryDetailLevel

    enum CodingKeys: String, CodingKey {
        case request
        case detailLevel = "detail_level"
    }
}

private struct RefreshBody: Encodable, Equatable {
    let dates: HealthMdDateSelection
    let metrics: HealthMdMetricSelection
    let sources: HealthMdSourceSelection
    let detailLevel: HealthMdQueryDetailLevel
    let waitTimeoutSeconds: Double

    enum CodingKeys: String, CodingKey {
        case dates, metrics, sources
        case detailLevel = "detail_level"
        case waitTimeoutSeconds = "wait_timeout_seconds"
    }
}

@MainActor
private final class DirectRefreshRecorder {
    var dates: HealthMdDateSelection?
    var selection: CanonicalHealthDataSelection?
    var identifiers: [String]?
    var timeout: Double?
}

private actor DirectAgentAPIQueryExecutor: HealthMdAgentQueryExecuting, HealthMdAgentQueryReadinessProviding {
    private var request: HealthMdQueryRequest?
    private var evidenceScope: HealthMdEvidenceScope?
    private var scopeCompletion: HealthMdRequestedScopeCompletion?
    private var storeReadiness = HealthMdAgentQueryStoreReadiness(
        revision: "fixture-query-store-revision",
        ownerDateCount: 3,
        firstOwnerDate: "2026-07-19",
        lastOwnerDate: "2026-07-21"
    )

    func execute(
        _ request: HealthMdQueryRequest,
        detailLevel: HealthMdQueryDetailLevel,
        evidenceScope: HealthMdEvidenceScope
    ) async throws -> HealthMdQueryResponse {
        self.request = request
        self.evidenceScope = evidenceScope
        return HealthMdQueryResponse(
            items: [],
            packet: nil,
            coverage: HealthMdCoverage(
                requestedRange: nil,
                availableRange: nil,
                status: .completeEmpty,
                daysConsidered: 0,
                daysWithValues: 0
            ),
            sources: [],
            evidence: [],
            nextCursor: nil,
            limitations: []
        )
    }

    func queryStoreBaseline() async throws -> HealthMdAgentQueryStoreBaseline? {
        HealthMdAgentQueryStoreBaseline(
            revision: "fixture-baseline",
            ownerDateMutationIDs: [:]
        )
    }

    func requestedScopeCompletion(
        dates: HealthMdDateSelection,
        metricIDs: Set<String>,
        sources: HealthMdSourceSelection,
        changedSince baseline: HealthMdAgentQueryStoreBaseline?
    ) async throws -> HealthMdRequestedScopeCompletion? {
        scopeCompletion
    }

    func queryStoreReadiness() async throws -> HealthMdAgentQueryStoreReadiness {
        storeReadiness
    }

    func setScopeCompletion(_ value: HealthMdRequestedScopeCompletion?) {
        scopeCompletion = value
    }

    func setStoreReadiness(_ value: HealthMdAgentQueryStoreReadiness) {
        storeReadiness = value
    }

    func lastRequest() -> HealthMdQueryRequest? { request }
    func lastEvidenceScope() -> HealthMdEvidenceScope? { evidenceScope }
}
#endif
