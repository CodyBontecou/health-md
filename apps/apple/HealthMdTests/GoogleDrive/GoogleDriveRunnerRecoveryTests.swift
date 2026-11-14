import Foundation
import XCTest
@testable import HealthMd

/// Dependency-free runner boundary: actual protected stores are reopened on every resume.
@MainActor
final class GoogleDriveRunnerRecoveryTests: XCTestCase {
    nonisolated deinit {}

    func testCommittedUpdateReconcilesCompletedSessionBeforeBundlePreflight() async throws {
        try await committedUpdate(expired: false)
    }

    func testCommittedUpdateReconcilesExpiredSessionBeforeBundlePreflight() async throws {
        try await committedUpdate(expired: true)
    }

    private func committedUpdate(expired: Bool) async throws {
        let h = try Harness(existing: true)
        defer { h.cleanup() }
        await h.api.configure(expired: expired)
        let first = await (try h.runner()).run(bundle: h.bundle, destination: h.destination, accessToken: "synthetic")
        XCTAssertFalse(first.isComplete)
        let retained = try await h.journals().load(operationID: h.bundle.operationID)
        XCTAssertEqual(retained.artifacts[0].phase, .uploadSessionStarted)
        let frozen = try await h.journals().readSpool(operationID: retained.id,
            filename: XCTUnwrap(retained.artifacts[0].finalFilename),
            expectedSHA256: XCTUnwrap(retained.artifacts[0].finalSHA256))
        let result = await (try h.runner()).resume(operationID: retained.id, destination: h.destination, accessToken: "synthetic")
        XCTAssertTrue(result.isComplete, "\(String(describing: result.errorID))")
        let state = await h.api.state()
        XCTAssertEqual(state.bytes, frozen)
        XCTAssertEqual(state.commits, 1)
        XCTAssertEqual(state.uploads, 1)
        XCTAssertGreaterThan(state.probes, 0)
        let recovered = try await h.journals().load(operationID: retained.id)
        XCTAssertEqual(recovered.destinationSnapshot, retained.destinationSnapshot)
        XCTAssertEqual(recovered.artifacts[0].objectID, "original")
        XCTAssertEqual(recovered.artifacts[0].phase, .verified)
    }

    func testCommittedUpdateRejectsChangedBytesIdentityParentNameTypeAndTrash() async throws {
        for mutation in ["bytes", "id", "parent", "name", "type", "trash"] {
            let h = try Harness(existing: true)
            defer { h.cleanup() }
            await h.api.configure(expired: true)
            _ = await (try h.runner()).run(bundle: h.bundle, destination: h.destination, accessToken: "synthetic")
            await h.api.mutate(mutation)
            let result = await (try h.runner()).resume(operationID: h.bundle.operationID, destination: h.destination, accessToken: "synthetic")
            XCTAssertEqual(result.errorID, .remoteConflict, mutation)
            let state = await h.api.state()
            XCTAssertEqual(state.uploads, 1, mutation)
            XCTAssertEqual(state.commits, 1, mutation)
        }
    }

    func testConcurrentEditWithoutSessionStillRejectsIntendedBytes() async throws {
        let h = try Harness(existing: true)
        defer { h.cleanup() }
        _ = await (try h.runner()).run(bundle: h.bundle, destination: h.destination, accessToken: "synthetic")
        var journal = try await h.journals().load(operationID: h.bundle.operationID)
        journal.artifacts[0].uploadSessionURL = nil
        journal.artifacts[0].phase = .finalPersisted
        try await h.journals().save(journal)
        let result = await (try h.runner()).resume(operationID: journal.id, destination: h.destination, accessToken: "synthetic")
        XCTAssertEqual(result.errorID, .remoteConflict)
    }

    func testNoBaselineOrSessionCannotAdoptMatchingConcurrentObject() async throws {
        let h = try Harness(existing: false)
        defer { h.cleanup() }
        let journals = try h.journals()
        var journal = try await journals.create(bundle: h.bundle, destination: h.destination)
        let bytes = h.bundle.artifacts[0].fragmentBytes
        try await journals.writeSpool(operationID: journal.id, filename: "0-final.bin", data: bytes)
        journal.artifacts[0].objectID = "reserved"
        journal.artifacts[0].parentID = "folder"
        journal.artifacts[0].finalFilename = "0-final.bin"
        journal.artifacts[0].finalByteCount = UInt64(bytes.count)
        journal.artifacts[0].finalSHA256 = GoogleDriveDigest.sha256(bytes)
        journal.artifacts[0].phase = .identityReserved
        try await journals.save(journal)
        await h.api.occupyReservedID(bytes: bytes)
        let result = await (try h.runner()).resume(operationID: journal.id, destination: h.destination, accessToken: "synthetic")
        XCTAssertEqual(result.errorID, .remoteConflict)
        let state = await h.api.state()
        XCTAssertEqual(state.creates, 1, "attempt create, never adopt a matching unrelated object")
        XCTAssertEqual(state.uploads, 0)
        XCTAssertEqual(state.commits, 0)
        let retained = try await journals.load(operationID: journal.id)
        XCTAssertNotEqual(retained.artifacts[0].phase, .verified)
    }

    func testResumeRejectsDifferentDestinationAndAccount() async throws {
        let h = try Harness(existing: true)
        defer { h.cleanup() }
        _ = await (try h.runner()).run(bundle: h.bundle, destination: h.destination, accessToken: "synthetic")
        let other = GoogleDriveDestination(credentialReferenceID: UUID(), accountPermissionID: "other", folderID: "other", canAddChildren: true)
        let result = await (try h.runner()).resume(operationID: h.bundle.operationID, destination: other, accessToken: "synthetic")
        XCTAssertEqual(result.errorID, .remoteConflict)
        await h.api.changeAccount()
        let account = await (try h.runner()).resume(operationID: h.bundle.operationID, destination: h.destination, accessToken: "synthetic")
        XCTAssertEqual(account.errorID, .accountMismatch)
    }

    func testReservedUncreatedIDCanResumeAfterFinalSpoolReadFailure() async throws {
        let h = try Harness(existing: false)
        defer { h.cleanup() }
        let journals = try h.journals()
        let journal = try await journals.create(bundle: h.bundle, destination: h.destination)
        let fragment = h.root.appendingPathComponent("spool/\(journal.id.uuidString.lowercased())/0-fragment.bin")
        let bytes = try Data(contentsOf: fragment)
        // Force the real preparation path to stop immediately after saving its reserved ID.
        try FileManager.default.removeItem(at: fragment)
        _ = await (try h.runner()).resume(operationID: journal.id, destination: h.destination, accessToken: "synthetic")
        let retained = try await journals.load(operationID: journal.id)
        XCTAssertEqual(retained.artifacts[0].phase, .identityReserved)
        XCTAssertEqual(retained.artifacts[0].objectID, "reserved")
        XCTAssertNil(retained.artifacts[0].finalFilename)
        try await journals.writeSpool(operationID: journal.id, filename: "0-fragment.bin", data: bytes)
        await h.api.configure(expired: false, cancel: false)
        let result = await (try h.runner()).resume(operationID: journal.id, destination: h.destination, accessToken: "synthetic")
        XCTAssertTrue(result.isComplete, "\(String(describing: result.errorID))")
        let state = await h.api.state()
        XCTAssertEqual(state.generatedIDs, 1)
        XCTAssertEqual(state.creates, 1)
        XCTAssertEqual(state.commits, 1)
        let recovered = try await journals.load(operationID: journal.id)
        XCTAssertEqual(recovered.artifacts[0].objectID, "reserved")
    }

    @MainActor
    private final class Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = GoogleDriveDestination(credentialReferenceID: UUID(), accountPermissionID: "synthetic-account", folderID: "folder", canAddChildren: true)
        let api: RecoveryDriveAPI
        let bundle: GoogleDriveGeneratedArtifactBundle
        init(existing: Bool) throws {
            let fragment = Data("synthetic-fragment".utf8)
            bundle = try GoogleDriveGeneratedArtifactBundle(profileID: nil, sourceDates: [], settingsDigest: "synthetic", rendererIdentity: "synthetic", artifacts: [
                GoogleDriveGeneratedArtifact(id: GoogleDriveDigest.sha256(fragment), relativePath: "note.json", mediaType: "application/json", writeIntent: .append, fragmentBytes: fragment)
            ])
            api = RecoveryDriveAPI(existing: existing)
            if existing {
                try GoogleDriveManagedObjectStore(rootURL: root).upsert(GoogleDriveManagedObjectBinding(destinationID: destination.id,
                    relativePathHash: GoogleDrivePath.hash("note.json"), objectID: "original", parentID: "folder", expectedName: "note.json", mimeType: "application/json"))
            }
        }
        func journals() throws -> GoogleDriveJournalStore { try GoogleDriveJournalStore(rootURL: root) }
        func runner() throws -> GoogleDriveDestinationRunner {
            try GoogleDriveDestinationRunner(api: api, managedStore: GoogleDriveManagedObjectStore(rootURL: root), journalStore: journals())
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}

private actor RecoveryDriveAPI: GoogleDriveAPIClientProtocol {
    private var remote: GoogleDriveFileMetadata?
    private var bytes: Data?
    private var expired = false
    private var cancel = true
    private var wrongAccount = false
    private var commits = 0
    private var uploads = 0
    private var probes = 0
    private var generatedIDs = 0
    private var creates = 0
    init(existing: Bool) {
        if existing {
            let data = Data("synthetic-baseline".utf8)
            bytes = data
            remote = GoogleDriveFileMetadata(id: "original", name: "note.json", mimeType: "application/json", parents: ["folder"], version: "1", size: UInt64(data.count), sha256Checksum: GoogleDriveDigest.sha256(data), trashed: false)
        }
    }
    func configure(expired: Bool, cancel: Bool = true) { self.expired = expired; self.cancel = cancel }
    func changeAccount() { wrongAccount = true }
    func state() -> (bytes: Data?, commits: Int, uploads: Int, probes: Int, generatedIDs: Int, creates: Int) {
        (bytes, commits, uploads, probes, generatedIDs, creates)
    }
    func occupyReservedID(bytes: Data) {
        self.bytes = bytes
        remote = GoogleDriveFileMetadata(id: "reserved", name: "note.json", mimeType: "application/json", parents: ["folder"], version: "1", size: UInt64(bytes.count), sha256Checksum: GoogleDriveDigest.sha256(bytes), trashed: false)
    }
    func mutate(_ kind: String) {
        let old = remote!
        if kind == "bytes" { bytes = Data("concurrent-edit".utf8) }
        remote = GoogleDriveFileMetadata(id: kind == "id" ? "other" : old.id,
            name: kind == "name" ? "renamed" : old.name, mimeType: kind == "type" ? "text/plain" : old.mimeType,
            parents: kind == "parent" ? ["other"] : old.parents, version: "3", size: UInt64(bytes!.count),
            sha256Checksum: GoogleDriveDigest.sha256(bytes!), trashed: kind == "trash")
    }
    func about(accessToken: String) async throws -> String { wrongAccount ? "other" : "synthetic-account" }
    func validateFolder(_ destination: GoogleDriveDestination, accessToken: String) async throws -> GoogleDriveFileMetadata {
        guard try await about(accessToken: accessToken) == destination.accountPermissionID else { throw GoogleDriveError(.accountMismatch) }
        return GoogleDriveFileMetadata(id: "folder", name: "Synthetic", mimeType: GoogleDriveFileMetadata.folderMIMEType, parents: [], trashed: false, canAddChildren: true)
    }
    func metadata(id: String, resourceKey: String?, accessToken: String) async throws -> GoogleDriveFileMetadata {
        guard let remote else { throw GoogleDriveError(.folderUnavailable) }
        return remote
    }
    func generateIDs(count: Int, accessToken: String) async throws -> [String] { generatedIDs += 1; return ["reserved"] }
    func createFolder(id: String, name: String, parentID: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> GoogleDriveFileMetadata { throw GoogleDriveError(.remoteConflict) }
    func findManagedObjects(parentID: String, name: String, pathHash: String, resourceKeys: [String: String], accessToken: String) async throws -> [GoogleDriveFileMetadata] { [] }
    func startResumableCreate(id: String, name: String, parentID: String, mediaType: String, byteCount: UInt64, sha256: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> URL {
        creates += 1
        guard remote == nil else { throw GoogleDriveError(.remoteConflict) }
        remote = GoogleDriveFileMetadata(id: id, name: name, mimeType: mediaType, parents: [parentID], version: "0", trashed: false)
        return URL(string: "https://www.googleapis.com/upload/synthetic")!
    }
    func startResumableUpdate(id: String, mediaType: String, byteCount: UInt64, sha256: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> URL { URL(string: "https://www.googleapis.com/upload/synthetic")! }
    func upload(sessionURL: URL, data: Data, offset: UInt64, totalByteCount: UInt64, accessToken: String) async throws -> GoogleDriveUploadResponse {
        uploads += 1
        let old = remote!
        bytes = data
        remote = GoogleDriveFileMetadata(id: old.id, name: old.name, mimeType: old.mimeType, parents: old.parents, version: "2", size: UInt64(data.count), sha256Checksum: GoogleDriveDigest.sha256(data), trashed: false)
        commits += 1
        if cancel { cancel = false; throw CancellationError() }
        return .completed(remote!)
    }
    func uploadStatus(sessionURL: URL, totalByteCount: UInt64, accessToken: String) async throws -> GoogleDriveUploadResponse {
        probes += 1
        if expired { throw GoogleDriveError(.folderUnavailable) }
        return .completed(remote!)
    }
    func download(id: String, resourceKey: String?, accessToken: String) async throws -> Data { bytes! }
}
