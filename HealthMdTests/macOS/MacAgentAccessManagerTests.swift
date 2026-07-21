import XCTest
@testable import HealthMd

#if os(macOS)
final class MacAgentAccessManagerTests: XCTestCase {
    @MainActor
    func testRandomCredentialIssuanceAndRotationReplaceKeychainValue() async throws {
        let fixture = try makeFixture(randomValues: [
            Data(repeating: 0x11, count: 32),
            Data(repeating: 0x22, count: 32),
        ])
        let registration = try await fixture.bridge.registerLocalAgent(displayName: "Local research agent")
        let issued = try XCTUnwrap(fixture.bridge.credentialReveal?.credential)

        let issuedParts = try XCTUnwrap(MacAgentAccessManager.parseExternalCredential(issued))
        XCTAssertEqual(issuedParts.registrationID, registration.id)
        XCTAssertEqual(
            try fixture.credentials.credential(for: registration.id),
            Data(issuedParts.secret.utf8)
        )
        let authenticated = await fixture.bridge.authenticateExternalCredential(issued)
        XCTAssertEqual(authenticated?.id, registration.id)

        fixture.bridge.dismissCredentialReveal()
        await XCTAssertNoThrowAsync {
            try await fixture.bridge.rotateCredential(for: registration.id)
        }
        let rotated = try XCTUnwrap(fixture.bridge.credentialReveal?.credential)

        XCTAssertNotEqual(issued, rotated)
        let rotatedParts = try XCTUnwrap(MacAgentAccessManager.parseExternalCredential(rotated))
        XCTAssertEqual(rotatedParts.registrationID, registration.id)
        XCTAssertEqual(
            try fixture.credentials.credential(for: registration.id),
            Data(rotatedParts.secret.utf8)
        )
        let staleAuthentication = await fixture.bridge.authenticateExternalCredential(issued)
        let rotatedAuthentication = await fixture.bridge.authenticateExternalCredential(rotated)
        XCTAssertNil(staleAuthentication)
        XCTAssertEqual(rotatedAuthentication?.id, registration.id)
        XCTAssertNil(MacAgentAccessManager.parseExternalCredential("not-a-token"))
    }

    @MainActor
    func testCredentialRevealCanBeConsumedOnlyOnce() async throws {
        let fixture = try makeFixture(randomValues: [Data(repeating: 0x42, count: 32)])
        _ = try await fixture.bridge.registerLocalAgent(displayName: "One-time reveal")
        let visible = try XCTUnwrap(fixture.bridge.credentialReveal?.credential)

        XCTAssertEqual(fixture.bridge.takeCredentialForCopy(), visible)
        XCTAssertNil(fixture.bridge.credentialReveal)
        XCTAssertNil(fixture.bridge.takeCredentialForCopy())

        await fixture.bridge.load()
        XCTAssertNil(fixture.bridge.credentialReveal, "Reloading must never reveal a Keychain credential")
    }

    @MainActor
    func testBroadGrantCannotBeConfirmedWithoutExplicitAcknowledgement() async throws {
        let fixture = try makeFixture(randomValues: [Data(repeating: 0x01, count: 32)])
        let registration = try await fixture.bridge.registerLocalAgent(displayName: "Broad agent")
        let profile = makeProfile(
            metricScope: .allAvailable,
            detailLevel: .lossless,
            datePolicy: .allHistory,
            surfaces: [.commandLine, .localControlAPI, .mcpStdio]
        )
        let grant = try await fixture.bridge.createGrant(for: registration.id, profile: profile)

        XCTAssertTrue(fixture.bridge.requiresBroadScopeConfirmation(grant))
        do {
            try await fixture.bridge.confirmGrant(grant.id, broadScopeAcknowledged: false)
            XCTFail("Broad grant confirmation should require explicit acknowledgement")
        } catch let error as AgentAccessManagerError {
            XCTAssertEqual(error.code, .invalidStateTransition)
        }
        XCTAssertEqual(fixture.bridge.grants.first?.status(at: Date()), .pendingConfirmation)

        try await fixture.bridge.confirmGrant(grant.id, broadScopeAcknowledged: true)
        XCTAssertEqual(fixture.bridge.grants.first?.status(at: Date()), .active)
    }

    func testExactProfileRevisionDigestAndScopesMapWithoutWidening() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(12_345)
        let profile = makeProfile(
            revision: 9,
            metricScope: .selected(metricIDs: ["heart_rate", "steps"]),
            detailLevel: .lossless,
            datePolicy: .explicit(.init(start: start, end: end)),
            surfaces: [.mcpStdio]
        )
        let reference = try profile.reference()

        let policy = try HealthContextProfileAgentPolicyMapper.effectivePolicy(
            profile: profile,
            reference: reference
        )

        XCTAssertEqual(policy.reference.revision, .init(9))
        XCTAssertEqual(policy.reference.policyDigest, try profile.policyDigest())
        XCTAssertEqual(policy.metricScope, .metricIDs(["heart_rate", "steps"]))
        XCTAssertEqual(policy.dateScope, .exact(start: start, end: end))
        XCTAssertEqual(policy.detailLevels, .allDetailLevels)
        XCTAssertEqual(policy.operations, .allOperations)
        XCTAssertEqual(policy.destinationClasses, .allDestinationClasses)
    }

    func testUnsupportedCanonicalRestrictionsFailClosed() throws {
        let sourceRestricted = HealthContextProfile(
            name: "Source restricted",
            metricScope: .allAvailable,
            dataSourceScope: .selected(sourceIDs: ["watch"]),
            detailLevel: .summary,
            datePolicy: .allHistory,
            allowedCallers: [.registeredAgent],
            allowedSurfaces: [.mcpStdio]
        )
        XCTAssertThrowsError(try HealthContextProfileAgentPolicyMapper.effectivePolicy(
            profile: sourceRestricted,
            reference: try sourceRestricted.reference()
        )) { error in
            XCTAssertEqual(
                error as? HealthContextProfileAgentPolicyMappingError,
                .unsupportedDataSourceRestriction
            )
        }

        let relative = makeProfile(datePolicy: .relative(duration: 86_400), surfaces: [.mcpStdio])
        XCTAssertThrowsError(try HealthContextProfileAgentPolicyMapper.effectivePolicy(
            profile: relative,
            reference: try relative.reference()
        )) { error in
            XCTAssertEqual(error as? HealthContextProfileAgentPolicyMappingError, .unsupportedDatePolicy)
        }
    }

    @MainActor
    func testPauseResumeAndRevokeAreReflectedImmediatelyByUIBridge() async throws {
        let fixture = try makeFixture(randomValues: [Data(repeating: 0x03, count: 32)])
        let registration = try await fixture.bridge.registerLocalAgent(displayName: "Lifecycle agent")
        let profile = makeProfile(surfaces: [.mcpStdio])
        let grant = try await fixture.bridge.createGrant(for: registration.id, profile: profile)
        try await fixture.bridge.confirmGrant(grant.id, broadScopeAcknowledged: true)

        try await fixture.bridge.pauseGrant(grant.id)
        XCTAssertEqual(fixture.bridge.grants.first?.status(at: Date()), .paused)
        try await fixture.bridge.resumeGrant(grant.id)
        XCTAssertEqual(fixture.bridge.grants.first?.status(at: Date()), .active)
        try await fixture.bridge.revokeGrant(grant.id)
        XCTAssertEqual(fixture.bridge.grants.first?.status(at: Date()), .revoked)

        try await fixture.bridge.revokeRegistration(registration.id)
        XCTAssertEqual(fixture.bridge.registrations.first?.state, .revoked)
        XCTAssertNil(try fixture.credentials.credential(for: registration.id))
    }

    @MainActor
    func testBridgeCredentialAndPHISentinelsNeverSerialize() async throws {
        let fixture = try makeFixture(randomValues: [Data("CREDENTIAL_SENTINEL_32_BYTES!!!!".utf8)])
        let registration = try await fixture.bridge.registerLocalAgent(displayName: "Serialization agent")
        let credential = try XCTUnwrap(fixture.bridge.credentialReveal?.credential)
        let profile = makeProfile(surfaces: [.mcpStdio])
        let grant = try await fixture.bridge.createGrant(for: registration.id, profile: profile)
        let request = AgentAccessRequest(
            clientIdentity: .registered(registration.id),
            profileReference: grant.profileReference,
            operation: .readHealthData,
            dateScope: .allHistory,
            metricScope: .allAvailable,
            detailLevel: .losslessRecords,
            destinationClass: .inProcessResponse
        )
        _ = try await fixture.core.recordActivity(
            for: request,
            grantID: grant.id,
            resultRecordCount: 7,
            resultByteCount: 99,
            outcome: .succeeded
        )
        await fixture.bridge.load()

        let accessData = try Data(contentsOf: fixture.directory.appendingPathComponent(AgentAccessManager.accessStoreFilename))
        let activityData = try Data(contentsOf: fixture.directory.appendingPathComponent(AgentAccessManager.activityStoreFilename))
        let serialized = String(decoding: accessData + activityData, as: UTF8.self)
        XCTAssertFalse(serialized.contains(credential))
        XCTAssertFalse(serialized.lowercased().contains("credential"))
        for sentinel in ["PHI_VALUE_SENTINEL", "PROMPT_SENTINEL", "/Users/private/Vault", "https://secret.example"] {
            XCTAssertFalse(serialized.contains(sentinel))
        }
        XCTAssertEqual(fixture.bridge.activity.count, 1)
    }

    private struct Fixture {
        let directory: URL
        let credentials: BridgeMemoryCredentialStore
        let core: AgentAccessManager
        let bridge: MacAgentAccessManager
    }

    @MainActor
    private func makeFixture(randomValues: [Data]) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAgentAccessManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let credentials = BridgeMemoryCredentialStore()
        let core = AgentAccessManager(directoryURL: directory, credentialStore: credentials)
        let generator = SequentialCredentialGenerator(values: randomValues)
        let bridge = MacAgentAccessManager(
            accessManager: core,
            credentialGenerator: { count in try generator.next(count: count) }
        )
        return Fixture(directory: directory, credentials: credentials, core: core, bridge: bridge)
    }

    private func makeProfile(
        revision: Int = 1,
        metricScope: HealthContextMetricScope = .allAvailable,
        detailLevel: HealthContextDetailLevel = .lossless,
        datePolicy: HealthContextDatePolicy = .allHistory,
        surfaces: [HealthContextSurface]
    ) -> HealthContextProfile {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        return HealthContextProfile(
            revision: .init(revision),
            name: "Agent policy",
            metricScope: metricScope,
            dataSourceScope: .allAvailable,
            detailLevel: detailLevel,
            datePolicy: datePolicy,
            allowedCallers: [.registeredAgent],
            allowedSurfaces: surfaces,
            confirmationRequirement: .required,
            destinationBinding: .any,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
}

private final class BridgeMemoryCredentialStore: AgentCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Data] = [:]

    func credential(for registrationID: UUID) throws -> Data? {
        lock.withLock { values[registrationID] }
    }

    func storeCredential(_ credential: Data, for registrationID: UUID) throws {
        lock.withLock { values[registrationID] = credential }
    }

    func removeCredential(for registrationID: UUID) throws {
        _ = lock.withLock { values.removeValue(forKey: registrationID) }
    }
}

private final class SequentialCredentialGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data]

    init(values: [Data]) { self.values = values }

    func next(count: Int) throws -> Data {
        try lock.withLock {
            guard !values.isEmpty else { throw AgentAccessManagerError(.credentialStorageFailed) }
            let value = values.removeFirst()
            guard value.count == count else { throw AgentAccessManagerError(.credentialStorageFailed) }
            return value
        }
    }
}

private extension XCTestCase {
    func XCTAssertNoThrowAsync(
        _ expression: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
#endif
