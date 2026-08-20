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
        XCTAssertEqual(values["mimetype"], GoogleDriveFileMetadata.folderMIMEType)
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertFalse(pkce.verifier.contains("="))
    }

    func testPickerCallbackRequiresStateCodeAndImmutableFolderID() throws {
        let callback = try GoogleDriveAuthorizationCallback.parse(
            url: URL(string: "com.example:/oauth?state=s&code=c&folder_id=f&drive_id=d&resource_key=r")!,
            expectedState: "s"
        )
        XCTAssertEqual(callback.code, "c")
        XCTAssertEqual(callback.selection.folderID, "f")
        XCTAssertEqual(callback.selection.sharedDriveID, "d")
        XCTAssertEqual(callback.selection.resourceKey, "r")

        XCTAssertThrowsError(try GoogleDriveAuthorizationCallback.parse(
            url: URL(string: "com.example:/oauth?state=other&code=c&folder_id=f")!,
            expectedState: "s"
        ))
        XCTAssertThrowsError(try GoogleDriveAuthorizationCallback.parse(
            url: URL(string: "com.example:/oauth?state=s&code=c")!,
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
