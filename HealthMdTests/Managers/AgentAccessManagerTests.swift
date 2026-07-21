import XCTest
@testable import HealthMd

final class AgentAccessManagerTests: XCTestCase {
    func testUnlimitedGrantAuthorizesAllHistoryAllMetricsLosslessAndAPIEndpoint() async throws {
        let fixture = try await makeFixture(
            operations: .allOperations,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevels: .allDetailLevels,
            destinations: .allDestinationClasses,
            resourceControls: AgentResourceControls(maxRecordsPerPage: 250, maxBytesPerStreamChunk: 32_768)
        )
        let request = makeRequest(
            fixture: fixture,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detail: .losslessRecords,
            destination: .apiEndpoint
        )

        let decision = await fixture.manager.checkAuthorization(context(fixture: fixture, request: request))

        XCTAssertTrue(decision.isAuthorized)
        XCTAssertEqual(decision.request.dateScope, .allHistory)
        XCTAssertEqual(decision.request.metricScope, .allAvailable)
        XCTAssertEqual(decision.request.detailLevel, .losslessRecords)
        XCTAssertEqual(decision.request.destinationClass, .apiEndpoint)
        XCTAssertEqual(decision.resourceControls?.maxRecordsPerPage, 250)
        XCTAssertNil(fixture.grant.expiresAt)
    }

    func testNarrowGrantDeniesOverbroadDateAndMetricRequestsWithoutNarrowing() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400)
        let fixture = try await makeFixture(
            operations: .operations([.readHealthData]),
            dateScope: .exact(start: start, end: end),
            metricScope: .metricIDs(["steps"]),
            detailLevels: .detailLevels([.summary]),
            destinations: .destinationClasses([.inProcessResponse])
        )
        let broaderDates = makeRequest(
            fixture: fixture,
            dateScope: .exact(start: start.addingTimeInterval(-1), end: end),
            metricScope: .metricIDs(["steps"])
        )
        let broaderMetrics = makeRequest(
            fixture: fixture,
            dateScope: .exact(start: start, end: end),
            metricScope: .metricIDs(["steps", "heart_rate"])
        )

        let dateDecision = await fixture.manager.checkAuthorization(context(fixture: fixture, request: broaderDates))
        let metricDecision = await fixture.manager.checkAuthorization(context(fixture: fixture, request: broaderMetrics))

        XCTAssertEqual(dateDecision.reasonCode, .dateScopeNotGranted)
        XCTAssertEqual(dateDecision.request.dateScope, broaderDates.dateScope)
        XCTAssertEqual(metricDecision.reasonCode, .metricScopeNotGranted)
        XCTAssertEqual(metricDecision.request.metricScope, broaderMetrics.metricScope)
    }

    func testAllHistoryAndAllMetricsRequireMatchingUnlimitedProfilePolicy() async throws {
        let fixture = try await makeFixture()
        let request = makeRequest(fixture: fixture, dateScope: .allHistory, metricScope: .allAvailable)
        let narrowPolicy = HealthContextProfileEffectivePolicy(
            reference: fixture.profile,
            operations: .allOperations,
            dateScope: .exact(start: fixture.now, end: fixture.now),
            metricScope: .allAvailable,
            detailLevels: .allDetailLevels,
            destinationClasses: .allDestinationClasses
        )

        let denied = await fixture.manager.checkAuthorization(AgentAuthorizationContext(
            request: request,
            grantID: fixture.grant.id,
            profilePolicy: narrowPolicy,
            healthKitAuthorization: authorizedHealthKit(at: fixture.now)
        ))
        let allowed = await fixture.manager.checkAuthorization(context(fixture: fixture, request: request))

        XCTAssertEqual(denied.reasonCode, .profileDateScopeDenied)
        XCTAssertTrue(allowed.isAuthorized)
    }

    func testProfileRevisionMismatchIsStructuredDenial() async throws {
        let fixture = try await makeFixture()
        let mismatched = testProfileReference(
            id: fixture.profile.profileID,
            revision: fixture.profile.revision.rawValue + 1
        )
        let request = AgentAccessRequest(
            clientIdentity: .registered(fixture.registration.id),
            profileReference: mismatched,
            operation: .readHealthData,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevel: .summary,
            destinationClass: .inProcessResponse
        )

        let decision = await fixture.manager.checkAuthorization(context(fixture: fixture, request: request))

        XCTAssertFalse(decision.isAuthorized)
        XCTAssertEqual(decision.reasonCode, .profileRevisionMismatch)
    }

    func testProfileDigestMismatchIsStructuredDenial() async throws {
        let fixture = try await makeFixture()
        let mismatched = HealthContextProfileReference(
            profileID: fixture.profile.profileID,
            revision: fixture.profile.revision,
            policyDigest: String(repeating: "b", count: 64)
        )
        let request = AgentAccessRequest(
            clientIdentity: .registered(fixture.registration.id),
            profileReference: mismatched,
            operation: .readHealthData,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevel: .summary,
            destinationClass: .inProcessResponse
        )

        let decision = await fixture.manager.checkAuthorization(
            context(fixture: fixture, request: request)
        )

        XCTAssertFalse(decision.isAuthorized)
        XCTAssertEqual(decision.reasonCode, .profilePolicyDigestMismatch)
    }

    func testCachedMacQueryDoesNotPretendToInspectHealthKitAuthorization() async throws {
        let fixture = try await makeFixture()
        let request = makeRequest(fixture: fixture)
        let authorization = AgentAuthorizationContext(
            request: request,
            grantID: fixture.grant.id,
            profilePolicy: fixture.policy,
            healthKitAuthorization: AgentHealthKitAuthorizationSnapshot(
                state: .notRequiredForCachedData,
                readableMetrics: .metricIDs([]),
                capturedAt: fixture.now
            )
        )

        let decision = await fixture.manager.checkAuthorization(authorization)

        XCTAssertTrue(decision.isAuthorized)
    }

    func testPauseResumeExpiryAndRevokeLifecycle() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let fixture = try await makeFixture(clock: clock)
        let request = makeRequest(fixture: fixture)
        let authorization = context(fixture: fixture, request: request)

        _ = try await fixture.manager.pauseGrant(fixture.grant.id)
        let pausedDecision = await fixture.manager.checkAuthorization(authorization)
        XCTAssertEqual(pausedDecision.reasonCode, .grantPaused)
        _ = try await fixture.manager.resumeGrant(fixture.grant.id)
        let resumedDecision = await fixture.manager.checkAuthorization(authorization)
        XCTAssertTrue(resumedDecision.isAuthorized)

        let expiringGrant = confirmedGrant(
            clientID: fixture.registration.id,
            profile: fixture.profile,
            now: fixture.now,
            expiresAt: fixture.now.addingTimeInterval(10)
        )
        _ = try await fixture.manager.saveGrant(expiringGrant)
        let expiringContext = AgentAuthorizationContext(
            request: request,
            grantID: expiringGrant.id,
            profilePolicy: fixture.policy,
            healthKitAuthorization: authorizedHealthKit(at: fixture.now)
        )
        clock.advance(by: 11)
        let expiredDecision = await fixture.manager.checkAuthorization(expiringContext)
        XCTAssertEqual(expiredDecision.reasonCode, .grantExpired)
        let expiredIDs = try await fixture.manager.expireEligibleGrants()
        XCTAssertEqual(expiredIDs, [expiringGrant.id])

        _ = try await fixture.manager.revokeGrant(fixture.grant.id)
        let revokedDecision = await fixture.manager.checkAuthorization(authorization)
        XCTAssertEqual(revokedDecision.reasonCode, .grantRevoked)
    }

    func testPendingGrantRequiresExplicitConfirmation() async throws {
        let fixture = try await makeFixture()
        let pending = AgentAccessGrant(
            clientRegistrationID: fixture.registration.id,
            profileReference: fixture.profile,
            createdAt: fixture.now,
            operations: .allOperations,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevels: .allDetailLevels,
            destinationClasses: .allDestinationClasses
        )
        _ = try await fixture.manager.saveGrant(pending)
        let request = makeRequest(fixture: fixture)
        let pendingContext = AgentAuthorizationContext(
            request: request,
            grantID: pending.id,
            profilePolicy: fixture.policy,
            healthKitAuthorization: authorizedHealthKit(at: fixture.now)
        )

        let pendingDecision = await fixture.manager.checkAuthorization(pendingContext)
        XCTAssertEqual(pendingDecision.reasonCode, .grantNotConfirmed)
        _ = try await fixture.manager.confirmGrant(pending.id)
        let confirmedDecision = await fixture.manager.checkAuthorization(pendingContext)
        XCTAssertTrue(confirmedDecision.isAuthorized)
    }

    func testClearActivityHistoryDoesNotRevokeGrant() async throws {
        let fixture = try await makeFixture()
        let request = makeRequest(fixture: fixture)
        let authorization = context(fixture: fixture, request: request)
        let initialDecision = try await fixture.manager.authorize(authorization)
        let initialHistory = await fixture.manager.activityHistory()
        XCTAssertTrue(initialDecision.isAuthorized)
        XCTAssertEqual(initialHistory.count, 1)

        try await fixture.manager.clearActivityHistory()

        let clearedHistory = await fixture.manager.activityHistory()
        let retainedGrant = await fixture.manager.grant(id: fixture.grant.id)
        let finalDecision = await fixture.manager.checkAuthorization(authorization)
        XCTAssertTrue(clearedHistory.isEmpty)
        XCTAssertEqual(retainedGrant?.status(at: fixture.now), .active)
        XCTAssertTrue(finalDecision.isAuthorized)
    }

    func testActivityRetentionByCountAgeAndStorage() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let directory = try temporaryDirectory()
        let manager = AgentAccessManager(
            directoryURL: directory,
            clock: { clock.now },
            retentionPolicy: AgentActivityRetentionPolicy(maximumAge: 5, maximumRecordCount: 2, maximumStorageBytes: 1_000_000)
        )
        let request = standaloneLegacyRequest()
        _ = try await manager.recordActivity(for: request, grantID: nil, resultRecordCount: 1, resultByteCount: 2, outcome: .denied, reasonCode: .legacyUnattributedClient)
        clock.advance(by: 1)
        _ = try await manager.recordActivity(for: request, grantID: nil, resultRecordCount: 2, resultByteCount: 3, outcome: .denied, reasonCode: .legacyUnattributedClient)
        clock.advance(by: 1)
        _ = try await manager.recordActivity(for: request, grantID: nil, resultRecordCount: 3, resultByteCount: 4, outcome: .denied, reasonCode: .legacyUnattributedClient)
        let countRetained = await manager.activityHistory().map(\.resultRecordCount)
        XCTAssertEqual(countRetained, [3, 2])

        clock.advance(by: 10)
        _ = try await manager.recordActivity(for: request, grantID: nil, resultRecordCount: 4, resultByteCount: 5, outcome: .denied, reasonCode: .legacyUnattributedClient)
        let ageRetained = await manager.activityHistory().map(\.resultRecordCount)
        XCTAssertEqual(ageRetained, [4])

        let tinyManager = AgentAccessManager(
            directoryURL: try temporaryDirectory(),
            clock: { clock.now },
            retentionPolicy: AgentActivityRetentionPolicy(maximumAge: 100, maximumRecordCount: 10, maximumStorageBytes: 1)
        )
        _ = try await tinyManager.recordActivity(for: request, grantID: nil, resultRecordCount: 1, resultByteCount: 1, outcome: .denied, reasonCode: .legacyUnattributedClient)
        let storageRetained = await tinyManager.activityHistory()
        XCTAssertTrue(storageRetained.isEmpty)
    }

    func testCorruptAccessStoreFailsClosedWithStableReason() async throws {
        let directory = try temporaryDirectory()
        try Data("not-json".utf8).write(to: directory.appendingPathComponent(AgentAccessManager.accessStoreFilename))
        let manager = AgentAccessManager(directoryURL: directory)
        let request = standaloneLegacyRequest()
        let profile = request.profileReference
        let context = AgentAuthorizationContext(
            request: request,
            grantID: UUID(),
            profilePolicy: unlimitedPolicy(profile: profile),
            healthKitAuthorization: authorizedHealthKit(at: Date())
        )

        let storeStatus = await manager.accessStoreStatus()
        let decision = await manager.checkAuthorization(context)
        XCTAssertEqual(storeStatus, .corrupt)
        XCTAssertEqual(decision.reasonCode, .accessStoreCorrupt)
    }

    func testCorruptActivityStoreDeniesAuditedAuthorizationUntilIndependentClear() async throws {
        let directory = try temporaryDirectory()
        let fixture = try await makeFixture(directory: directory)
        try Data("corrupt".utf8).write(
            to: directory.appendingPathComponent(AgentAccessManager.activityStoreFilename),
            options: .atomic
        )
        let reloaded = AgentAccessManager(directoryURL: directory)
        let authorization = AgentAuthorizationContext(
            request: makeRequest(fixture: fixture),
            grantID: fixture.grant.id,
            profilePolicy: fixture.policy,
            healthKitAuthorization: authorizedHealthKit(at: fixture.now)
        )

        let corruptStatus = await reloaded.activityStoreStatus()
        let unavailableDecision = try await reloaded.authorize(authorization)
        XCTAssertEqual(corruptStatus, .corrupt)
        XCTAssertEqual(unavailableDecision.reasonCode, .activityHistoryUnavailable)
        try await reloaded.clearActivityHistory()
        let repairedDecision = try await reloaded.authorize(authorization)
        XCTAssertTrue(repairedDecision.isAuthorized)
    }

    func testCredentialNeverSerializesIntoCodableStores() async throws {
        let directory = try temporaryDirectory()
        let credentialStore = MemoryCredentialStore()
        let _: AgentCredentialStoring = SystemAgentCredentialStore(service: "com.test.agent-access")
        let manager = AgentAccessManager(directoryURL: directory, credentialStore: credentialStore)
        let secret = "CREDENTIAL_SENTINEL_DO_NOT_SERIALIZE"
        let registration = try await manager.registerClient(
            displayName: "Research agent",
            kind: .localAgent,
            credential: Data(secret.utf8)
        )
        let profile = testProfileReference(revision: 1)
        _ = try await manager.saveGrant(confirmedGrant(clientID: registration.id, profile: profile, now: Date()))
        _ = try await manager.recordActivity(
            for: AgentAccessRequest(
                clientIdentity: .registered(registration.id),
                profileReference: profile,
                operation: .readHealthData,
                dateScope: .allHistory,
                metricScope: .allAvailable,
                detailLevel: .losslessRecords,
                destinationClass: .apiEndpoint
            ),
            grantID: nil,
            resultRecordCount: 0,
            resultByteCount: 0,
            outcome: .authorized
        )

        let accessJSON = try String(contentsOf: directory.appendingPathComponent(AgentAccessManager.accessStoreFilename), encoding: .utf8)
        let activityJSON = try String(contentsOf: directory.appendingPathComponent(AgentAccessManager.activityStoreFilename), encoding: .utf8)
        XCTAssertFalse(accessJSON.contains(secret))
        XCTAssertFalse(activityJSON.contains(secret))
        XCTAssertFalse(accessJSON.lowercased().contains("credential"))
        XCTAssertFalse(activityJSON.lowercased().contains("credential"))
        let accessPermissions = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent(AgentAccessManager.accessStoreFilename).path
        )[.posixPermissions] as? NSNumber
        let activityPermissions = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent(AgentAccessManager.activityStoreFilename).path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(accessPermissions.map { $0.intValue & 0o777 }, 0o600)
        XCTAssertEqual(activityPermissions.map { $0.intValue & 0o777 }, 0o600)
        let storedCredential = try await manager.credential(for: registration.id)
        XCTAssertEqual(storedCredential, Data(secret.utf8))
    }

    func testAuditStoresExactScopeCountsOutcomeAndCorrelation() async throws {
        let directory = try temporaryDirectory()
        let fixture = try await makeFixture(directory: directory)
        let start = fixture.now.addingTimeInterval(-123_456.789)
        let end = fixture.now.addingTimeInterval(-42.123)
        let correlationID = UUID()
        let request = AgentAccessRequest(
            clientIdentity: .registered(fixture.registration.id),
            profileReference: fixture.profile,
            operation: .streamHealthData,
            dateScope: .exact(start: start, end: end),
            metricScope: .metricIDs(["heart_rate", "steps"]),
            detailLevel: .losslessRecords,
            destinationClass: .connectedDevice,
            correlationID: correlationID
        )

        let record = try await fixture.manager.recordActivity(
            for: request,
            grantID: fixture.grant.id,
            resultRecordCount: 4_321,
            resultByteCount: 987_654,
            outcome: .succeeded
        )

        XCTAssertEqual(record.dateScope, request.dateScope)
        XCTAssertEqual(record.metricScope, request.metricScope)
        XCTAssertEqual(record.detailLevel, .losslessRecords)
        XCTAssertEqual(record.destinationClass, .connectedDevice)
        XCTAssertEqual(record.resultRecordCount, 4_321)
        XCTAssertEqual(record.resultByteCount, 987_654)
        XCTAssertEqual(record.outcome, .succeeded)
        XCTAssertEqual(record.correlationID, correlationID)

        let reloaded = AgentAccessManager(directoryURL: directory)
        let reloadedHistory = await reloaded.activityHistory()
        let persisted = try XCTUnwrap(reloadedHistory.first)
        XCTAssertEqual(persisted.dateScope, request.dateScope)
        XCTAssertEqual(persisted.metricScope, request.metricScope)
        XCTAssertEqual(persisted.correlationID, correlationID)

        let activityData = try Data(contentsOf: directory.appendingPathComponent(AgentAccessManager.activityStoreFilename))
        let envelope = try JSONSerialization.jsonObject(with: activityData) as? [String: Any]
        XCTAssertEqual(envelope?["version"] as? Int, AgentActivityStoreEnvelope.currentVersion)
    }

    func testActivityJSONHasNoForbiddenFieldsOrPHISentinels() async throws {
        let directory = try temporaryDirectory()
        let fixture = try await makeFixture(directory: directory)
        let request = makeRequest(fixture: fixture)
        _ = try await fixture.manager.recordActivity(
            for: request,
            grantID: fixture.grant.id,
            resultRecordCount: 1,
            resultByteCount: 8,
            outcome: .succeeded
        )
        let data = try Data(contentsOf: directory.appendingPathComponent(AgentAccessManager.activityStoreFilename))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = allKeys(in: object)
        let forbiddenKeys: Set<String> = [
            "value", "values", "prompt", "filename", "file_name", "path", "url",
            "endpoint_url", "peer_name", "credential", "credentials", "response_body", "body"
        ]

        XCTAssertTrue(keys.isDisjoint(with: forbiddenKeys), "Unexpected activity keys: \(keys.intersection(forbiddenKeys))")
        let json = String(decoding: data, as: UTF8.self)
        for sentinel in ["PHI_VALUE_SENTINEL", "/Users/private/Vault", "https://secret.example", "PEER_SENTINEL", "PROMPT_SENTINEL"] {
            XCTAssertFalse(json.contains(sentinel))
        }
    }

    func testLegacyLoopbackIsHonestlyUnattributedAndDeniedAsAuthenticatedClient() async throws {
        let fixture = try await makeFixture()
        let request = AgentAccessRequest(
            clientIdentity: .legacyUnattributedLocalProcess,
            profileReference: fixture.profile,
            operation: .readHealthData,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevel: .summary,
            destinationClass: .loopbackResponse
        )
        let decision = await fixture.manager.checkAuthorization(context(fixture: fixture, request: request))
        XCTAssertEqual(decision.reasonCode, .legacyUnattributedClient)

        let activity = try await fixture.manager.recordActivity(
            for: request,
            grantID: nil,
            resultRecordCount: 0,
            resultByteCount: 0,
            outcome: .denied,
            reasonCode: .legacyUnattributedClient
        )
        XCTAssertEqual(activity.clientIdentity, .legacyUnattributedLocalProcess)
        XCTAssertNil(activity.clientIdentity.registrationID)
    }

    func testConcurrentActivityRecordingLosesNoRecords() async throws {
        let directory = try temporaryDirectory()
        let manager = AgentAccessManager(
            directoryURL: directory,
            retentionPolicy: AgentActivityRetentionPolicy(maximumAge: 1000, maximumRecordCount: 100, maximumStorageBytes: 1_000_000)
        )
        let request = standaloneLegacyRequest()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    _ = try await manager.recordActivity(
                        for: request,
                        grantID: nil,
                        resultRecordCount: index,
                        resultByteCount: index,
                        outcome: .denied,
                        reasonCode: .legacyUnattributedClient
                    )
                }
            }
            try await group.waitForAll()
        }

        let history = await manager.activityHistory()
        XCTAssertEqual(history.count, 40)
    }

    // MARK: - Helpers

    private struct Fixture {
        let manager: AgentAccessManager
        let registration: AgentClientRegistration
        let profile: HealthContextProfileReference
        let grant: AgentAccessGrant
        let policy: HealthContextProfileEffectivePolicy
        let now: Date
    }

    private func makeFixture(
        directory: URL? = nil,
        clock: TestClock? = nil,
        operations: AgentOperationScope = .allOperations,
        dateScope: AgentDateScope = .allHistory,
        metricScope: AgentMetricScope = .allAvailable,
        detailLevels: AgentDetailScope = .allDetailLevels,
        destinations: AgentDestinationScope = .allDestinationClasses,
        resourceControls: AgentResourceControls? = nil
    ) async throws -> Fixture {
        let testClock = clock ?? TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let manager = AgentAccessManager(
            directoryURL: try directory ?? temporaryDirectory(),
            clock: { testClock.now }
        )
        let registration = try await manager.registerClient(displayName: "Test agent", kind: .localAgent)
        let profile = testProfileReference(revision: 7)
        let grant = AgentAccessGrant(
            clientRegistrationID: registration.id,
            profileReference: profile,
            createdAt: testClock.now,
            confirmationState: .userConfirmed,
            confirmedAt: testClock.now,
            operations: operations,
            dateScope: dateScope,
            metricScope: metricScope,
            detailLevels: detailLevels,
            destinationClasses: destinations,
            resourceControls: resourceControls
        )
        _ = try await manager.saveGrant(grant)
        let policy = HealthContextProfileEffectivePolicy(
            reference: profile,
            operations: .allOperations,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevels: .allDetailLevels,
            destinationClasses: .allDestinationClasses
        )
        return Fixture(
            manager: manager,
            registration: registration,
            profile: profile,
            grant: grant,
            policy: policy,
            now: testClock.now
        )
    }

    private func makeRequest(
        fixture: Fixture,
        dateScope: AgentDateScope = .allHistory,
        metricScope: AgentMetricScope = .allAvailable,
        detail: AgentDetailLevel = .summary,
        destination: AgentDestinationClass = .inProcessResponse
    ) -> AgentAccessRequest {
        AgentAccessRequest(
            clientIdentity: .registered(fixture.registration.id),
            profileReference: fixture.profile,
            operation: .readHealthData,
            dateScope: dateScope,
            metricScope: metricScope,
            detailLevel: detail,
            destinationClass: destination
        )
    }

    private func context(fixture: Fixture, request: AgentAccessRequest) -> AgentAuthorizationContext {
        AgentAuthorizationContext(
            request: request,
            grantID: fixture.grant.id,
            profilePolicy: fixture.policy,
            healthKitAuthorization: authorizedHealthKit(at: fixture.now)
        )
    }

    private static func authorizedHealthKit(at date: Date) -> AgentHealthKitAuthorizationSnapshot {
        AgentHealthKitAuthorizationSnapshot(state: .authorized, readableMetrics: .allAvailable, capturedAt: date)
    }

    private func authorizedHealthKit(at date: Date) -> AgentHealthKitAuthorizationSnapshot {
        Self.authorizedHealthKit(at: date)
    }

    private static func unlimitedPolicy(profile: HealthContextProfileReference) -> HealthContextProfileEffectivePolicy {
        HealthContextProfileEffectivePolicy(
            reference: profile,
            operations: .allOperations,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevels: .allDetailLevels,
            destinationClasses: .allDestinationClasses
        )
    }

    private func unlimitedPolicy(profile: HealthContextProfileReference) -> HealthContextProfileEffectivePolicy {
        Self.unlimitedPolicy(profile: profile)
    }

    private func confirmedGrant(
        clientID: UUID,
        profile: HealthContextProfileReference,
        now: Date,
        expiresAt: Date? = nil
    ) -> AgentAccessGrant {
        AgentAccessGrant(
            clientRegistrationID: clientID,
            profileReference: profile,
            createdAt: now,
            confirmationState: .userConfirmed,
            confirmedAt: now,
            operations: .allOperations,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevels: .allDetailLevels,
            destinationClasses: .allDestinationClasses,
            expiresAt: expiresAt
        )
    }

    private func standaloneLegacyRequest() -> AgentAccessRequest {
        AgentAccessRequest(
            clientIdentity: .legacyUnattributedLocalProcess,
            profileReference: testProfileReference(revision: 1),
            operation: .readHealthData,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevel: .summary,
            destinationClass: .loopbackResponse
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentAccessManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func allKeys(in value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            return Set(dictionary.keys).union(dictionary.values.reduce(into: Set<String>()) { result, child in
                result.formUnion(allKeys(in: child))
            })
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { result, child in
                result.formUnion(allKeys(in: child))
            }
        }
        return []
    }
}

private nonisolated func testProfileReference(
    id: UUID = UUID(),
    revision: Int
) -> HealthContextProfileReference {
    HealthContextProfileReference(
        profileID: id,
        revision: .init(revision),
        policyDigest: String(repeating: "a", count: 64)
    )
}

private nonisolated final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private nonisolated final class MemoryCredentialStore: AgentCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Data] = [:]

    func credential(for registrationID: UUID) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[registrationID]
    }

    func storeCredential(_ credential: Data, for registrationID: UUID) throws {
        lock.lock()
        values[registrationID] = credential
        lock.unlock()
    }

    func removeCredential(for registrationID: UUID) throws {
        lock.lock()
        values.removeValue(forKey: registrationID)
        lock.unlock()
    }
}
