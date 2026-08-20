import Foundation
import XCTest
@testable import HealthMd

final class GoogleDriveFoundationTests: XCTestCase {
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
