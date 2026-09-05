import Combine
import Foundation
import XCTest
@testable import HealthMd

#if os(iOS)
/// Cycle-4 in-flow confirmation coverage for Shared Setup v2: the blocked
/// API-endpoint import can be unblocked inside the review flow only through
/// the injected verified path with a fresh local credential, blocked
/// connected-Mac rows keep their explicit attestation path, and every
/// missing/failing piece surfaces honest unavailability without ever
/// weakening the fail-closed execution gate. Cycle-6 adds the reused-row
/// name-preservation contract: the in-flow endpoint add never renames an
/// existing row the editor's upsert reuses — only a genuinely new row
/// receives the identity-derived display hint.
@MainActor
final class SharedSetupV2ConfirmationFlowTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: MainActor-isolated deinits take the
    // back-deployed task path on older simulator runtimes (CI's iOS 26.2
    // simulator) where nested store release aborts; retain for the process
    // lifetime. See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []
    // STATIC RETENTION JUSTIFICATION: same deinit-crash workaround as above
    // for the nested ObservableObject instances the real-coordinator test
    // constructs (ExportProfileCoordinator + VaultManager).
    private static var retainedInstances: [AnyObject] = []

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SharedSetupV2ConfirmationFlowTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Conservative endpoint identity matching

    func testEndpointIdentityMatchingIsConservative() {
        let imported = "https://api.example.com:8443/v1/health"
        XCTAssertTrue(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com:8443/v1/health",
            matchesImportedURLString: imported
        ))
        // Host and scheme compare case-insensitively.
        XCTAssertTrue(SharedSetupV2EndpointIdentity.localRowURL(
            "HTTPS://API.EXAMPLE.COM:8443/v1/health",
            matchesImportedURLString: imported
        ))
        // Explicitly equal queries still match.
        XCTAssertTrue(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com:8443/v1/health?q=1",
            matchesImportedURLString: "https://api.example.com:8443/v1/health?q=1"
        ))
        // An implicit scheme-default port equals the explicit default port.
        XCTAssertTrue(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com/v1",
            matchesImportedURLString: "https://api.example.com:443/v1"
        ))
        // An empty row path equals the canonical root path.
        XCTAssertTrue(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com",
            matchesImportedURLString: "https://api.example.com/"
        ))

        // Port mismatch.
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com:8444/v1/health",
            matchesImportedURLString: imported
        ))
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com/v1/health",
            matchesImportedURLString: imported
        ))
        // Path mismatch, including a trailing-slash difference.
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com:8443/v1/health/",
            matchesImportedURLString: imported
        ))
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com:8443/v2/health",
            matchesImportedURLString: imported
        ))
        // Host mismatch.
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "https://other.example.com:8443/v1/health",
            matchesImportedURLString: imported
        ))
        // Scheme mismatch, including non-http(s) rows.
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "http://api.example.com:8443/v1/health",
            matchesImportedURLString: imported
        ))
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "ftp://api.example.com:8443/v1/health",
            matchesImportedURLString: imported
        ))
        // A query the imported identity does not retain means no match.
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "https://api.example.com:8443/v1/health?token=1",
            matchesImportedURLString: imported
        ))
        // Unparseable or empty row strings never match.
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "not a url",
            matchesImportedURLString: imported
        ))
        XCTAssertFalse(SharedSetupV2EndpointIdentity.localRowURL(
            "",
            matchesImportedURLString: imported
        ))
    }

    // MARK: - Imported identity resolution

    func testImportedEndpointIdentityRequiresLoadedPlanAndStopsAtFinish() throws {
        let coordinator = makeCoordinator(adapter: nil)
        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))

        let apiReview = SharedSetupV2ImportedProfileReview(
            id: uuid(1),
            sourceBundleID: "profile-003",
            sourceName: "Archive Only",
            destinationKind: .apiEndpoint,
            unsupportedSemanticIDCount: 0
        )
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: apiReview))
        XCTAssertEqual(identity.displayHint, "setup.invalid/synthetic/apple-archive")
        XCTAssertEqual(
            identity.validatedURLString,
            "https://setup.invalid:8443/synthetic/apple-archive"
        )

        // Non-endpoint reviews and unknown bundle IDs never resolve an identity.
        XCTAssertNil(coordinator.importedV2APIEndpoint(for: SharedSetupV2ImportedProfileReview(
            id: uuid(2),
            sourceBundleID: "profile-004",
            sourceName: "Lossless",
            destinationKind: .deviceFolder,
            unsupportedSemanticIDCount: 0
        )))
        XCTAssertNil(coordinator.importedV2APIEndpoint(for: SharedSetupV2ImportedProfileReview(
            id: uuid(3),
            sourceBundleID: "missing-bundle",
            sourceName: "Unknown",
            destinationKind: .apiEndpoint,
            unsupportedSemanticIDCount: 0
        )))

        // Finish drops the plan, so the flow stops guessing an identity.
        coordinator.finish()
        XCTAssertNil(coordinator.importedV2APIEndpoint(for: apiReview))
    }

    // MARK: - Confirmed credential unblock (injected verified path)

    func testConfirmedCredentialUnblocksThroughInjectedVerifiedPath() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let spy = ConfirmationSpy()
        adapter.localAPIEndpointID = { importedURLString in
            spy.matchQueries.append(importedURLString)
            return spy.endpointID
        }
        adapter.confirmAPIEndpointRebind = { profileID, endpointID, credential in
            spy.confirmCalls.append(ConfirmationSpy.ConfirmCall(
                profileID: profileID,
                endpointID: endpointID,
                credential: credential
            ))
            // Mirror the production coordinator's verified effect: the real
            // execution gate clears the blocked identity only for this typed,
            // credential-confirmed rebind.
            _ = try service.confirmRebind(
                profileID: profileID,
                confirmation: .apiEndpoint(
                    endpointID: endpointID,
                    credentialsConfirmed: true
                )
            )
            return true
        }
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let outcome = try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
        let review = try XCTUnwrap(outcome.importedProfiles.first)
        XCTAssertEqual(review.destinationKind, .apiEndpoint)
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.isV2APIEndpointRebindAvailable)

        // The review resolves the imported identity and the matching local row.
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))
        XCTAssertEqual(
            coordinator.matchingV2LocalAPIEndpointID(
                forImportedURLString: identity.validatedURLString
            ),
            spy.endpointID
        )
        XCTAssertEqual(spy.matchQueries, [identity.validatedURLString])

        // A fresh credential unblocks exactly one imported profile.
        XCTAssertTrue(try coordinator.confirmV2APIEndpointRebind(
            profileID: review.id,
            endpointID: spy.endpointID,
            credential: "  fresh-token  "
        ))
        XCTAssertEqual(spy.confirmCalls.count, 1)
        XCTAssertEqual(spy.confirmCalls.first?.profileID, review.id)
        XCTAssertEqual(spy.confirmCalls.first?.endpointID, spy.endpointID)
        XCTAssertEqual(spy.confirmCalls.first?.credential, "fresh-token")
        XCTAssertFalse(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.v2ReboundProfileIDs.contains(review.id))
        XCTAssertNil(coordinator.errorMessage)
    }

    func testEmptyOrMalformedCredentialNeverReachesVerifiedPath() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let spy = ConfirmationSpy()
        adapter.localAPIEndpointID = { _ in spy.endpointID }
        adapter.confirmAPIEndpointRebind = { profileID, endpointID, credential in
            spy.confirmCalls.append(ConfirmationSpy.ConfirmCall(
                profileID: profileID,
                endpointID: endpointID,
                credential: credential
            ))
            return true
        }
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))

        let invalidCredentials = [
            "",
            "   ",
            "\t \n ",
            "bad\nline",
            "bad\u{01}line",
            String(repeating: "a", count: 8_193)
        ]
        for credential in invalidCredentials {
            XCTAssertThrowsError(
                try coordinator.confirmV2APIEndpointRebind(
                    profileID: review.id,
                    endpointID: spy.endpointID,
                    credential: credential
                )
            ) { error in
                XCTAssertEqual(
                    error as? SharedSetupV2CoordinatorError,
                    .invalidCredential
                )
            }
        }
        // None of the invalid attempts reached the injected verified path.
        XCTAssertTrue(spy.confirmCalls.isEmpty)
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertNotNil(coordinator.errorMessage)

        // The exact boundary — 8,192 valid characters — does reach it.
        XCTAssertTrue(try coordinator.confirmV2APIEndpointRebind(
            profileID: review.id,
            endpointID: spy.endpointID,
            credential: String(repeating: "a", count: 8_192)
        ))
        XCTAssertEqual(spy.confirmCalls.count, 1)
    }

    func testAbsentAPIEndpointClosuresSurfaceHonestUnavailability() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let coordinator = makeCoordinator(adapter: adapter)

        // The Mac attestation path stays available; only the API endpoint
        // confirmation is honestly reported as unavailable.
        XCTAssertTrue(coordinator.isV2RebindAvailable)
        XCTAssertFalse(coordinator.isV2APIEndpointRebindAvailable)
        XCTAssertNil(coordinator.v2ConnectedMacState)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertNil(coordinator.matchingV2LocalAPIEndpointID(
            forImportedURLString: "https://setup.invalid:8443/synthetic/apple-archive"
        ))
        XCTAssertThrowsError(
            try coordinator.confirmV2APIEndpointRebind(
                profileID: review.id,
                endpointID: uuid(501),
                credential: "fresh-token"
            )
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .transactionUnavailable
            )
        }
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))

        // An adapter-less coordinator reports the same honest unavailability.
        let bare = makeCoordinator(adapter: nil)
        XCTAssertFalse(bare.isV2RebindAvailable)
        XCTAssertFalse(bare.isV2APIEndpointRebindAvailable)
    }

    // MARK: - Connected-Mac attestation path

    func testMacAttestationConfirmPathClearsOnlyWithExplicitConfirmation() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-002"], mode: .add)
                .importedProfiles.first
        )
        XCTAssertEqual(review.destinationKind, .connectedMac)
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))

        // An unconfirmed attestation fails closed and is reported.
        XCTAssertThrowsError(
            try coordinator.confirmV2Rebind(
                profileID: review.id,
                confirmation: .connectedMac(pairingConfirmed: false)
            )
        ) { error in
            XCTAssertEqual(error as? SharedSetupV2ExecutionGateError, .rebindNotConfirmed)
        }
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertNotNil(coordinator.errorMessage)

        // The explicit attestation clears the blocked identity.
        XCTAssertTrue(try coordinator.confirmV2Rebind(
            profileID: review.id,
            confirmation: .connectedMac(pairingConfirmed: true)
        ))
        XCTAssertFalse(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.v2ReboundProfileIDs.contains(review.id))
        XCTAssertNil(coordinator.errorMessage)
    }

    func testConnectedMacStateReportsNativeFactsExactly() throws {
        let unpaired = SharedSetupV2ConnectedMacState(
            hasSavedManualIPPairing: false,
            savedManualIPMacName: nil,
            isLiveConnectionActive: false,
            liveConnectedPeerName: nil
        )
        XCTAssertEqual(unpaired.savedPairingCaption, "No saved Manual IP pairing on this device")
        XCTAssertEqual(unpaired.liveConnectionCaption, "No Mac connection active right now")

        let paired = SharedSetupV2ConnectedMacState(
            hasSavedManualIPPairing: true,
            savedManualIPMacName: "Studio Mac",
            isLiveConnectionActive: true,
            liveConnectedPeerName: "iPhone of Cody"
        )
        XCTAssertEqual(paired.savedPairingCaption, "Saved Manual IP pairing: Studio Mac")
        XCTAssertEqual(paired.liveConnectionCaption, "Mac connection active (iPhone of Cody)")
        XCTAssertEqual(
            SharedSetupV2ConnectedMacState(
                hasSavedManualIPPairing: true,
                savedManualIPMacName: nil,
                isLiveConnectionActive: true,
                liveConnectedPeerName: nil
            ).savedPairingCaption,
            "Saved Manual IP pairing: a paired Mac"
        )

        // The adapter surfaces the snapshot when supplied, and nothing otherwise.
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let coordinator = makeCoordinator(adapter: adapter)
        XCTAssertNil(coordinator.v2ConnectedMacState)
        adapter.connectedMacState = { paired }
        let wired = makeCoordinator(adapter: adapter)
        XCTAssertEqual(wired.v2ConnectedMacState, paired)
    }

    // MARK: - Failure and recovery

    func testConfirmationFailureLeavesBlockedStateIntactAndRecovers() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let spy = ConfirmationSpy()
        spy.nextError = SharedSetupV2ExecutionGateError.persistenceVerificationFailed
        adapter.localAPIEndpointID = { _ in spy.endpointID }
        adapter.confirmAPIEndpointRebind = { profileID, endpointID, credential in
            spy.confirmCalls.append(ConfirmationSpy.ConfirmCall(
                profileID: profileID,
                endpointID: endpointID,
                credential: credential
            ))
            if let nextError = spy.nextError { throw nextError }
            _ = try service.confirmRebind(
                profileID: profileID,
                confirmation: .apiEndpoint(
                    endpointID: endpointID,
                    credentialsConfirmed: true
                )
            )
            return true
        }
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))

        // A failing verified path rethrows, reports, and changes nothing.
        XCTAssertThrowsError(
            try coordinator.confirmV2APIEndpointRebind(
                profileID: review.id,
                endpointID: spy.endpointID,
                credential: "first-attempt"
            )
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2ExecutionGateError,
                .persistenceVerificationFailed
            )
        }
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.v2ReboundProfileIDs.isEmpty)
        XCTAssertNotNil(coordinator.errorMessage)

        // A later successful attempt still works and clears the error.
        spy.nextError = nil
        XCTAssertTrue(try coordinator.confirmV2APIEndpointRebind(
            profileID: review.id,
            endpointID: spy.endpointID,
            credential: "second-attempt"
        ))
        XCTAssertFalse(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.v2ReboundProfileIDs.contains(review.id))
        XCTAssertNil(coordinator.errorMessage)
    }

    func testCredentialEntryModelGatesAndResetsAfterSuccessAndFailure() {
        let entry = SharedSetupV2CredentialEntryModel()
        XCTAssertTrue(entry.authorization.isEmpty)
        XCTAssertFalse(entry.canConfirm)

        entry.authorization = "   "
        XCTAssertFalse(entry.canConfirm)

        entry.authorization = "typed-secret"
        XCTAssertTrue(entry.canConfirm)

        // After a failed attempt the view resets the entry, so the same
        // secret can never silently re-fire from the disabled field.
        entry.reset()
        XCTAssertTrue(entry.authorization.isEmpty)
        XCTAssertFalse(entry.canConfirm)

        // The same reset applies after a successful attempt.
        entry.authorization = "typed-secret"
        entry.reset()
        XCTAssertTrue(entry.authorization.isEmpty)
    }

    // MARK: - Full production loop over the real export profile coordinator

    func testFullProductionLoopConfirmsEndpointWithRealExportProfileCoordinator() throws {
        let keychain = FakeKeychainStore()
        let vaultManager = VaultManager(
            defaults: SystemUserDefaults(defaults: defaults),
            bookmarkResolver: PathMappingBookmarkResolver(),
            identityProbe: FakeVaultFolderIdentityProbe()
        )
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let apiExportSettings = APIExportSettings(userDefaults: defaults, keychain: keychain)
        let exportProfiles = ExportProfileCoordinator(
            profileStore: ExportProfileStore(userDefaults: defaults),
            destinationStore: ProfileDestinationStore(userDefaults: defaults, keychain: keychain),
            scheduledEntryStore: ScheduledExportEntryStore(userDefaults: defaults),
            settings: settings,
            vaultManager: vaultManager,
            apiExportSettings: apiExportSettings,
            initialTarget: .localIPhoneFolder,
            sharedSetupV2ExecutionGate: SharedSetupV2ExecutionGate(userDefaults: defaults)
        )
        Self.retainedInstances.append(exportProfiles)
        Self.retainedInstances.append(vaultManager)

        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(
            service,
            exportProfiles: { exportProfiles },
            connectedMacState: { nil }
        )
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.isV2APIEndpointRebindAvailable)

        // No local endpoint row exists yet: no honest match, fail closed.
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))
        XCTAssertNil(coordinator.matchingV2LocalAPIEndpointID(
            forImportedURLString: identity.validatedURLString
        ))
        // A credential against a fabricated endpoint row fails closed: the
        // production closure cannot resolve that row, so it reports its own
        // honest unavailability without touching the blocked identity.
        XCTAssertThrowsError(
            try coordinator.confirmV2APIEndpointRebind(
                profileID: review.id,
                endpointID: uuid(601),
                credential: "fresh-token"
            )
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .exportProfileServiceUnavailable
            )
        }
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))

        // The user adds the matching endpoint locally through the exact
        // editor path production already uses (no credential yet).
        let endpointID = try XCTUnwrap(exportProfiles.importAPIEndpointSelection(
            name: "Archive",
            endpointURLString: "https://setup.invalid:8443/synthetic/apple-archive",
            bearerToken: nil
        ))
        XCTAssertEqual(
            coordinator.matchingV2LocalAPIEndpointID(
                forImportedURLString: identity.validatedURLString
            ),
            endpointID
        )

        // The fresh credential unblocks the profile through the verified
        // binding + gate + rollback path on the real coordinator.
        XCTAssertTrue(try coordinator.confirmV2APIEndpointRebind(
            profileID: review.id,
            endpointID: endpointID,
            credential: "fresh-token-123"
        ))
        XCTAssertFalse(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.v2ReboundProfileIDs.contains(review.id))
        XCTAssertNil(coordinator.errorMessage)

        // Durable truth: the real profile row is bound and the fresh
        // credential lives in the endpoint row's Keychain-backed slot.
        XCTAssertEqual(
            exportProfiles.profileStore.profile(id: review.id)?.apiEndpointID,
            endpointID
        )
        XCTAssertEqual(exportProfiles.destinationStore.token(for: endpointID), "fresh-token-123")
        XCTAssertTrue(try storedBlockedIDs().isEmpty)
    }

    // MARK: - In-flow endpoint add/bind when no saved row matches

    func testInFlowURLConfirmationCreatesRowAndCompletesVerifiedRebind() throws {
        let exportProfiles = makeRetainedExportProfileCoordinator()
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(
            service,
            exportProfiles: { exportProfiles },
            connectedMacState: { nil }
        )
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        XCTAssertTrue(coordinator.isV2APIEndpointRebindAvailable)
        XCTAssertTrue(coordinator.isV2ImportedAPIEndpointAddAvailable)

        // No saved row matches, so the review offers the in-flow URL
        // confirmation against the exact plan-retained URL.
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))
        XCTAssertNil(coordinator.matchingV2LocalAPIEndpointID(
            forImportedURLString: identity.validatedURLString
        ))

        let rowID = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.contains(rowID))
        XCTAssertNil(coordinator.errorMessage)

        // The row exists through the editor's exact upsert path: the exact
        // imported URL, an identity-derived honest name, no credential yet.
        let row = try XCTUnwrap(exportProfiles.destinationStore.apiEndpoint(id: rowID))
        XCTAssertEqual(row.endpointURLString, identity.validatedURLString)
        XCTAssertEqual(row.name, identity.displayHint)
        XCTAssertNil(exportProfiles.destinationStore.token(for: rowID))

        // The created row resolves through the conservative identity matcher.
        XCTAssertEqual(
            coordinator.matchingV2LocalAPIEndpointID(
                forImportedURLString: identity.validatedURLString
            ),
            rowID
        )
        XCTAssertTrue(SharedSetupV2EndpointIdentity.localRowURL(
            row.endpointURLString,
            matchesImportedURLString: identity.validatedURLString
        ))

        // Completing the existing credential flow runs the verified rebind
        // and clears the block.
        XCTAssertTrue(try coordinator.confirmV2APIEndpointRebind(
            profileID: review.id,
            endpointID: rowID,
            credential: "fresh-token-123"
        ))
        XCTAssertFalse(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.v2ReboundProfileIDs.contains(review.id))
        XCTAssertEqual(
            exportProfiles.profileStore.profile(id: review.id)?.apiEndpointID,
            rowID
        )
        XCTAssertEqual(exportProfiles.destinationStore.token(for: rowID), "fresh-token-123")
        XCTAssertTrue(try storedBlockedIDs().isEmpty)
    }

    func testInFlowRowCreationBindsNoDestinationUntilVerifiedRebind() throws {
        let exportProfiles = makeRetainedExportProfileCoordinator()
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(
            service,
            exportProfiles: { exportProfiles },
            connectedMacState: { nil }
        )
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))
        let rowID = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)

        // Snapshot semantics: a created row alone binds no destination,
        // stores no credential, and never clears the blocked identity.
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertNil(exportProfiles.profileStore.profile(id: review.id)?.apiEndpointID)
        XCTAssertNil(exportProfiles.destinationStore.token(for: rowID))
        XCTAssertFalse(coordinator.v2ReboundProfileIDs.contains(review.id))
        XCTAssertFalse(try storedBlockedIDs().isEmpty)
    }

    func testUserNeverConfirmsURLLeavesNoRowAndKeepsBlock() throws {
        let exportProfiles = makeRetainedExportProfileCoordinator()
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(
            service,
            exportProfiles: { exportProfiles },
            connectedMacState: { nil }
        )
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        XCTAssertTrue(coordinator.isV2ImportedAPIEndpointAddAvailable)

        // The user never confirms the URL: no row is created, nothing is
        // bound, and the blocked identity stays exactly as it was.
        XCTAssertTrue(exportProfiles.destinationStore.apiEndpoints.isEmpty)
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.isEmpty)
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertNotNil(coordinator.importedV2APIEndpoint(for: review))
    }

    func testAbsentUpsertClosureKeepsHonestDeadEnd() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let spy = ConfirmationSpy()
        adapter.localAPIEndpointID = { _ in nil }
        adapter.confirmAPIEndpointRebind = { profileID, endpointID, credential in
            spy.confirmCalls.append(ConfirmationSpy.ConfirmCall(
                profileID: profileID,
                endpointID: endpointID,
                credential: credential
            ))
            return true
        }
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        // The cycle-4 closure set keeps the credential path available while
        // the in-flow add stays honestly unavailable (dead-end copy).
        XCTAssertTrue(coordinator.isV2APIEndpointRebindAvailable)
        XCTAssertFalse(coordinator.isV2ImportedAPIEndpointAddAvailable)

        XCTAssertThrowsError(
            try coordinator.confirmV2ImportedAPIEndpointURL(for: review)
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .transactionUnavailable
            )
        }
        XCTAssertTrue(spy.confirmCalls.isEmpty)
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.isEmpty)
    }

    func testIdentityMismatchAfterUpsertFailsClosed() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let spy = ConfirmationSpy()
        var upsertCalls: [(name: String, url: String)] = []
        adapter.upsertAPIEndpointForImportedURL = { name, urlString in
            upsertCalls.append((name: name, url: urlString))
            // A row id the conservative matcher will not resolve to.
            return spy.endpointID
        }
        adapter.localAPIEndpointID = { _ in nil }
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))

        XCTAssertThrowsError(
            try coordinator.confirmV2ImportedAPIEndpointURL(for: review)
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2ExecutionGateError,
                .persistenceVerificationFailed
            )
        }
        XCTAssertEqual(upsertCalls.count, 1)
        XCTAssertEqual(upsertCalls.first?.name, identity.displayHint)
        XCTAssertEqual(upsertCalls.first?.url, identity.validatedURLString)
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.isEmpty)
        XCTAssertFalse(coordinator.v2ReboundProfileIDs.contains(review.id))
        XCTAssertNotNil(coordinator.errorMessage)
    }

    func testUpsertReusedCaseInsensitiveRowCanonicalizesToConfirmedIdentity() throws {
        let exportProfiles = makeRetainedExportProfileCoordinator()
        // Pre-existing row whose raw URL differs from the imported identity
        // only by path case: the conservative matcher rejects it (paths
        // compare exactly), but the editor upsert resolves rows
        // case-insensitively by raw URL string and canonicalizes the reused
        // row to the user-confirmed imported URL — so the upserted row IS the
        // resolved match in one honest step: same row, exact confirmed URL.
        let preexistingID = try XCTUnwrap(exportProfiles.importAPIEndpointSelection(
            name: "Personal archive",
            endpointURLString: "https://setup.invalid:8443/SYNTHETIC/apple-archive",
            bearerToken: nil
        ))
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(
            service,
            exportProfiles: { exportProfiles },
            connectedMacState: { nil }
        )
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))
        XCTAssertNil(coordinator.matchingV2LocalAPIEndpointID(
            forImportedURLString: identity.validatedURLString
        ))

        // One explicit confirm reuses the case-variant row and canonicalizes
        // it to the exact user-confirmed URL; no second row is created.
        // Cycle-6 name preservation: the reused row keeps its existing
        // name ("Personal archive") — this previously asserted the rename
        // to the identity-derived display hint, which silently renamed a
        // row the user had already named; the hint names only a genuinely
        // new row.
        let rowID = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)
        XCTAssertEqual(rowID, preexistingID)
        XCTAssertEqual(exportProfiles.destinationStore.apiEndpoints.count, 1)
        let row = try XCTUnwrap(exportProfiles.destinationStore.apiEndpoints.first)
        XCTAssertEqual(row.endpointURLString, identity.validatedURLString)
        XCTAssertEqual(row.name, "Personal archive")
        XCTAssertNotEqual(row.name, identity.displayHint)
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.contains(rowID))

        // The block still clears only through the verified credential rebind.
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
        XCTAssertTrue(try coordinator.confirmV2APIEndpointRebind(
            profileID: review.id,
            endpointID: rowID,
            credential: "fresh-token"
        ))
        XCTAssertFalse(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))
    }

    // MARK: - Cycle-6 reused-row name preservation

    func testInFlowConfirmationPreservesReusedRowName() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let existingRowID = UUID()
        var upsertCalls: [(name: String, url: String)] = []
        adapter.reusedAPIEndpointNameForImportedURL = { _ in "Team archive" }
        adapter.upsertAPIEndpointForImportedURL = { name, urlString in
            upsertCalls.append((name: name, url: urlString))
            return existingRowID
        }
        adapter.localAPIEndpointID = { _ in existingRowID }
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))

        let rowID = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)
        XCTAssertEqual(rowID, existingRowID)

        // The upsert receives the reused row's existing name — never the
        // identity-derived display hint, which would rename the row the
        // editor's upsert path reuses. The identity discipline is
        // unchanged: the post-upsert conservative re-verification still
        // gates the row before any credential confirmation runs.
        XCTAssertEqual(upsertCalls.count, 1)
        XCTAssertEqual(upsertCalls.first?.name, "Team archive")
        XCTAssertNotEqual(upsertCalls.first?.name, identity.displayHint)
        XCTAssertEqual(upsertCalls.first?.url, identity.validatedURLString)
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.contains(rowID))
        XCTAssertNil(coordinator.errorMessage)
    }

    func testInFlowNewRowStillReceivesIdentityHintName() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let newRowID = UUID()
        var upsertCalls: [(name: String, url: String)] = []
        adapter.reusedAPIEndpointNameForImportedURL = { _ in nil }
        adapter.upsertAPIEndpointForImportedURL = { name, urlString in
            upsertCalls.append((name: name, url: urlString))
            return newRowID
        }
        adapter.localAPIEndpointID = { _ in newRowID }
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))

        _ = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)

        // No row is reused, so the identity-derived display hint names the
        // genuinely new row exactly as before.
        XCTAssertEqual(upsertCalls.count, 1)
        XCTAssertEqual(upsertCalls.first?.name, identity.displayHint)
        XCTAssertEqual(upsertCalls.first?.url, identity.validatedURLString)
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.contains(newRowID))
    }

    func testInFlowBlankReusedRowNameFallsBackToIdentityHint() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let existingRowID = UUID()
        var upsertCalls: [(name: String, url: String)] = []
        adapter.reusedAPIEndpointNameForImportedURL = { _ in "   " }
        adapter.upsertAPIEndpointForImportedURL = { name, urlString in
            upsertCalls.append((name: name, url: urlString))
            return existingRowID
        }
        adapter.localAPIEndpointID = { _ in existingRowID }
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))

        _ = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)

        // A blank reused name cannot be preserved (the editor's own empty-
        // name rule would not keep it), so the hint names the row instead.
        XCTAssertEqual(upsertCalls.count, 1)
        XCTAssertEqual(upsertCalls.first?.name, identity.displayHint)
        XCTAssertEqual(upsertCalls.first?.url, identity.validatedURLString)
    }

    func testInFlowConfirmationRequiresRetainedIdentity() throws {
        let exportProfiles = makeRetainedExportProfileCoordinator()
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(
            service,
            exportProfiles: { exportProfiles },
            connectedMacState: { nil }
        )
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        XCTAssertTrue(coordinator.isV2ImportedAPIEndpointAddAvailable)

        // Finish drops the plan: the flow stops trusting a retained identity
        // and never creates a row from a remembered URL.
        coordinator.finish()
        XCTAssertThrowsError(
            try coordinator.confirmV2ImportedAPIEndpointURL(for: review)
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .importedEndpointUnavailable
            )
        }
        XCTAssertTrue(exportProfiles.destinationStore.apiEndpoints.isEmpty)
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.isEmpty)
    }

    func testCredentialBoundsStillEnforcedAfterInFlowRowCreation() throws {
        let exportProfiles = makeRetainedExportProfileCoordinator()
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(
            service,
            exportProfiles: { exportProfiles },
            connectedMacState: { nil }
        )
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )
        let identity = try XCTUnwrap(coordinator.importedV2APIEndpoint(for: review))
        let rowID = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)

        // The existing credential bounds guard the new row exactly as they
        // guard a pre-existing match; nothing invalid reaches the store.
        let invalidCredentials = [
            "",
            "   ",
            "bad\nline",
            "bad\u{01}line",
            String(repeating: "a", count: 8_193)
        ]
        for credential in invalidCredentials {
            XCTAssertThrowsError(
                try coordinator.confirmV2APIEndpointRebind(
                    profileID: review.id,
                    endpointID: rowID,
                    credential: credential
                )
            ) { error in
                XCTAssertEqual(
                    error as? SharedSetupV2CoordinatorError,
                    .invalidCredential
                )
            }
            XCTAssertNil(exportProfiles.destinationStore.token(for: rowID))
        }
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: review.id))

        // The exact boundary still succeeds through the verified path.
        let boundary = String(repeating: "a", count: 8_192)
        XCTAssertTrue(try coordinator.confirmV2APIEndpointRebind(
            profileID: review.id,
            endpointID: rowID,
            credential: boundary
        ))
        XCTAssertEqual(exportProfiles.destinationStore.token(for: rowID), boundary)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(
            identity.validatedURLString,
            "https://setup.invalid:8443/synthetic/apple-archive"
        )
    }

    func testInFlowConfirmAnnouncesAndResetsAcrossFinish() throws {
        let exportProfiles = makeRetainedExportProfileCoordinator()
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(
            service,
            exportProfiles: { exportProfiles },
            connectedMacState: { nil }
        )
        let announcements = AnnouncementRecorder()
        let coordinator = makeCoordinator(
            adapter: adapter,
            announcer: { announcements.values.append($0) }
        )

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))
        let review = try XCTUnwrap(
            try coordinator.applyV2(selectedBundleIDs: ["profile-003"], mode: .add)
                .importedProfiles.first
        )

        _ = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)
        // applyV2 announced first; the in-flow add announces second.
        XCTAssertEqual(announcements.values.count, 2)
        XCTAssertTrue(announcements.values.last?.contains("API endpoint added") == true)
        XCTAssertEqual(
            announcements.values.first,
            "Shared Setup profiles applied. Complete local destination setup before exporting."
        )

        // Finish resets the in-flow row bookkeeping along with the flow.
        coordinator.finish()
        XCTAssertTrue(coordinator.v2InFlowEndpointRowIDs.isEmpty)
        XCTAssertTrue(coordinator.v2ReboundProfileIDs.isEmpty)
    }

    // MARK: - Live connected-Mac state re-render

    func testConnectedMacChangeSignalReRendersAndRefreshesFacts() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        var adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let subject = PassthroughSubject<Void, Never>()
        var macState = SharedSetupV2ConnectedMacState(
            hasSavedManualIPPairing: false,
            savedManualIPMacName: nil,
            isLiveConnectionActive: false,
            liveConnectedPeerName: nil
        )
        adapter.connectedMacState = { macState }
        adapter.connectedMacStateChanges = { subject.eraseToAnyPublisher() }
        let coordinator = makeCoordinator(adapter: adapter)

        XCTAssertEqual(coordinator.v2ConnectedMacStateRevision, 0)
        XCTAssertEqual(
            coordinator.v2ConnectedMacState?.liveConnectionCaption,
            "No Mac connection active right now"
        )

        // Facts change while the review sheet stays presented: the change
        // signal bumps the revision so the rows re-render and re-read the
        // authoritative closure snapshot.
        macState = SharedSetupV2ConnectedMacState(
            hasSavedManualIPPairing: true,
            savedManualIPMacName: "Studio Mac",
            isLiveConnectionActive: true,
            liveConnectedPeerName: "iPhone of Cody"
        )
        subject.send()
        XCTAssertEqual(coordinator.v2ConnectedMacStateRevision, 1)
        XCTAssertEqual(
            coordinator.v2ConnectedMacState?.savedPairingCaption,
            "Saved Manual IP pairing: Studio Mac"
        )
        XCTAssertEqual(
            coordinator.v2ConnectedMacState?.liveConnectionCaption,
            "Mac connection active (iPhone of Cody)"
        )

        subject.send()
        XCTAssertEqual(coordinator.v2ConnectedMacStateRevision, 2)

        // Without a signal producer, revisions never move — the cycle-4
        // render-time snapshot semantics stay observable.
        let quiet = makeCoordinator(adapter: SharedSetupV2CoordinatorAdapter.production(service))
        XCTAssertEqual(quiet.v2ConnectedMacStateRevision, 0)
    }

    func testProductionConnectedMacFactChangesFireOnlyOnDisplayedFacts() throws {
        // The production signal derives purely from the shared sync service's
        // published facts the review rows display — no transport work.
        let syncService = SyncService()
        Self.retainedInstances.append(syncService)
        let signalCount = SignalCounter()
        let cancellable = SharedSetupV2CoordinatorAdapter
            .connectedMacFactChanges(syncService: syncService)
            .sink { _ in signalCount.value += 1 }

        withExtendedLifetime(cancellable) {
            // No initial replay of current values fires a signal.
            XCTAssertEqual(signalCount.value, 0)

            syncService.connectionState = .connecting
            XCTAssertEqual(signalCount.value, 1)
            syncService.connectionState = .connected
            XCTAssertEqual(signalCount.value, 2)
            syncService.connectedPeerName = "Test Mac"
            XCTAssertEqual(signalCount.value, 3)

            // Unrelated published sync-service state never re-renders the
            // review rows.
            syncService.lastError = "unrelated"
            syncService.discoveredPeers = []
            XCTAssertEqual(signalCount.value, 3)
        }

        let snapshot = SharedSetupV2ConnectedMacState(syncService: syncService)
        XCTAssertEqual(snapshot.liveConnectionCaption, "Mac connection active (Test Mac)")
    }

    // MARK: - Helpers

    private final class ConfirmationSpy {
        struct ConfirmCall {
            let profileID: UUID
            let endpointID: UUID
            let credential: String
        }

        var confirmCalls: [ConfirmCall] = []
        var matchQueries: [String] = []
        var nextError: Error?
        let endpointID = UUID()
    }

    /// Reference box so @Sendable closures can record announcements.
    private final class AnnouncementRecorder {
        var values: [String] = []
    }

    /// Reference box so Combine sinks can count main-thread signals.
    private final class SignalCounter {
        var value = 0
    }

    /// The real production export-profile coordinator over this test's
    /// isolated suite — the exact editor path, retained for the process
    /// lifetime per the sanitizer-gate lifecycle audit.
    private func makeRetainedExportProfileCoordinator() -> ExportProfileCoordinator {
        let keychain = FakeKeychainStore()
        let vaultManager = VaultManager(
            defaults: SystemUserDefaults(defaults: defaults),
            bookmarkResolver: PathMappingBookmarkResolver(),
            identityProbe: FakeVaultFolderIdentityProbe()
        )
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let exportProfiles = ExportProfileCoordinator(
            profileStore: ExportProfileStore(userDefaults: defaults),
            destinationStore: ProfileDestinationStore(userDefaults: defaults, keychain: keychain),
            scheduledEntryStore: ScheduledExportEntryStore(userDefaults: defaults),
            settings: settings,
            vaultManager: vaultManager,
            apiExportSettings: APIExportSettings(userDefaults: defaults, keychain: keychain),
            initialTarget: .localIPhoneFolder,
            sharedSetupV2ExecutionGate: SharedSetupV2ExecutionGate(userDefaults: defaults)
        )
        Self.retainedInstances.append(exportProfiles)
        Self.retainedInstances.append(vaultManager)
        return exportProfiles
    }

    private func makeService(
        profileIDs: [UUID],
        scheduleIDs: [UUID]
    ) -> SharedSetupV2TransactionAdapter {
        var profileIterator = profileIDs.makeIterator()
        var scheduleIterator = scheduleIDs.makeIterator()
        let transaction = SharedSetupV2ProfileTransaction(
            userDefaults: defaults,
            now: { self.fixedDate(2026, 9, 4) },
            calendar: utcCalendar(),
            makeProfileID: { profileIterator.next() ?? self.uuid(8_001) },
            makeScheduleID: { scheduleIterator.next() ?? self.uuid(8_002) }
        )
        return SharedSetupV2TransactionAdapter(
            transaction: transaction,
            executionGate: SharedSetupV2ExecutionGate(userDefaults: defaults)
        )
    }

    private func makeCoordinator(
        adapter: SharedSetupV2CoordinatorAdapter?,
        announcer: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) -> SharedSetupCoordinator {
        SharedSetupCoordinator(
            settings: AdvancedExportSettings(userDefaults: defaults),
            apiExportSettings: APIExportSettings(
                userDefaults: defaults,
                keychain: FakeKeychainStore()
            ),
            schedulingManager: SchedulingManager(
                initialSchedule: ExportSchedule(),
                persistScheduleChanges: false,
                systemSideEffectsEnabled: false
            ),
            userDefaults: defaults,
            registry: fixtureRegistry(),
            accessibilityAnnouncer: announcer,
            v2Adapter: adapter
        )
    }

    private func storedBlockedIDs() throws -> [UUID] {
        try SharedSetupV2ProfileTransaction.decodeBlockedProfileIDs(
            XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey))
        )
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: try fixtureURL(named: name))
    }

    private func fixtureURL(named name: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(
                "packages/contracts/shared-setup/v2/fixtures/\(name)"
            )
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate the Shared Setup v2 fixture \(name)")
    }

    private func fixtureRegistry() -> SharedSetupMetricRegistry {
        SharedSetupMetricRegistry(
            version: 1,
            sha256: "4597c2f197c25e6e6a0ec1976e3b5de930edffa2ca61fd4779d47b465075bae2",
            semanticToApple: [
                "active_energy": "active_energy",
                "blood_pressure_systolic": "blood_pressure_systolic",
                "heart_rate_avg": "heart_rate_avg",
                "hrv": "hrv",
                "sleep_core": "sleep_core",
                "steps": "steps"
            ],
            semanticToAndroid: [
                "active_energy": "active_calories",
                "blood_pressure_systolic": "bp_systolic",
                "heart_rate_avg": "avg_hr",
                "sleep_core": "sleep_light",
                "steps": "steps",
                "android.hrv_rmssd": "hrv"
            ],
            equivalence: [
                "active_energy": .mappedAlias,
                "blood_pressure_systolic": .mappedAlias,
                "heart_rate_avg": .mappedAlias,
                "hrv": .platformExactOrUnavailable,
                "sleep_core": .mappedAlias,
                "steps": .platformExactOrUnavailable,
                "android.hrv_rmssd": .platformDistinct
            ]
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }

    private func fixedDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar().date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
#endif
