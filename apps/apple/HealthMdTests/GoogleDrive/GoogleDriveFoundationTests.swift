import Foundation
import XCTest
@testable import HealthMd

final class GoogleDriveFoundationTests: XCTestCase {
    @MainActor
    func testConnectRejectsProtectedConsentBeforeStartingOAuth() async throws {
        let authorizer = BindingTestAuthorizer()
        let manager = GoogleDriveConnectionManager(authorizer: authorizer)
        do {
            _ = try await manager.connect(commitAllowed: { false })
            XCTFail("Protected consent must be rejected")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(authorizer.calls, 0)
    }

    @MainActor
    func testProtectionAndCancellationAtEveryAcquisitionBoundaryStopSubsequentCallsAndWrites() async throws {
        for cancel in [false, true] {
            for stage in ["oauth", "/token", "/drive/v3/about", "/drive/v3/files/folder"] {
                for exactReauthorization in [false, true] {
                    let suite = "DriveProtectedBinding.\(UUID().uuidString)"
                    let defaults = BindingTestDefaults(suiteName: suite)!
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let protection = ConfigurationProtectionManager(userDefaults: defaults)
                    let started = expectation(description: "Async binding suspended at \(stage)")
                    let gate = BindingTestGate(started: started)
                    let authorizer = BindingTestAuthorizer(gate: stage == "oauth" ? gate : nil)
                    let transport = BindingTestTransport(gate: gate, delayedPath: stage)
                    let keychain = BindingTestKeychain()
                    let credentials = GoogleDriveCredentialStore(keychain: keychain)
                    let store = GoogleDriveDestinationStore(userDefaults: defaults)
                    let existing = GoogleDriveDestination(
                        credentialReferenceID: UUID(), accountPermissionID: "synthetic-permission",
                        folderID: "folder", canAddChildren: true
                    )
                    if exactReauthorization {
                        store.upsert(existing)
                        try credentials.save(GoogleDriveTokenCredential(
                            accessToken: "old-access", refreshToken: "old-refresh",
                            expiresAt: .distantFuture, grantedScopes: [GoogleDriveConfiguration.driveFileScope]
                        ), referenceID: existing.credentialReferenceID)
                    }
                    defaults.destinationWrites = 0
                    keychain.writeCount = 0
                    let credentialBefore = keychain.values
                    let configuration = try XCTUnwrap(GoogleDriveConfiguration(
                        clientID: "public.apps.googleusercontent.com",
                        redirectURI: "com.googleusercontent.apps.public:/oauthredirect"
                    ))
                    let manager = GoogleDriveConnectionManager(
                        configuration: configuration, destinationStore: store, credentialStore: credentials,
                        tokenEndpoint: GoogleDriveTokenEndpoint(transport: transport),
                        api: GoogleDriveAPIClient(transport: transport), authorizer: authorizer
                    )
                    var selectionWrites = 0
                    let task = Task { @MainActor in
                        do {
                            _ = try await manager.connect(
                                replacing: exactReauthorization ? existing.id : nil,
                                commitAllowed: { protection.performConfigurationChange({}) }
                            )
                            selectionWrites += 1
                            return false
                        } catch is CancellationError { return true }
                        catch { XCTFail("Unexpected error: \(error)"); return false }
                    }
                    await fulfillment(of: [started], timeout: 2)
                    if cancel { task.cancel() } else { protection.setEnabled(true) }
                    let before = defaults.dictionaryRepresentation() as NSDictionary
                    await gate.resume()
                    let rejected = await task.value
                    let calls = await transport.calls
                    XCTAssertTrue(rejected)
                    XCTAssertEqual(calls["/token", default: 0], stage == "oauth" ? 0 : 1)
                    XCTAssertEqual(calls["/drive/v3/about", default: 0], ["oauth", "/token"].contains(stage) ? 0 : 1)
                    XCTAssertEqual(calls["/drive/v3/files/folder", default: 0], stage == "/drive/v3/files/folder" ? 1 : 0)
                    XCTAssertEqual(keychain.writeCount, 0)
                    XCTAssertEqual(keychain.values, credentialBefore)
                    XCTAssertEqual(defaults.destinationWrites, 0)
                    XCTAssertEqual(store.destinations.count, exactReauthorization ? 1 : 0)
                    XCTAssertEqual(selectionWrites, 0)
                    XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
                }
            }
        }
    }

    @MainActor
    func testDisconnectDenialBeforeTaskOrDuringCleanupAndRevocationPreservesLocalConfiguration() async throws {
        for stage in ["entry", "cleanup", "/revoke"] {
            for cancel in [false, true] {
                let suite = "DriveProtectedDisconnect.\(UUID())"
                let defaults = BindingTestDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let protection = ConfigurationProtectionManager(userDefaults: defaults)
                let store = GoogleDriveDestinationStore(userDefaults: defaults)
                let destination = makeDestination()
                store.upsert(destination)
                let keychain = BindingTestKeychain()
                let credentials = GoogleDriveCredentialStore(keychain: keychain)
                try credentials.save(GoogleDriveTokenCredential(
                    accessToken: "old-access", refreshToken: "old-refresh", expiresAt: .distantFuture,
                    grantedScopes: [GoogleDriveConfiguration.driveFileScope]
                ), referenceID: destination.credentialReferenceID)
                let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
                let vault = LifecycleHarness.retain(VaultManager(
                    defaults: SystemUserDefaults(defaults: defaults),
                    bookmarkResolver: PathMappingBookmarkResolver(), identityProbe: FakeVaultFolderIdentityProbe()
                ))
                let coordinator = LifecycleHarness.retain(ExportProfileCoordinator(
                    profileStore: ExportProfileStore(userDefaults: defaults),
                    destinationStore: ProfileDestinationStore(userDefaults: defaults, keychain: keychain),
                    googleDriveDestinationStore: store,
                    scheduledEntryStore: ScheduledExportEntryStore(userDefaults: defaults),
                    settings: settings, vaultManager: vault,
                    apiExportSettings: APIExportSettings(userDefaults: defaults, keychain: keychain),
                    initialTarget: .googleDrive
                ))
                let activeID = try XCTUnwrap(coordinator.profileStore.activeProfileID)
                _ = coordinator.profileStore.setGoogleDriveBinding(profileID: activeID, destinationID: destination.id)
                let other = coordinator.profileStore.add(
                    name: "Another Drive profile", settings: ExportSettingsSnapshot.from(settings),
                    target: .googleDrive, googleDriveDestinationID: destination.id
                )
                for id in [activeID, other.id] {
                    _ = coordinator.scheduledEntryStore.upsert(ScheduledExportEntry(profileID: id, isEnabled: true))
                }
                // Bootstrap applies published settings whose persistence runs on the next
                // main-queue turn. Finish that admitted initialization before the no-write
                // snapshot; otherwise its daily-note save can race an entry-denied task.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
                // Entry denial intentionally never waits; only delayed stages register a wait.
                let started = XCTestExpectation(description: "Disconnect suspended at \(stage)")
                let gate = BindingTestGate(started: started)
                let transport = BindingTestTransport(gate: gate, delayedPath: stage)
                let manager = GoogleDriveConnectionManager(
                    destinationStore: store, credentialStore: credentials,
                    tokenEndpoint: GoogleDriveTokenEndpoint(transport: transport),
                    cleanupForDisconnect: { _ in if stage == "cleanup" { await gate.pause() } }
                )
                var selection: UUID? = destination.id
                // Models protection changing between button admission and Task execution.
                if stage == "entry", !cancel { protection.setEnabled(true) }
                keychain.writeCount = 0
                defaults.destinationWrites = 0
                let credentialsBefore = keychain.values
                var before = (defaults.persistentDomain(forName: suite) ?? [:]) as NSDictionary
                let task = Task { @MainActor in
                    do {
                        try await coordinator.disconnectGoogleDrive(
                            destinationID: destination.id, manager: manager,
                            commitAllowed: { protection.performConfigurationChange({}) }
                        )
                        try Task.checkCancellation()
                        protection.performConfigurationChange { selection = nil }
                        return false
                    } catch is CancellationError { return true }
                    catch { XCTFail("Unexpected disconnect error: \(error)"); return false }
                }
                if stage == "entry" {
                    if cancel { task.cancel() }
                } else {
                    await fulfillment(of: [started], timeout: 2)
                    if cancel { task.cancel() } else { protection.setEnabled(true) }
                    before = (defaults.persistentDomain(forName: suite) ?? [:]) as NSDictionary
                    await gate.resume()
                }
                let rejected = await task.value
                let calls = await transport.calls
                XCTAssertTrue(rejected)
                XCTAssertEqual(calls["/revoke", default: 0], stage == "/revoke" ? 1 : 0)
                XCTAssertEqual(keychain.removeCount, 0)
                XCTAssertEqual(keychain.writeCount, 0)
                XCTAssertEqual(keychain.values, credentialsBefore)
                XCTAssertEqual(defaults.destinationWrites, 0)
                XCTAssertEqual(store.destination(id: destination.id), destination)
                XCTAssertEqual(selection, destination.id)
                XCTAssertEqual(coordinator.profileStore.activeProfileID, activeID)
                for id in [activeID, other.id] {
                    XCTAssertEqual(coordinator.profileStore.profile(id: id)?.googleDriveDestinationID, destination.id)
                    XCTAssertEqual(coordinator.scheduledEntryStore.entry(profileID: id)?.isEnabled, true)
                }
                // Compare this isolated suite's complete persisted bytes, not volatile global
                // Apple/keyboard preferences inherited by dictionaryRepresentation().
                XCTAssertEqual((defaults.persistentDomain(forName: suite) ?? [:]) as NSDictionary, before)
            }
        }
    }

    func testConfigurationRequiresExplicitPublicClientValues() {
        XCTAssertNil(GoogleDriveConfiguration(clientID: nil, redirectURI: nil))
        XCTAssertNil(GoogleDriveConfiguration(clientID: "$(GOOGLE_DRIVE_IOS_CLIENT_ID)", redirectURI: "$(GOOGLE_DRIVE_REDIRECT_URI)"))
        XCTAssertNil(GoogleDriveConfiguration(clientID: "client", redirectURI: "https://example.com/callback"))
        XCTAssertNotNil(GoogleDriveConfiguration(
            clientID: "public.apps.googleusercontent.com",
            redirectURI: "com.googleusercontent.apps.public:/oauthredirect"
        ))
    }

    func testAuthorizationRequestUsesDriveFileOnlyAndMobileFolderPicker() throws {
        let configuration = try XCTUnwrap(GoogleDriveConfiguration(
            clientID: "public.apps.googleusercontent.com",
            redirectURI: "com.googleusercontent.apps.public:/oauthredirect"
        ))
        let pkce = GoogleDrivePKCE(randomBytes: Data(repeating: 7, count: 48))
        let request = try GoogleDriveAuthorizationRequest.make(
            configuration: configuration,
            state: "state-1",
            pkce: pkce
        )
        let items = try XCTUnwrap(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["scope"], GoogleDriveConfiguration.driveFileScope)
        XCTAssertEqual(values["access_type"], "offline")
        XCTAssertEqual(values["prompt"], "consent")
        XCTAssertEqual(values["include_granted_scopes"], "false")
        XCTAssertEqual(values["trigger_onepick"], "true")
        XCTAssertEqual(values["allow_folder_selection"], "true")
        XCTAssertEqual(values["mimetypes"], GoogleDriveFileMetadata.folderMIMEType)
        XCTAssertNil(values["mimetype"])
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertFalse(pkce.verifier.contains("="))
    }

    func testPickerCallbackRequiresStateCodeAndImmutableFolderID() throws {
        let callback = try GoogleDriveAuthorizationCallback.parse(
            url: URL(string: "com.example:/oauth?state=s&code=c&picked_file_ids=f")!,
            expectedState: "s"
        )
        XCTAssertEqual(callback.code, "c")
        XCTAssertEqual(callback.selection.folderID, "f")
        XCTAssertNil(callback.selection.sharedDriveID)
        XCTAssertNil(callback.selection.resourceKey)

        XCTAssertThrowsError(try GoogleDriveAuthorizationCallback.parse(
            url: URL(string: "com.example:/oauth?state=other&code=c&picked_file_ids=f")!,
            expectedState: "s"
        ))
        XCTAssertThrowsError(try GoogleDriveAuthorizationCallback.parse(
            url: URL(string: "com.example:/oauth?state=s&code=c")!,
            expectedState: "s"
        ))
        XCTAssertThrowsError(try GoogleDriveAuthorizationCallback.parse(
            url: URL(string: "com.example:/oauth?state=s&code=c&picked_file_ids=f1,f2")!,
            expectedState: "s"
        ))
        XCTAssertThrowsError(try GoogleDriveAuthorizationCallback.parse(
            url: URL(string: "com.example:/oauth?state=s&code=c&picked_file_ids=f&error=access_denied")!,
            expectedState: "s"
        ))
    }

    @MainActor
    func testDestinationEnvelopePreservesUnknownAndCorruptRecords() throws {
        let suiteName = "GoogleDriveFoundationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let destination = makeDestination()
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(destination))
        let unknown: [String: Any] = ["kind": "future_destination", "payload": ["version": 9]]
        let corrupt: [String: Any] = ["kind": "google_drive", "payload": ["version": 99, "id": "bad"]]
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "records": [["kind": "google_drive", "payload": payload], unknown, corrupt]
        ]), forKey: GoogleDriveDestinationStore.storageKey)

        let store = GoogleDriveDestinationStore(userDefaults: defaults)
        XCTAssertEqual(store.destinations, [destination])
        XCTAssertEqual(store.unknownRecordCount, 2)
        store.upsert(destination)
        let reloaded = GoogleDriveDestinationStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.destinations, [destination])
        XCTAssertEqual(reloaded.unknownRecordCount, 2)
    }

    @MainActor
    func testApplicationScopedDestinationStoreReloadObservesCoordinatorWrites() throws {
        let suiteName = "GoogleDriveFoundationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let serviceStore = GoogleDriveDestinationStore(userDefaults: defaults)
        let coordinatorStore = GoogleDriveDestinationStore(userDefaults: defaults)
        let destination = makeDestination()

        coordinatorStore.upsert(destination)
        XCTAssertNil(serviceStore.destination(id: destination.id))
        serviceStore.reload()
        XCTAssertEqual(serviceStore.destination(id: destination.id), destination)
    }

    @MainActor
    func testManagedObjectStoreCorruptionAndTornJSONBlockReadsAndCreates() throws {
        for bytes in [Data("not-json".utf8), Data("[{\"version\":1".utf8)] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try bytes.write(to: root.appendingPathComponent("managed-objects.json"))
            let store = GoogleDriveManagedObjectStore(rootURL: root)
            XCTAssertThrowsError(try store.binding(destinationID: UUID(), relativePathHash: "path"))
            XCTAssertThrowsError(try store.upsert(GoogleDriveManagedObjectBinding(
                destinationID: UUID(),
                relativePathHash: "path",
                objectID: "object",
                parentID: "parent",
                expectedName: "name",
                mimeType: "text/plain"
            )))
        }
    }

    func testPrivacyDisclosureNamesSensitiveHealthGoogleAndRetention() {
        XCTAssertTrue(GoogleDrivePrivacyDisclosure.title.localizedCaseInsensitiveContains("health"))
        XCTAssertTrue(GoogleDrivePrivacyDisclosure.message.localizedCaseInsensitiveContains("Google"))
        XCTAssertTrue(GoogleDrivePrivacyDisclosure.message.localizedCaseInsensitiveContains("retain"))
        XCTAssertTrue(GoogleDrivePrivacyDisclosure.message.localizedCaseInsensitiveContains("servers"))
    }

    func testOAuthAndTransientHTTPFailuresHaveDistinctTaxonomy() {
        let invalidGrant = #"{"error":"invalid_grant"}"#.data(using: .utf8)!
        XCTAssertEqual(GoogleDriveHTTPErrorMapper.error(statusCode: 400, responseData: invalidGrant).id, .reauthorizationRequired)
        let rateLimited = GoogleDriveHTTPErrorMapper.error(statusCode: 429)
        XCTAssertEqual(rateLimited.id, .rateLimited)
        XCTAssertTrue(rateLimited.isRetryable)
        let serverFailure = GoogleDriveHTTPErrorMapper.error(statusCode: 503)
        XCTAssertEqual(serverFailure.id, .ambiguousCommit)
        XCTAssertTrue(serverFailure.isRetryable)
    }

    @MainActor
    func testReauthorizationReusesBindingOnlyForSameAccountAndFolder() {
        let destination = makeDestination()
        let sameFolder = GoogleDriveFileMetadata(
            id: destination.folderID,
            name: "Selected",
            mimeType: GoogleDriveFileMetadata.folderMIMEType,
            parents: [],
            driveID: destination.sharedDriveID,
            trashed: false,
            canAddChildren: true
        )
        XCTAssertTrue(GoogleDriveConnectionManager.isExactReauthorization(
            destination,
            permissionID: destination.accountPermissionID,
            folder: sameFolder
        ))
        XCTAssertFalse(GoogleDriveConnectionManager.isExactReauthorization(
            destination,
            permissionID: "another-account",
            folder: sameFolder
        ))
        let anotherFolder = GoogleDriveFileMetadata(
            id: "another-folder",
            name: "Another",
            mimeType: GoogleDriveFileMetadata.folderMIMEType,
            parents: [],
            driveID: destination.sharedDriveID,
            trashed: false,
            canAddChildren: true
        )
        XCTAssertFalse(GoogleDriveConnectionManager.isExactReauthorization(
            destination,
            permissionID: destination.accountPermissionID,
            folder: anotherFolder
        ))
    }

    @MainActor
    func testFutureDestinationEnvelopeAndScalarRecordsRemainUnrunnable() throws {
        let suiteName = "GoogleDriveFoundationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "version": 99,
            "records": [["kind": "google_drive", "payload": ["version": 1]], "future-scalar"]
        ]), forKey: GoogleDriveDestinationStore.storageKey)

        let store = GoogleDriveDestinationStore(userDefaults: defaults)
        XCTAssertTrue(store.destinations.isEmpty)
        XCTAssertEqual(store.unknownRecordCount, 1)
        store.upsert(makeDestination())
        XCTAssertTrue(store.destinations.isEmpty)
        XCTAssertEqual(GoogleDriveDestinationStore(userDefaults: defaults).unknownRecordCount, 1)

        defaults.set(try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "records": ["future-scalar"]
        ]), forKey: GoogleDriveDestinationStore.storageKey)
        let scalarStore = GoogleDriveDestinationStore(userDefaults: defaults)
        XCTAssertEqual(scalarStore.unknownRecordCount, 1)
        scalarStore.upsert(makeDestination())
        let scalarReloaded = GoogleDriveDestinationStore(userDefaults: defaults)
        XCTAssertEqual(scalarReloaded.destinations.count, 1)
        XCTAssertEqual(scalarReloaded.unknownRecordCount, 1)
    }

    @MainActor
    func testMissingBuildConfigurationIsVisibleButNotRunnable() {
        let manager = GoogleDriveConnectionManager(configuration: nil)
        XCTAssertEqual(manager.readiness, .configurationMissing)
        XCTAssertEqual(manager.lastErrorID, .configurationMissing)
    }

    func testGeneratedBundleRejectsPortablePathCollision() throws {
        let first = try GoogleDriveGeneratedArtifact(
            id: GoogleDriveDigest.sha256(Data("a".utf8)),
            relativePath: "Health/A.md",
            mediaType: "text/markdown",
            writeIntent: .overwrite,
            fragmentBytes: Data("a".utf8)
        )
        let second = try GoogleDriveGeneratedArtifact(
            id: GoogleDriveDigest.sha256(Data("b".utf8)),
            relativePath: "health/a.md",
            mediaType: "text/markdown",
            writeIntent: .overwrite,
            fragmentBytes: Data("b".utf8)
        )
        XCTAssertThrowsError(try GoogleDriveGeneratedArtifactBundle(
            profileID: nil,
            sourceDates: [],
            settingsDigest: "settings",
            rendererIdentity: "renderer",
            artifacts: [first, second]
        ))
    }

    func testFinalByteMergersMatchExistingAppendAndMarkdownSemantics() throws {
        let appended = try GoogleDriveFinalByteMerger.merge(
            baseline: Data("old".utf8),
            fragment: Data("new".utf8),
            intent: .append
        )
        XCTAssertEqual(String(data: appended, encoding: .utf8), "old\n\nnew")
        XCTAssertEqual(
            try GoogleDriveFinalByteMerger.merge(baseline: appended, fragment: Data("new".utf8), intent: .append),
            appended
        )
        XCTAssertThrowsError(try GoogleDriveFinalByteMerger.merge(
            baseline: Data([0xff, 0xfe]),
            fragment: Data("new".utf8),
            intent: .append
        ))

        let existing = "My preamble\n\n## Sleep\nold\n\n## Notes\nkeep\n"
        let generated = "Generated preamble\n\n## Sleep\nnew\n"
        let daily = try GoogleDriveFinalByteMerger.merge(
            baseline: Data(existing.utf8),
            fragment: Data(generated.utf8),
            intent: .dailyNoteMerge
        )
        let value = try XCTUnwrap(String(data: daily, encoding: .utf8))
        XCTAssertTrue(value.contains("My preamble"))
        XCTAssertTrue(value.contains("## Sleep\nnew"))
        XCTAssertTrue(value.contains("## Notes\nkeep"))
        XCTAssertFalse(value.contains("Generated preamble"))
    }

    func testProtectedJournalDetectsSpoolTamperingAndRetainsDestinationSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journalStore = try GoogleDriveJournalStore(rootURL: root)
        let bytes = Data("synthetic,not-health-data".utf8)
        let artifact = try GoogleDriveGeneratedArtifact(
            id: GoogleDriveDigest.sha256(bytes),
            relativePath: "Health/test.csv",
            mediaType: "text/csv",
            writeIntent: .overwrite,
            fragmentBytes: bytes
        )
        let bundle = try GoogleDriveGeneratedArtifactBundle(
            operationID: UUID(),
            profileID: UUID(),
            sourceDates: [Date(timeIntervalSince1970: 0)],
            settingsDigest: "settings",
            rendererIdentity: "apple_health_data_v8/native",
            artifacts: [artifact]
        )
        let destination = makeDestination()
        let journal = try await journalStore.create(bundle: bundle, destination: destination)
        XCTAssertEqual(journal.destinationSnapshot, GoogleDriveDestinationSnapshot(destination: destination))
        let stagedBytes = try await journalStore.readSpool(
            operationID: bundle.operationID,
            filename: journal.artifacts[0].fragmentFilename,
            expectedSHA256: artifact.sha256
        )
        XCTAssertEqual(stagedBytes, bytes)
        try await journalStore.writeSpool(
            operationID: bundle.operationID,
            filename: journal.artifacts[0].fragmentFilename,
            data: Data("changed".utf8)
        )
        do {
            _ = try await journalStore.readSpool(
                operationID: bundle.operationID,
                filename: journal.artifacts[0].fragmentFilename,
                expectedSHA256: artifact.sha256
            )
            XCTFail("Expected checksum mismatch")
        } catch let error as GoogleDriveError {
            XCTAssertEqual(error.id, .checksumMismatch)
        }
    }

    @MainActor
    func testRunnerFailsClosedInsteadOfReplacingCorruptExistingJournal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journalStore = try GoogleDriveJournalStore(rootURL: root)
        let bytes = Data("immutable".utf8)
        let artifact = try GoogleDriveGeneratedArtifact(
            id: GoogleDriveDigest.sha256(bytes),
            relativePath: "Health/day.md",
            mediaType: "text/markdown",
            writeIntent: .overwrite,
            fragmentBytes: bytes
        )
        let bundle = try GoogleDriveGeneratedArtifactBundle(
            operationID: UUID(),
            profileID: nil,
            sourceDates: [Date(timeIntervalSince1970: 0)],
            settingsDigest: "settings",
            rendererIdentity: "renderer",
            artifacts: [artifact]
        )
        let destination = makeDestination()
        _ = try await journalStore.create(bundle: bundle, destination: destination)
        let journalURL = root.appendingPathComponent("journals/\(bundle.operationID.uuidString.lowercased()).json")
        try Data("corrupt".utf8).write(to: journalURL)

        let runner = try GoogleDriveDestinationRunner(journalStore: journalStore)
        let result = await runner.run(bundle: bundle, destination: destination, accessToken: "unused")

        XCTAssertEqual(result.errorID, .remoteConflict)
        XCTAssertEqual(try Data(contentsOf: journalURL), Data("corrupt".utf8))
    }

    func testUnresolvedJournalBlocksDisconnectAndAgesToExplicitAbandonedNotice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journalStore = try GoogleDriveJournalStore(
            rootURL: root,
            now: { Date(timeIntervalSince1970: 1_000) },
            unresolvedRetention: -1
        )
        let bytes = Data("sensitive-staged-bytes".utf8)
        let artifact = try GoogleDriveGeneratedArtifact(
            id: GoogleDriveDigest.sha256(bytes),
            relativePath: "Health/day.json",
            mediaType: "application/json",
            writeIntent: .overwrite,
            fragmentBytes: bytes
        )
        let destination = makeDestination()
        let bundle = try GoogleDriveGeneratedArtifactBundle(
            operationID: UUID(),
            profileID: nil,
            sourceDates: [Date(timeIntervalSince1970: 100)],
            settingsDigest: "settings",
            rendererIdentity: "renderer",
            artifacts: [artifact]
        )
        _ = try await journalStore.create(bundle: bundle, destination: destination)
        do {
            try await journalStore.cleanupForDisconnect(destinationID: destination.id)
            XCTFail("Unresolved journal must block credential destruction")
        } catch let error as GoogleDriveError {
            XCTAssertEqual(error.id, .partialCompletion)
        }

        try await journalStore.prune()
        let journalRemains = await journalStore.contains(operationID: bundle.operationID)
        XCTAssertFalse(journalRemains)
        let isAbandoned = await journalStore.isAbandoned(operationID: bundle.operationID)
        XCTAssertTrue(isAbandoned)
        let notices = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("abandoned-operations.json"))
        ) as? [[String: Any]]
        XCTAssertEqual(notices?.first?["operation_id"] as? String, bundle.operationID.uuidString.lowercased())
        XCTAssertNil(notices?.first?["relative_path"])
    }

    func testAcknowledgedJournalRetentionActuallyPrunesExpiredBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let createdAt = Date(timeIntervalSince1970: 100)
        let journalStore = try GoogleDriveJournalStore(
            rootURL: root,
            now: { Date(timeIntervalSince1970: 1_000) },
            retention: -1
        )
        let bytes = Data("retained".utf8)
        let artifact = try GoogleDriveGeneratedArtifact(
            id: GoogleDriveDigest.sha256(bytes),
            relativePath: "Health/day.json",
            mediaType: "application/json",
            writeIntent: .overwrite,
            fragmentBytes: bytes
        )
        let bundle = try GoogleDriveGeneratedArtifactBundle(
            operationID: UUID(),
            profileID: nil,
            sourceDates: [createdAt],
            settingsDigest: "settings",
            rendererIdentity: "renderer",
            artifacts: [artifact]
        )
        _ = try await journalStore.create(bundle: bundle, destination: makeDestination())
        try await journalStore.markAcknowledged(operationID: bundle.operationID)
        try await journalStore.prune()
        let remains = await journalStore.contains(operationID: bundle.operationID)
        XCTAssertFalse(remains)
    }

    @MainActor
    func testRunnerUsesExactIDPostflightInsteadOfTrustingUploadResponseMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("immutable-final".utf8)
        let destination = makeDestination()
        let api = ExactPostflightDriveAPI(bytes: bytes, destination: destination)
        let runner = try GoogleDriveDestinationRunner(
            api: api,
            managedStore: GoogleDriveManagedObjectStore(rootURL: root),
            journalStore: GoogleDriveJournalStore(rootURL: root)
        )
        let artifact = try GoogleDriveGeneratedArtifact(
            id: GoogleDriveDigest.sha256(bytes),
            relativePath: "day.json",
            mediaType: "application/json",
            writeIntent: .overwrite,
            fragmentBytes: bytes
        )
        let bundle = try GoogleDriveGeneratedArtifactBundle(
            operationID: UUID(),
            profileID: nil,
            sourceDates: [Date(timeIntervalSince1970: 0)],
            settingsDigest: "settings",
            rendererIdentity: "renderer",
            artifacts: [artifact]
        )

        let result = await runner.run(bundle: bundle, destination: destination, accessToken: "token")

        XCTAssertTrue(result.isComplete)
        let metadataRequestCount = await api.exactMetadataRequestCount()
        XCTAssertEqual(metadataRequestCount, 1)
    }

    func testResumableCreatePersistsOperationIDAsIdempotencyMarker() async throws {
        let operationID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let transport = RecordingDriveTransport { request in
            (Data(), HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Location": "https://www.googleapis.com/upload/session"]
            )!)
        }
        let client = GoogleDriveAPIClient(transport: transport)
        _ = try await client.startResumableCreate(
            id: "reserved",
            name: "day.json",
            parentID: "folder",
            mediaType: "application/json",
            byteCount: 10,
            sha256: String(repeating: "a", count: 64),
            pathHash: String(repeating: "b", count: 64),
            operationID: operationID,
            resourceKeys: [:],
            accessToken: "secret"
        )
        let recordedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try XCTUnwrap(root["appProperties"] as? [String: String])
        XCTAssertEqual(properties["healthmd_operation_id"], operationID.uuidString.lowercased())
        XCTAssertEqual(properties["healthmd_path_hash"], String(repeating: "b", count: 64))
    }

    func testSameNameCollisionSearchConsumesEveryPage() async throws {
        let transport = RecordingDriveTransport { request in
            let token = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pageToken" })?.value
            let body = token == nil
                ? #"{"files":[{"id":"one","name":"day.md","mimeType":"text/markdown","parents":["folder"],"trashed":false}],"nextPageToken":"page-2"}"#
                : #"{"files":[{"id":"two","name":"day.md","mimeType":"text/markdown","parents":["folder"],"trashed":false}]}"#
            return (Data(body.utf8), HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!)
        }
        let client = GoogleDriveAPIClient(transport: transport)
        let matches = try await client.findManagedObjects(
            parentID: "folder",
            name: "day.md",
            pathHash: GoogleDrivePath.hash("day.md"),
            resourceKeys: [:],
            accessToken: "secret"
        )
        XCTAssertEqual(matches.map(\.id), ["one", "two"])
    }

    func testAPIClientSetsSharedDriveFlagsAndResourceKey() async throws {
        let transport = RecordingDriveTransport { request in
            let body = #"{"id":"folder","name":"Selected","mimeType":"application/vnd.google-apps.folder","parents":[],"driveId":"shared","resourceKey":"rk","version":"1","trashed":false,"capabilities":{"canAddChildren":true}}"#.data(using: .utf8)!
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let client = GoogleDriveAPIClient(transport: transport)
        _ = try await client.metadata(id: "folder", resourceKey: "rk", accessToken: "secret")
        let recordedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "supportsAllDrives" })?.value, "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Drive-Resource-Keys"), "folder/rk")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    private func makeDestination() -> GoogleDriveDestination {
        GoogleDriveDestination(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            credentialReferenceID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            accountPermissionID: "permission",
            folderID: "folder",
            sharedDriveID: "shared",
            resourceKey: "resource",
            folderLabel: "Selected folder",
            canAddChildren: true,
            lastValidatedAt: Date(timeIntervalSince1970: 1)
        )
    }

}

private actor ExactPostflightDriveAPI: GoogleDriveAPIClientProtocol {
    private let bytes: Data
    private let destination: GoogleDriveDestination
    private var metadataRequests = 0

    init(bytes: Data, destination: GoogleDriveDestination) {
        self.bytes = bytes
        self.destination = destination
    }

    func exactMetadataRequestCount() -> Int { metadataRequests }

    func about(accessToken: String) async throws -> String { destination.accountPermissionID }

    func metadata(id: String, resourceKey: String?, accessToken: String) async throws -> GoogleDriveFileMetadata {
        metadataRequests += 1
        return fileMetadata(sha256: GoogleDriveDigest.sha256(bytes))
    }

    func validateFolder(_ destination: GoogleDriveDestination, accessToken: String) async throws -> GoogleDriveFileMetadata {
        GoogleDriveFileMetadata(
            id: destination.folderID,
            name: "Selected",
            mimeType: GoogleDriveFileMetadata.folderMIMEType,
            parents: [],
            driveID: destination.sharedDriveID,
            trashed: false,
            canAddChildren: true
        )
    }

    func generateIDs(count: Int, accessToken: String) async throws -> [String] { ["reserved-file"] }

    func createFolder(
        id: String,
        name: String,
        parentID: String,
        pathHash: String,
        operationID: UUID,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> GoogleDriveFileMetadata {
        throw GoogleDriveError(.remoteConflict)
    }

    func findManagedObjects(
        parentID: String,
        name: String,
        pathHash: String,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> [GoogleDriveFileMetadata] { [] }

    func startResumableCreate(
        id: String,
        name: String,
        parentID: String,
        mediaType: String,
        byteCount: UInt64,
        sha256: String,
        pathHash: String,
        operationID: UUID,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> URL {
        URL(string: "https://www.googleapis.com/upload/session")!
    }

    func startResumableUpdate(
        id: String,
        mediaType: String,
        byteCount: UInt64,
        sha256: String,
        pathHash: String,
        operationID: UUID,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> URL {
        throw GoogleDriveError(.remoteConflict)
    }

    func upload(
        sessionURL: URL,
        data: Data,
        offset: UInt64,
        totalByteCount: UInt64,
        accessToken: String
    ) async throws -> GoogleDriveUploadResponse {
        // Deliberately wrong response checksum: runner must ignore it and exact-ID GET postflight.
        .completed(fileMetadata(sha256: String(repeating: "0", count: 64)))
    }

    func uploadStatus(
        sessionURL: URL,
        totalByteCount: UInt64,
        accessToken: String
    ) async throws -> GoogleDriveUploadResponse {
        throw GoogleDriveError(.ambiguousCommit)
    }

    func download(id: String, resourceKey: String?, accessToken: String) async throws -> Data { bytes }

    private func fileMetadata(sha256: String) -> GoogleDriveFileMetadata {
        GoogleDriveFileMetadata(
            id: "reserved-file",
            name: "day.json",
            mimeType: "application/json",
            parents: [destination.folderID],
            version: "1",
            size: UInt64(bytes.count),
            sha256Checksum: sha256,
            trashed: false,
            appProperties: [
                "healthmd_owner": "healthmd",
                "healthmd_path_hash": GoogleDrivePath.hash("day.json")
            ]
        )
    }
}

private actor BindingTestGate {
    let started: XCTestExpectation
    var continuation: CheckedContinuation<Void, Never>?
    init(started: XCTestExpectation) { self.started = started }
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class BindingTestAuthorizer: GoogleDriveWebAuthorizing {
    let gate: BindingTestGate?
    var calls = 0
    init(gate: BindingTestGate? = nil) { self.gate = gate }
    func authorize(_ request: GoogleDriveAuthorizationRequest) async throws -> URL {
        calls += 1
        if let gate { await gate.pause() }
        return URL(string: "com.googleusercontent.apps.public:/oauthredirect?state=\(request.state)&code=synthetic&picked_file_ids=folder")!
    }
}

private actor BindingTestTransport: GoogleDriveHTTPTransport {
    let gate: BindingTestGate?
    let delayedPath: String
    private(set) var calls: [String: Int] = [:]
    init(gate: BindingTestGate?, delayedPath: String) {
        self.gate = gate
        self.delayedPath = delayedPath
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls[request.url!.path, default: 0] += 1
        if request.url!.path == delayedPath, let gate { await gate.pause() }
        let body: String
        switch request.url!.path {
        case "/token":
            body = #"{"access_token":"synthetic","refresh_token":"synthetic-refresh","expires_in":3600,"scope":"https://www.googleapis.com/auth/drive.file"}"#
        case "/drive/v3/about":
            body = #"{"user":{"permissionId":"synthetic-permission"}}"#
        case "/drive/v3/files/folder":
            body = #"{"id":"folder","name":"Synthetic","mimeType":"application/vnd.google-apps.folder","capabilities":{"canAddChildren":true}}"#
        case "/revoke":
            body = ""
        default: throw GoogleDriveError(.folderUnavailable)
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

// The write counter is used only by main-actor tests; UserDefaults is not Sendable.
private final class BindingTestDefaults: UserDefaults {
    var destinationWrites = 0
    override func set(_ value: Any?, forKey key: String) {
        if key == "googleDrive.destinations.envelope" { destinationWrites += 1 }
        super.set(value, forKey: key)
    }
}

private final class BindingTestKeychain: KeychainStoring, @unchecked Sendable {
    var values: [String: String] = [:]
    var writeCount = 0
    var removeCount = 0
    func readInt(key: String) -> Int { 0 }
    func writeInt(key: String, value: Int) { writeCount += 1 }
    func readString(key: String) -> String? { values[key] }
    func readStringOrThrow(key: String) throws -> String? { values[key] }
    func writeString(key: String, value: String) { writeCount += 1; values[key] = value }
    func writeStringOrThrow(key: String, value: String) throws { writeString(key: key, value: value) }
    func remove(key: String) { removeCount += 1; values.removeValue(forKey: key) }
    func removeOrThrow(key: String) throws { remove(key: key) }
}

private actor RecordingDriveTransport: GoogleDriveHTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    private let handler: Handler
    private var request: URLRequest?

    init(handler: @escaping Handler) { self.handler = handler }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return try handler(request)
    }

    func lastRequest() -> URLRequest? { request }
}
