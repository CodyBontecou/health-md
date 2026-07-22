import XCTest
@testable import HealthMd

#if os(macOS)
final class HealthMdAgentAPIServiceTests: XCTestCase {
    @MainActor
    func testAuthorizedQueryUsesPinnedProfileGrantAndVersionedResponse() async throws {
        let fixture = try await makeFixture()
        let query = HealthMdQueryRequest(
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries,
            page: .init(maxItems: 10, maxBytes: 10_000)
        )
        let body = QueryTestBody(
            grantID: fixture.grant.id,
            profile: try fixture.profile.reference(),
            request: query,
            detailLevel: .summary,
            correlationID: UUID()
        )
        let request = HealthMdControlServer.ParsedHTTPRequest(
            method: "POST",
            path: "/v1/agent/query",
            headers: ["content-type": "application/json", "content-length": "1"],
            body: try JSONEncoder().encode(body)
        )

        let response = await fixture.service.respond(
            registration: fixture.registration,
            request: request
        )

        XCTAssertEqual(response.statusCode, 200)
        let decoded = try HealthMdQueryCanonicalSerializer.decode(
            HealthMdQueryResponse.self,
            from: response.body
        )
        XCTAssertEqual(decoded.schema, HealthMdQuerySchemas.queryResponse)
        let executed = await fixture.executor.lastRequest()
        XCTAssertEqual(executed, query)
        XCTAssertTrue(fixture.bridge.activity.contains {
            $0.clientIdentity.registrationID == fixture.registration.id
        })
    }

    @MainActor
    func testAnotherRegistrationCannotUseGrantOrSeeProfiles() async throws {
        let fixture = try await makeFixture()
        let other = try await fixture.bridge.registerLocalAgent(displayName: "Other agent")
        fixture.bridge.dismissCredentialReveal()
        let query = HealthMdQueryRequest(
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries
        )
        let body = QueryTestBody(
            grantID: fixture.grant.id,
            profile: try fixture.profile.reference(),
            request: query,
            detailLevel: .summary,
            correlationID: UUID()
        )

        let denied = await fixture.service.respond(
            registration: other,
            request: .init(
                method: "POST",
                path: "/v1/agent/query",
                headers: [:],
                body: try JSONEncoder().encode(body)
            )
        )
        XCTAssertEqual(denied.statusCode, 403)

        let profiles = await fixture.service.respond(
            registration: other,
            request: .init(method: "GET", path: "/v1/agent/profiles", headers: [:], body: Data())
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: profiles.body) as? [String: Any]
        )
        XCTAssertEqual((object["profiles"] as? [Any])?.count, 0)
    }

    @MainActor
    func testAuthorizedRefreshPinsFullProfilePolicyAndOwnerBeforeExecution() async throws {
        let fixture = try await makeFixture(refreshEnabled: true)
        let body = RefreshTestBody(
            grantID: fixture.grant.id,
            profile: try fixture.profile.reference(),
            dates: .allAvailable,
            waitTimeoutSeconds: 30,
            correlationID: UUID()
        )
        let response = await fixture.service.respond(
            registration: fixture.registration,
            request: .init(
                method: "POST",
                path: "/v1/agent/refresh",
                headers: [:],
                body: try JSONEncoder().encode(body)
            )
        )

        XCTAssertEqual(response.statusCode, 202)
        XCTAssertEqual(fixture.refreshRecorder.registrationID, fixture.registration.id)
        XCTAssertEqual(fixture.refreshRecorder.grantID, fixture.grant.id)
        XCTAssertEqual(fixture.refreshRecorder.policy?.profileID, fixture.profile.id)
        XCTAssertEqual(
            Set(fixture.refreshRecorder.policy?.request.metricIDs ?? []),
            Set(HealthMetrics.all.map(\.id))
        )
        XCTAssertEqual(fixture.refreshRecorder.policy?.request.dates, .allHistory)
        XCTAssertEqual(
            Set(fixture.refreshRecorder.policy?.request.sourceIDs ?? []),
            Set(["apple_health"] + ExternalIntegrationProvider.allCases.map(\.id))
        )
        XCTAssertEqual(fixture.refreshRecorder.policy?.request.detailLevel, .lossless)
    }

    @MainActor
    func testUnknownClaimedAgentSurfaceFailsClosed() async throws {
        let fixture = try await makeFixture()
        let body = QueryTestBody(
            grantID: fixture.grant.id,
            profile: try fixture.profile.reference(),
            request: HealthMdQueryRequest(
                metrics: .allAvailable,
                dates: .allAvailable,
                operation: .metricSeries
            ),
            detailLevel: .summary,
            correlationID: UUID()
        )
        let response = await fixture.service.respond(
            registration: fixture.registration,
            request: .init(
                method: "POST",
                path: "/v1/agent/query",
                headers: ["x-healthmd-surface": "untrusted_future_surface"],
                body: try JSONEncoder().encode(body)
            )
        )
        XCTAssertEqual(response.statusCode, 400)
    }

    @MainActor
    func testCapabilitiesPromiseContinuationNotTotalCaps() async throws {
        let fixture = try await makeFixture()
        let response = await fixture.service.respond(
            registration: fixture.registration,
            request: .init(method: "GET", path: "/v1/agent/capabilities", headers: [:], body: Data())
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        )
        XCTAssertEqual(object["all_available_metrics"] as? Bool, true)
        XCTAssertEqual(object["all_available_history"] as? Bool, true)
        XCTAssertEqual(object["complete_cursor_traversal"] as? Bool, true)
        XCTAssertEqual(object["fresh_acquisition"] as? Bool, false)
    }

    @MainActor
    private func makeFixture(refreshEnabled: Bool = false) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-api-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let profileStore = HealthContextProfileStore(rootURL: root.appendingPathComponent("profiles"))
        let profileManager = HealthContextProfileManager(store: profileStore)
        await profileManager.load()
        let profile = try await profileManager.createFullAccessProfile()

        let core = AgentAccessManager(
            directoryURL: root.appendingPathComponent("access"),
            credentialStore: AgentAPICredentialStore()
        )
        let bridge = MacAgentAccessManager(
            accessManager: core,
            credentialGenerator: { _ in Data(repeating: 0x44, count: 32) }
        )
        await bridge.load()
        let registration = try await bridge.registerLocalAgent(displayName: "Query agent")
        bridge.dismissCredentialReveal()
        let grant = try await bridge.createGrant(for: registration.id, profile: profile)
        try await bridge.confirmGrant(grant.id, broadScopeAcknowledged: true)

        let executor = AgentAPIQueryExecutor()
        let refreshRecorder = AgentAPIRefreshRecorder()
        let refreshExecutor: HealthMdAgentAPIService.RefreshExecutor? = refreshEnabled ? { @MainActor @Sendable
            registration, grantID, policy, timeout in
            refreshRecorder.registrationID = registration.id
            refreshRecorder.grantID = grantID
            refreshRecorder.policy = policy
            refreshRecorder.timeout = timeout
            return MacIPhoneExportRequestCoordinator.ExportResponse(
                status: .accepted,
                jobID: UUID(),
                message: "Accepted",
                successCount: nil,
                totalCount: nil,
                filesWritten: nil,
                externalRecordCount: nil,
                destinationDisplayName: nil,
                destinationPath: nil,
                failureReason: nil,
                rawData: nil,
                rawResult: nil,
                durable: true
            )
        } : nil
        let service = HealthMdAgentAPIService(
            agentAccessManager: bridge,
            profileManager: profileManager,
            exportCoordinator: MacIPhoneExportRequestCoordinator(rootURL: root.appendingPathComponent("jobs")),
            syncService: SyncService(),
            destinationStatus: { Self.destinationStatus() },
            queryExecutor: executor,
            refreshExecutor: refreshExecutor
        )
        return Fixture(
            bridge: bridge,
            profile: profile,
            registration: registration,
            grant: grant,
            executor: executor,
            refreshRecorder: refreshRecorder,
            service: service
        )
    }

    @MainActor
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

    private struct Fixture {
        let bridge: MacAgentAccessManager
        let profile: HealthContextProfile
        let registration: AgentClientRegistration
        let grant: AgentAccessGrant
        let executor: AgentAPIQueryExecutor
        let refreshRecorder: AgentAPIRefreshRecorder
        let service: HealthMdAgentAPIService
    }
}

@MainActor
private final class AgentAPIRefreshRecorder {
    var registrationID: UUID?
    var grantID: UUID?
    var policy: HealthContextExecutionPolicy?
    var timeout: Double?
}

private struct RefreshTestBody: Encodable {
    let grantID: UUID
    let profile: HealthContextProfileReference
    let dates: HealthMdDateSelection?
    let waitTimeoutSeconds: Double
    let correlationID: UUID

    enum CodingKeys: String, CodingKey {
        case grantID = "grant_id"
        case profile, dates
        case waitTimeoutSeconds = "wait_timeout_seconds"
        case correlationID = "correlation_id"
    }
}

private struct QueryTestBody: Encodable {
    let grantID: UUID
    let profile: HealthContextProfileReference
    let request: HealthMdQueryRequest
    let detailLevel: AgentDetailLevel
    let correlationID: UUID

    enum CodingKeys: String, CodingKey {
        case grantID = "grant_id"
        case profile, request
        case detailLevel = "detail_level"
        case correlationID = "correlation_id"
    }
}

private actor AgentAPIQueryExecutor: HealthMdAgentQueryExecuting {
    private var request: HealthMdQueryRequest?

    func execute(
        _ request: HealthMdQueryRequest,
        detailLevel: AgentDetailLevel
    ) async throws -> HealthMdQueryResponse {
        self.request = request
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

    func lastRequest() -> HealthMdQueryRequest? { request }
}

private final class AgentAPICredentialStore: AgentCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Data] = [:]

    func credential(for registrationID: UUID) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[registrationID]
    }

    func storeCredential(_ credential: Data, for registrationID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        values[registrationID] = credential
    }

    func removeCredential(for registrationID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: registrationID)
    }
}
#endif
