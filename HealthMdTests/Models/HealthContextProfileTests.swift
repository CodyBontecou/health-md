import Foundation
import XCTest
@testable import HealthMd

final class HealthContextProfileTests: XCTestCase {
    private let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testProfileAndReferenceRoundTripAllPolicyVariants() throws {
        let profile = makeProfile(
            metricScope: .selected(metricIDs: ["steps", "heart_rate_avg"]),
            dataSourceScope: .selected(sourceIDs: ["healthkit", "whoop"]),
            detailLevel: .lossless,
            datePolicy: .relative(duration: 10 * 365 * 24 * 60 * 60),
            confirmationRequirement: .required,
            expiresAt: now.addingTimeInterval(60),
            destinationBinding: .exact(destinationID: "vault:primary")
        )
        let reference = try profile.reference()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(HealthContextProfile.self, from: encoder.encode(profile)),
            profile
        )
        XCTAssertEqual(
            try decoder.decode(HealthContextProfileReference.self, from: encoder.encode(reference)),
            reference
        )
        let profileJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(profile)) as? [String: Any]
        )
        XCTAssertEqual(profileJSON["schema"] as? String, HealthContextProfileSchema.identifier)
        XCTAssertEqual(profileJSON["schema_version"] as? Int, 1)
        XCTAssertEqual(profileJSON["revision"] as? Int, profile.revision.rawValue)
        XCTAssertNil(profileJSON["schemaIdentifier"])
        let referenceJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(reference)) as? [String: Any]
        )
        XCTAssertEqual(referenceJSON["profile_id"] as? String, reference.profileID.uuidString)
        XCTAssertEqual(referenceJSON["policy_digest"] as? String, reference.policyDigest)
    }

    func testPolicyDigestIsDeterministicAndCanonicalizesSetLikeOrder() throws {
        let first = makeProfile(
            revision: .init(1),
            name: "First display name",
            metricScope: .selected(metricIDs: ["steps", "weight", "workouts"]),
            dataSourceScope: .selected(sourceIDs: ["whoop", "healthkit"]),
            allowedCallers: [.commandLine, .interactiveUser],
            allowedSurfaces: [.commandLine, .iOSApp]
        )
        let second = HealthContextProfile(
            id: UUID(),
            revision: .init(99),
            name: "Unrelated renamed profile",
            metricScope: .selected(metricIDs: ["workouts", "steps", "weight"]),
            dataSourceScope: .selected(sourceIDs: ["healthkit", "whoop"]),
            detailLevel: first.detailLevel,
            datePolicy: first.datePolicy,
            allowedCallers: [.interactiveUser, .commandLine],
            allowedSurfaces: [.iOSApp, .commandLine],
            confirmationRequirement: first.confirmationRequirement,
            expiresAt: first.expiresAt,
            destinationBinding: first.destinationBinding,
            createdAt: now.addingTimeInterval(-999),
            updatedAt: now.addingTimeInterval(-500)
        )

        XCTAssertEqual(try first.policyDigest(), try second.policyDigest())
        XCTAssertEqual(try first.policyDigest().count, 64)
    }

    func testAllAvailableLosslessAllHistoryResolvesEveryRuntimeMetricAndSource() throws {
        let profile = makeProfile(
            metricScope: .allAvailable,
            dataSourceScope: .allAvailable,
            detailLevel: .lossless,
            datePolicy: .allHistory
        )
        let metrics = (0..<5_000).map { "metric_\($0)" } + ["future_metric"]
        let sources = (0..<1_000).map { "provider_\($0)" } + ["future_provider"]

        let policy = try resolve(profile, metrics: metrics, sources: sources)

        XCTAssertEqual(Set(policy.request.metricIDs), Set(metrics))
        XCTAssertEqual(Set(policy.request.sourceIDs), Set(sources))
        XCTAssertEqual(policy.request.detailLevel, .lossless)
        XCTAssertEqual(policy.request.dates, .allHistory)
        XCTAssertEqual(policy.profileID, profile.id)
        XCTAssertEqual(policy.revision, profile.revision)
        XCTAssertEqual(policy.policyDigest, try profile.policyDigest())
    }

    func testSelectedMetricAndSourceScopesRemainFrozenWhenCatalogExpands() throws {
        let profile = makeProfile(
            metricScope: .selected(metricIDs: ["steps", "weight"]),
            dataSourceScope: .selected(sourceIDs: ["healthkit"])
        )

        let first = try resolve(profile, metrics: ["steps", "weight"], sources: ["healthkit"])
        let expanded = try resolve(
            profile,
            metrics: ["future_metric", "steps", "weight"],
            sources: ["future_provider", "healthkit"]
        )

        XCTAssertEqual(first.request.metricIDs, ["steps", "weight"])
        XCTAssertEqual(expanded.request.metricIDs, first.request.metricIDs)
        XCTAssertEqual(expanded.request.sourceIDs, ["healthkit"])
    }

    func testExpiredProfileIsPreservedByStoreButDeniedByResolver() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = makeProfile(expiresAt: now.addingTimeInterval(-1))
        let store = HealthContextProfileStore(rootURL: root)
        try await store.upsert(profile)

        let storedProfiles = try await store.loadProfiles()
        XCTAssertEqual(storedProfiles, [profile])
        XCTAssertThrowsError(try resolve(profile)) { error in
            XCTAssertEqual(error as? HealthContextProfileResolutionError, .expired)
        }
    }

    func testDestinationMismatchFailsClosed() throws {
        let profile = makeProfile(
            destinationBinding: .exact(destinationID: "vault:approved")
        )

        XCTAssertThrowsError(
            try resolve(profile, destinationID: "vault:other")
        ) { error in
            XCTAssertEqual(error as? HealthContextProfileResolutionError, .destinationMismatch)
        }
    }

    func testRevisionAndDigestMismatchesFailClosed() throws {
        let profile = makeProfile()
        let correct = try profile.reference()
        let staleRevision = HealthContextProfileReference(
            profileID: profile.id,
            revision: .init(profile.revision.rawValue - 1),
            policyDigest: correct.policyDigest
        )
        XCTAssertThrowsError(try resolve(profile, reference: staleRevision)) { error in
            XCTAssertEqual(error as? HealthContextProfileResolutionError, .revisionMismatch)
        }

        let wrongDigest = HealthContextProfileReference(
            profileID: profile.id,
            revision: profile.revision,
            policyDigest: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try resolve(profile, reference: wrongDigest)) { error in
            XCTAssertEqual(error as? HealthContextProfileResolutionError, .policyDigestMismatch)
        }
    }

    func testUnknownSchemaCallerAndSurfaceRemainDecodableAndFailExecution() throws {
        let unknownCaller = HealthContextCaller(rawValue: "future_caller")
        let unknownSurface = HealthContextSurface(rawValue: "future_surface")
        let futureProfile = makeProfile(
            schemaVersion: HealthContextProfileSchema.version + 1,
            allowedCallers: [unknownCaller],
            allowedSurfaces: [unknownSurface]
        )
        let roundTripped = try JSONDecoder().decode(
            HealthContextProfile.self,
            from: JSONEncoder().encode(futureProfile)
        )
        XCTAssertEqual(roundTripped.schemaVersion, HealthContextProfileSchema.version + 1)
        XCTAssertEqual(roundTripped.allowedCallers, [unknownCaller])
        XCTAssertEqual(roundTripped.allowedSurfaces, [unknownSurface])

        let reference = HealthContextProfileReference(
            schemaVersion: futureProfile.schemaVersion,
            profileID: futureProfile.id,
            revision: futureProfile.revision,
            policyDigest: try futureProfile.policyDigest()
        )
        XCTAssertThrowsError(try resolve(futureProfile, reference: reference)) { error in
            XCTAssertEqual(
                error as? HealthContextProfileResolutionError,
                .invalidProfile(.unsupportedSchemaVersion)
            )
        }

        let unknownCallerProfile = makeProfile(allowedCallers: [unknownCaller])
        let unknownCallerReference = HealthContextProfileReference(
            profileID: unknownCallerProfile.id,
            revision: unknownCallerProfile.revision,
            policyDigest: try unknownCallerProfile.policyDigest()
        )
        XCTAssertThrowsError(try resolve(unknownCallerProfile, reference: unknownCallerReference)) { error in
            XCTAssertEqual(
                error as? HealthContextProfileResolutionError,
                .invalidProfile(.unknownCaller)
            )
        }

        let unknownSurfaceProfile = makeProfile(allowedSurfaces: [unknownSurface])
        let unknownSurfaceReference = HealthContextProfileReference(
            profileID: unknownSurfaceProfile.id,
            revision: unknownSurfaceProfile.revision,
            policyDigest: try unknownSurfaceProfile.policyDigest()
        )
        XCTAssertThrowsError(try resolve(unknownSurfaceProfile, reference: unknownSurfaceReference)) { error in
            XCTAssertEqual(
                error as? HealthContextProfileResolutionError,
                .invalidProfile(.unknownSurface)
            )
        }

        let validProfile = makeProfile()
        XCTAssertThrowsError(try resolve(validProfile, caller: unknownCaller)) { error in
            XCTAssertEqual(error as? HealthContextProfileResolutionError, .unknownCaller)
        }
        XCTAssertThrowsError(try resolve(validProfile, surface: unknownSurface)) { error in
            XCTAssertEqual(error as? HealthContextProfileResolutionError, .unknownSurface)
        }
    }

    func testCorruptAndUnsupportedStoresFailClosedAndCannotBeOverwrittenByUpsert() async throws {
        let corruptRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: corruptRoot) }
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corruptStore = HealthContextProfileStore(rootURL: corruptRoot)
        try Data("not-json".utf8).write(to: corruptStore.storageURL)

        do {
            _ = try await corruptStore.loadProfiles()
            XCTFail("Expected corrupt store failure")
        } catch {
            XCTAssertEqual(error as? HealthContextProfileStoreError, .corruptStore)
        }
        do {
            try await corruptStore.upsert(makeProfile())
            XCTFail("A corrupt store must not be silently reset")
        } catch {
            XCTAssertEqual(error as? HealthContextProfileStoreError, .corruptStore)
        }

        let unsupportedRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: unsupportedRoot) }
        try FileManager.default.createDirectory(at: unsupportedRoot, withIntermediateDirectories: true)
        let unsupportedStore = HealthContextProfileStore(rootURL: unsupportedRoot)
        let payload = """
        {"schemaIdentifier":"healthmd.health_context_profile_store","schemaVersion":999,"profiles":[]}
        """
        try Data(payload.utf8).write(to: unsupportedStore.storageURL)
        do {
            _ = try await unsupportedStore.loadProfiles()
            XCTFail("Expected unsupported schema failure")
        } catch {
            XCTAssertEqual(error as? HealthContextProfileStoreError, .unsupportedStoreSchema)
        }
    }

    func testStoreAtomicallyReplacesCompleteSortedJSONDocument() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HealthContextProfileStore(rootURL: root)
        let first = makeProfile(revision: .init(1), name: "First")
        let second = makeProfile(revision: .init(2), name: "Second")

        try await store.upsert(first)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: store.storageURL)))
        try await store.upsert(second)

        let storedProfiles = try await store.loadProfiles()
        XCTAssertEqual(storedProfiles, [second])
        let data = try Data(contentsOf: store.storageURL)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        let hiddenFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(hiddenFiles.isEmpty, "Atomic replacement must not leave partial files")
    }

    func testNoArtificialSelectedMetricOrHistoricalDateLimits() throws {
        let metrics = (0..<20_000).map { "selected_metric_\($0)" }
        let range = HealthContextBoundedDateRange(
            start: Date(timeIntervalSince1970: -5_364_662_400), // 1800-01-01
            end: Date(timeIntervalSince1970: 19_874_534_400) // 2600-01-01
        )
        let profile = makeProfile(
            metricScope: .selected(metricIDs: metrics),
            datePolicy: .explicit(range)
        )

        let policy = try resolve(profile, metrics: metrics)

        XCTAssertEqual(policy.request.metricIDs.count, metrics.count)
        XCTAssertEqual(policy.request.dates, .bounded(range))
    }

    func testCallerProvidedAndRelativeDatesResolveToExactBoundedRequests() throws {
        let requested = HealthContextBoundedDateRange(
            start: now.addingTimeInterval(-50 * 365 * 24 * 60 * 60),
            end: now
        )
        let callerProvided = makeProfile(datePolicy: .callerProvided)
        let callerPolicy = try resolve(callerProvided, dateRequest: .bounded(requested))
        XCTAssertEqual(callerPolicy.request.dates, .bounded(requested))

        let duration: TimeInterval = 100 * 365 * 24 * 60 * 60
        let relative = makeProfile(datePolicy: .relative(duration: duration))
        let relativePolicy = try resolve(relative)
        XCTAssertEqual(
            relativePolicy.request.dates,
            .bounded(.init(start: now.addingTimeInterval(-duration), end: now))
        )
    }

    func testConfirmationIsPartOfAuthorization() throws {
        let profile = makeProfile(confirmationRequirement: .required)
        XCTAssertThrowsError(try resolve(profile)) { error in
            XCTAssertEqual(error as? HealthContextProfileResolutionError, .confirmationRequired)
        }
        XCTAssertNoThrow(try resolve(profile, confirmationProvided: true))
    }

    func testRegisteredAgentCanResolveMCPStdioSurface() throws {
        let profile = makeProfile(
            allowedCallers: [.registeredAgent],
            allowedSurfaces: [.mcpStdio]
        )

        let policy = try resolve(
            profile,
            caller: .registeredAgent,
            surface: .mcpStdio
        )

        XCTAssertEqual(policy.caller, .registeredAgent)
        XCTAssertEqual(policy.surface, .mcpStdio)
    }

    private func makeProfile(
        schemaVersion: Int = HealthContextProfileSchema.version,
        revision: HealthContextProfileRevision = .init(7),
        name: String = "Research context",
        metricScope: HealthContextMetricScope = .selected(metricIDs: ["steps"]),
        dataSourceScope: HealthContextDataSourceScope = .selected(sourceIDs: ["healthkit"]),
        detailLevel: HealthContextDetailLevel = .summary,
        datePolicy: HealthContextDatePolicy = .allHistory,
        allowedCallers: [HealthContextCaller] = [.commandLine],
        allowedSurfaces: [HealthContextSurface] = [.commandLine],
        confirmationRequirement: HealthContextConfirmationRequirement = .notRequired,
        expiresAt: Date? = nil,
        destinationBinding: HealthContextDestinationBinding = .any
    ) -> HealthContextProfile {
        HealthContextProfile(
            schemaVersion: schemaVersion,
            id: profileID,
            revision: revision,
            name: name,
            metricScope: metricScope,
            dataSourceScope: dataSourceScope,
            detailLevel: detailLevel,
            datePolicy: datePolicy,
            allowedCallers: allowedCallers,
            allowedSurfaces: allowedSurfaces,
            confirmationRequirement: confirmationRequirement,
            expiresAt: expiresAt,
            destinationBinding: destinationBinding,
            createdAt: now.addingTimeInterval(-1_000),
            updatedAt: now.addingTimeInterval(-500)
        )
    }

    private func resolve(
        _ profile: HealthContextProfile,
        reference: HealthContextProfileReference? = nil,
        caller: HealthContextCaller = .commandLine,
        surface: HealthContextSurface = .commandLine,
        destinationID: String = "vault:primary",
        dateRequest: HealthContextDateRequest? = nil,
        confirmationProvided: Bool = false,
        metrics: [String] = ["steps"],
        sources: [String] = ["healthkit"]
    ) throws -> HealthContextExecutionPolicy {
        try HealthContextProfileResolver.resolve(
            profile: profile,
            reference: reference ?? profile.reference(),
            request: HealthContextProfileResolutionRequest(
                caller: caller,
                surface: surface,
                destinationID: destinationID,
                dateRequest: dateRequest,
                confirmationProvided: confirmationProvided
            ),
            availableMetricIDs: metrics,
            availableSourceIDs: sources,
            now: now
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("health-context-profile-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
