//
//  RuntimeProtocolTests.swift
//  HealthMdTests
//
//  TDD tests for runtime service protocol seams.
//  Validates that fake implementations work correctly and that
//  managers can accept injected dependencies.
//

import XCTest
import Darwin
@testable import HealthMd

// MARK: - Fake Implementations

final class FakeKeychainStore: KeychainStoring, @unchecked Sendable {
    var storage: [String: Int] = [:]
    var stringStorage: [String: String] = [:]
    var nextReadStringError: Error?
    var nextWriteStringError: Error?
    var nextRemoveError: Error?

    func readInt(key: String) -> Int {
        storage[key] ?? 0
    }

    func writeInt(key: String, value: Int) {
        storage[key] = value
    }

    func readString(key: String) -> String? {
        stringStorage[key]
    }

    func readStringOrThrow(key: String) throws -> String? {
        if let error = nextReadStringError {
            nextReadStringError = nil
            throw error
        }
        return stringStorage[key]
    }

    func writeString(key: String, value: String) {
        stringStorage[key] = value
    }

    func writeStringOrThrow(key: String, value: String) throws {
        if let error = nextWriteStringError {
            nextWriteStringError = nil
            throw error
        }
        stringStorage[key] = value
    }

    func remove(key: String) {
        storage.removeValue(forKey: key)
        stringStorage.removeValue(forKey: key)
    }

    func removeOrThrow(key: String) throws {
        if let error = nextRemoveError {
            nextRemoveError = nil
            throw error
        }
        remove(key: key)
    }
}

final class FakeUserDefaults: UserDefaultsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String: Any] = [:]

    var storage: [String: Any] {
        get { lock.withLock { storedValues } }
        set { lock.withLock { storedValues = newValue } }
    }

    func string(forKey key: String) -> String? {
        lock.withLock { storedValues[key] as? String }
    }

    func bool(forKey key: String) -> Bool {
        lock.withLock { storedValues[key] as? Bool ?? false }
    }

    func integer(forKey key: String) -> Int {
        lock.withLock { storedValues[key] as? Int ?? 0 }
    }

    func data(forKey key: String) -> Data? {
        lock.withLock { storedValues[key] as? Data }
    }

    func set(_ value: Any?, forKey key: String) {
        lock.withLock { storedValues[key] = value }
    }

    func removeObject(forKey key: String) {
        lock.withLock { storedValues.removeValue(forKey: key) }
    }
}

final class FakeHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    var responses: [(Data, URLResponse)] = []
    var requestsMade: [URLRequest] = []
    var shouldThrow: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestsMade.append(request)
        if let error = shouldThrow { throw error }
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }
}

nonisolated final class RecordingFileCoordinator: FileCoordinating, @unchecked Sendable {
    struct Call: Equatable {
        let url: URL
        let intent: FileCoordinationWritingIntent
    }

    var calls: [Call] = []
    var redirectedURL: URL?
    var injectedError: Error?
    var beforeAccessor: (() -> Void)?

    func coordinateWriting<Output>(
        at url: URL,
        intent: FileCoordinationWritingIntent,
        cancellationCheck: () throws -> Void,
        accessor: (URL) throws -> Output
    ) throws -> Output {
        calls.append(Call(url: url, intent: intent))
        if let injectedError { throw injectedError }
        try cancellationCheck()
        beforeAccessor?()
        try cancellationCheck()
        return try accessor(redirectedURL ?? url)
    }
}

nonisolated final class FakeFileSystem: FileSystemAccessing, @unchecked Sendable {
    var files: [String: String] = [:]
    var directories: Set<String> = []
    var failBeforeWritingPathOnce: String?
    var failAfterWritingPathOnce: String?
    var writeStarted: ((URL) -> Void)?
    var writeBlocker: DispatchSemaphore?
    var readStarted: ((URL) -> Void)?
    var readCompleted: ((URL) -> Void)?
    var readBlocker: DispatchSemaphore?
    private(set) var writeCounts: [String: Int] = [:]

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        directories.insert(url.path)
    }

    func contentsOfFile(at url: URL) throws -> String {
        readStarted?(url)
        if let blocker = readBlocker {
            readBlocker = nil
            blocker.wait()
        }
        guard let content = files[url.path] else {
            throw NSError(domain: "FakeFS", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        readCompleted?(url)
        return content
    }

    func writeString(_ string: String, to url: URL, atomically: Bool) throws {
        writeStarted?(url)
        if let blocker = writeBlocker {
            writeBlocker = nil
            blocker.wait()
        }
        if failBeforeWritingPathOnce == url.path {
            failBeforeWritingPathOnce = nil
            throw NSError(
                domain: "FakeFS",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Injected failure before write"]
            )
        }
        files[url.path] = string
        writeCounts[url.path, default: 0] += 1
        if failAfterWritingPathOnce == url.path {
            failAfterWritingPathOnce = nil
            throw NSError(
                domain: "FakeFS",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Injected failure after write"]
            )
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
        var names = Set<String>()
        for path in files.keys where path.hasPrefix(prefix) {
            let remainder = String(path.dropFirst(prefix.count))
            if let first = remainder.split(separator: "/").first {
                names.insert(String(first))
            }
        }
        for path in directories where path.hasPrefix(prefix) {
            let remainder = String(path.dropFirst(prefix.count))
            if let first = remainder.split(separator: "/").first {
                names.insert(String(first))
            }
        }
        return names.sorted().map { url.appendingPathComponent($0) }
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
    }
}

// MARK: - KeychainStoring Tests

final class KeychainStoringTests: XCTestCase {

    func testFakeKeychain_readDefaultsToZero() {
        let keychain = FakeKeychainStore()
        XCTAssertEqual(keychain.readInt(key: "nonexistent"), 0)
    }

    func testFakeKeychain_writeAndRead() {
        let keychain = FakeKeychainStore()
        keychain.writeInt(key: "count", value: 3)
        XCTAssertEqual(keychain.readInt(key: "count"), 3)
    }

    func testFakeKeychain_overwrite() {
        let keychain = FakeKeychainStore()
        keychain.writeInt(key: "count", value: 1)
        keychain.writeInt(key: "count", value: 5)
        XCTAssertEqual(keychain.readInt(key: "count"), 5)
    }

    func testFakeKeychain_isolatedKeys() {
        let keychain = FakeKeychainStore()
        keychain.writeInt(key: "a", value: 10)
        keychain.writeInt(key: "b", value: 20)
        XCTAssertEqual(keychain.readInt(key: "a"), 10)
        XCTAssertEqual(keychain.readInt(key: "b"), 20)
    }

    func testFakeKeychain_removeClearsStoredValues() {
        let keychain = FakeKeychainStore()
        keychain.writeInt(key: "value", value: 3)
        keychain.writeString(key: "value", value: "token")

        keychain.remove(key: "value")

        XCTAssertEqual(keychain.readInt(key: "value"), 0)
        XCTAssertNil(keychain.readString(key: "value"))
    }
}

// MARK: - UserDefaultsStoring Tests

final class UserDefaultsStoringTests: XCTestCase {

    func testFakeDefaults_stringNilByDefault() {
        let defaults = FakeUserDefaults()
        XCTAssertNil(defaults.string(forKey: "missing"))
    }

    func testFakeDefaults_setAndReadString() {
        let defaults = FakeUserDefaults()
        defaults.set("hello", forKey: "key")
        XCTAssertEqual(defaults.string(forKey: "key"), "hello")
    }

    func testFakeDefaults_boolDefaultsFalse() {
        let defaults = FakeUserDefaults()
        XCTAssertFalse(defaults.bool(forKey: "flag"))
    }

    func testFakeDefaults_setAndReadBool() {
        let defaults = FakeUserDefaults()
        defaults.set(true, forKey: "flag")
        XCTAssertTrue(defaults.bool(forKey: "flag"))
    }

    func testFakeDefaults_integerDefaultsZero() {
        let defaults = FakeUserDefaults()
        XCTAssertEqual(defaults.integer(forKey: "count"), 0)
    }

    func testFakeDefaults_setAndReadData() {
        let defaults = FakeUserDefaults()
        let data = Data([0x01, 0x02])
        defaults.set(data, forKey: "blob")
        XCTAssertEqual(defaults.data(forKey: "blob"), data)
    }

    func testFakeDefaults_removeObject() {
        let defaults = FakeUserDefaults()
        defaults.set("value", forKey: "key")
        defaults.removeObject(forKey: "key")
        XCTAssertNil(defaults.string(forKey: "key"))
    }

    func testFakeDefaultsSupportsConcurrentProtocolAccess() {
        let defaults = FakeUserDefaults()
        DispatchQueue.concurrentPerform(iterations: 256) { index in
            let key = "key-\(index % 8)"
            defaults.set(Data([UInt8(index % 256)]), forKey: key)
            _ = defaults.data(forKey: key)
            _ = defaults.storage
        }
        XCTAssertLessThanOrEqual(defaults.storage.count, 8)
    }
}

// MARK: - HTTPClientProtocol Tests

final class HTTPClientProtocolTests: XCTestCase {

    func testFakeHTTP_recordsRequests() async throws {
        let client = FakeHTTPClient()
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client.responses.append((Data(), response))

        let request = URLRequest(url: URL(string: "https://example.com/test")!)
        _ = try await client.data(for: request)

        XCTAssertEqual(client.requestsMade.count, 1)
        XCTAssertEqual(client.requestsMade[0].url?.absoluteString, "https://example.com/test")
    }

    func testFakeHTTP_returnsConfiguredResponse() async throws {
        let client = FakeHTTPClient()
        let body = Data("{\"isLegacy\":true}".utf8)
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client.responses.append((body, response))

        let request = URLRequest(url: URL(string: "https://example.com")!)
        let (data, _) = try await client.data(for: request)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["isLegacy"] as? Bool, true)
    }

    func testFakeHTTP_throwsWhenConfigured() async {
        let client = FakeHTTPClient()
        client.shouldThrow = URLError(.notConnectedToInternet)

        let request = URLRequest(url: URL(string: "https://example.com")!)
        do {
            _ = try await client.data(for: request)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
}

// MARK: - File Coordination Tests

final class FileCoordinationTests: XCTestCase {
    func testNSFileCoordinatorInvokesAccessorAtExactStandardizedPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HealthMdFileCoordinationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("export.md")
        let coordinator = NSFileCoordinatorAdapter()

        let accessorPath = try coordinator.coordinateWriting(
            at: destination,
            intent: .replace,
            cancellationCheck: {}
        ) { coordinatedURL in
            try AtomicFileWriter.writeString("coordinated", to: coordinatedURL)
            return coordinatedURL.standardizedFileURL.path
        }

        XCTAssertEqual(accessorPath, destination.standardizedFileURL.path)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "coordinated")
    }

    func testNSFileCoordinatorPropagatesAccessorFailureWithoutChangingExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HealthMdFileCoordinationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("export.md")
        try "original".write(to: destination, atomically: true, encoding: .utf8)
        let coordinator = NSFileCoordinatorAdapter()

        XCTAssertThrowsError(try coordinator.coordinateWriting(
            at: destination,
            intent: .replace,
            cancellationCheck: {}
        ) { _ -> Void in
            throw CocoaError(.fileWriteNoPermission)
        })
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
    }
}

// MARK: - FileSystemAccessing Tests

final class FileSystemAccessingTests: XCTestCase {

    func testFakeFS_fileDoesNotExist() {
        let fs = FakeFileSystem()
        XCTAssertFalse(fs.fileExists(atPath: "/missing"))
    }

    func testFakeFS_writeAndCheckExists() throws {
        let fs = FakeFileSystem()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        try fs.writeString("content", to: url, atomically: true)
        XCTAssertTrue(fs.fileExists(atPath: url.path))
    }

    func testFakeFS_writeAndRead() throws {
        let fs = FakeFileSystem()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        try fs.writeString("hello world", to: url, atomically: true)
        let content = try fs.contentsOfFile(at: url)
        XCTAssertEqual(content, "hello world")
    }

    func testFakeFS_readNonexistentThrows() {
        let fs = FakeFileSystem()
        XCTAssertThrowsError(try fs.contentsOfFile(at: URL(fileURLWithPath: "/missing")))
    }

    func testFakeFS_createDirectory() throws {
        let fs = FakeFileSystem()
        let url = URL(fileURLWithPath: "/tmp/sub/dir")
        try fs.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertTrue(fs.fileExists(atPath: url.path))
    }
}

// MARK: - Production Adapter Conformance Tests

final class AtomicFileWriterTests: XCTestCase {

    func testDirectCheckpointRejectsByteIdenticalReplacementGeneration() throws {
        let root = try makeTemporaryDirectory()
        let job = root.appendingPathComponent("job")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        let destination = job.appendingPathComponent("journal.json")
        let lock = root.appendingPathComponent(".publication.lock")
        let bytes = Data("synthetic accepted authority".utf8)
        var stale = AppleExportJournalCheckpoint()
        try stale.publish(bytes, to: destination, freshAdmission: true,
            lockURL: lock, durabilityRoot: root)
        try FileManager.default.removeItem(at: job)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        var replacement = AppleExportJournalCheckpoint()
        try replacement.publish(bytes, to: destination, freshAdmission: true,
            lockURL: lock, durabilityRoot: root)
        XCTAssertNotNil(stale.generation)
        XCTAssertNotEqual(stale.generation, replacement.generation)
        XCTAssertThrowsError(try stale.publish(Data("stale paused checkpoint".utf8), to: destination,
            freshAdmission: false, lockURL: lock, durabilityRoot: root)) {
            XCTAssertEqual(($0 as? POSIXError)?.code, .EAGAIN)
        }
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    func testContinuationOwnershipSurvivesProgressButRejectsReplacement() throws {
        let root = try makeTemporaryDirectory()
        let job = root.appendingPathComponent("job")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        let destination = job.appendingPathComponent("journal.json")
        let lock = root.appendingPathComponent(".publication.lock")
        var original = AppleExportJournalCheckpoint()
        try original.publish(Data("initial checkpoint".utf8), to: destination,
            freshAdmission: true, lockURL: lock, durabilityRoot: root)
        var progress = original
        let bytes = Data("advanced checkpoint".utf8)
        try progress.publish(bytes, to: destination, freshAdmission: false,
            lockURL: lock, durabilityRoot: root)
        XCTAssertNoThrow(try original.validateGeneration())
        try FileManager.default.removeItem(at: job)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        var replacement = AppleExportJournalCheckpoint()
        try replacement.publish(bytes, to: destination, freshAdmission: true,
            lockURL: lock, durabilityRoot: root)
        XCTAssertThrowsError(try original.validateGeneration()) {
            XCTAssertEqual(($0 as? POSIXError)?.code, .EAGAIN)
        }
        XCTAssertNoThrow(try replacement.validateGeneration())
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    func testContinuationCannotRecreateMissingJobOrUseUnboundReceipt() throws {
        let root = try makeTemporaryDirectory()
        let job = root.appendingPathComponent("job")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        let destination = job.appendingPathComponent("journal.json")
        var checkpoint = AppleExportJournalCheckpoint()
        try checkpoint.publish(Data("owned checkpoint".utf8), to: destination,
            freshAdmission: true, lockURL: root.appendingPathComponent(".publication.lock"), durabilityRoot: root)
        try FileManager.default.removeItem(at: job)
        XCTAssertThrowsError(try checkpoint.validateGeneration())
        XCTAssertFalse(FileManager.default.fileExists(atPath: job.path))
        let unbound = AppleExportJournalCheckpoint(bytes: checkpoint.bytes, generation: checkpoint.generation)
        XCTAssertThrowsError(try unbound.validateGeneration())
        XCTAssertFalse(FileManager.default.fileExists(atPath: job.path))
    }

    @MainActor
    func testSuspendedReceiveRejectsReplacementBeforeReturningReply() async throws {
        let root = try makeTemporaryDirectory()
        let job = root.appendingPathComponent("job")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        let destination = job.appendingPathComponent("journal.json")
        let lock = root.appendingPathComponent(".publication.lock")
        let bytes = Data("synthetic accepted authority".utf8)
        var checkpoint = AppleExportJournalCheckpoint()
        try checkpoint.publish(bytes, to: destination, freshAdmission: true,
            lockURL: lock, durabilityRoot: root)
        var consumedReply: Int?
        do {
            consumedReply = try await checkpoint.continueWhileOwned {
                await Task.yield()
                try FileManager.default.removeItem(at: job)
                try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
                var replacement = AppleExportJournalCheckpoint()
                try replacement.publish(bytes, to: destination, freshAdmission: true,
                    lockURL: lock, durabilityRoot: root)
                return 42
            }
            XCTFail("A superseded sender must not consume the pending reply")
        } catch {
            XCTAssertEqual(error as? AppleExportJournalCheckpoint.ContinuationError, .superseded)
        }
        XCTAssertNil(consumedReply)
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    @MainActor
    func testOwnedSendSequenceStopsAfterReplacementButAllowsSameGenerationProgress() async throws {
        for timing in ["before-send", "during-send", "same-generation-progress"] {
            let root = try makeTemporaryDirectory()
            let job = root.appendingPathComponent("job")
            try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
            let destination = job.appendingPathComponent("journal.json")
            let lock = root.appendingPathComponent(".publication.lock")
            let bytes = Data("synthetic accepted authority".utf8)
            var checkpoint = AppleExportJournalCheckpoint()
            try checkpoint.publish(bytes, to: destination, freshAdmission: true,
                lockURL: lock, durabilityRoot: root)
            func replaceJob() throws {
                try FileManager.default.removeItem(at: job)
                try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
                var replacement = AppleExportJournalCheckpoint()
                try replacement.publish(bytes, to: destination, freshAdmission: true,
                    lockURL: lock, durabilityRoot: root)
            }
            if timing == "before-send" { try replaceJob() }
            var frames: [String] = []
            do {
                try await checkpoint.continueWhileOwned {
                    frames.append("session")
                    await Task.yield()
                    if timing == "during-send" { try replaceJob() }
                    if timing == "same-generation-progress" {
                        var progress = checkpoint
                        try progress.publish(Data("advanced progress".utf8), to: destination,
                            freshAdmission: false, lockURL: lock, durabilityRoot: root)
                    }
                }
                try await checkpoint.continueWhileOwned { frames.append("manifest") }
                XCTAssertEqual(timing, "same-generation-progress")
            } catch {
                XCTAssertNotEqual(timing, "same-generation-progress")
                XCTAssertEqual(error as? AppleExportJournalCheckpoint.ContinuationError, .superseded)
            }
            switch timing {
            case "before-send": XCTAssertEqual(frames, [])
            case "during-send": XCTAssertEqual(frames, ["session"])
            default: XCTAssertEqual(frames, ["session", "manifest"])
            }
            XCTAssertEqual(try Data(contentsOf: destination),
                timing == "same-generation-progress" ? Data("advanced progress".utf8) : bytes)
        }
    }

    private enum SimulatedReceiveError: Error, Equatable { case disconnected }

    @MainActor
    func testReceiveFailureRevalidatesOwnershipAndPreservesOwnedTransportErrors() async throws {
        for replaceDuringReceive in [false, true] {
            let root = try makeTemporaryDirectory()
            let job = root.appendingPathComponent("job")
            try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
            let destination = job.appendingPathComponent("journal.json")
            let lock = root.appendingPathComponent(".publication.lock")
            let bytes = Data("synthetic accepted authority".utf8)
            var checkpoint = AppleExportJournalCheckpoint()
            try checkpoint.publish(bytes, to: destination, freshAdmission: true,
                lockURL: lock, durabilityRoot: root)
            do {
                let _: Int = try await checkpoint.continueWhileOwned {
                    await Task.yield()
                    if replaceDuringReceive {
                        try FileManager.default.removeItem(at: job)
                        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
                        var replacement = AppleExportJournalCheckpoint()
                        try replacement.publish(bytes, to: destination, freshAdmission: true,
                            lockURL: lock, durabilityRoot: root)
                    }
                    throw SimulatedReceiveError.disconnected
                }
                XCTFail("The receive failed")
            } catch {
                if replaceDuringReceive {
                    XCTAssertEqual(error as? AppleExportJournalCheckpoint.ContinuationError, .superseded)
                } else {
                    XCTAssertEqual(error as? SimulatedReceiveError, .disconnected)
                }
            }
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
        }
    }

    func testErrorCleanupHoldsOriginalGenerationThroughProgressMutation() throws {
        let root = try makeTemporaryDirectory()
        let job = root.appendingPathComponent("job")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        let destination = job.appendingPathComponent("journal.json")
        let lock = root.appendingPathComponent(".publication.lock")
        var execution = AppleExportJournalCheckpoint()
        try execution.publish(Data("accepted".utf8), to: destination,
            freshAdmission: true, lockURL: lock, durabilityRoot: root)
        var progress = execution
        try progress.publish(Data("captured".utf8), to: destination,
            freshAdmission: false, lockURL: lock, durabilityRoot: root)
        try execution.withGenerationOwnership {
            let descriptor = Darwin.open(lock.path, O_RDWR)
            guard descriptor >= 0 else { throw POSIXError(.EIO) }
            defer { Darwin.close(descriptor) }
            let result = flock(descriptor, LOCK_EX | LOCK_NB)
            let observedError = errno
            if result == 0 { _ = flock(descriptor, LOCK_UN) }
            XCTAssertEqual(result, -1)
            XCTAssertEqual(observedError, EWOULDBLOCK)
            XCTAssertEqual(try Data(contentsOf: destination), Data("captured".utf8))
            // A loaded checkpoint may advance within this execution's generation.
            try progress.publish(Data("paused".utf8), to: destination,
                freshAdmission: false, lockURL: lock, durabilityRoot: root)
        }
        XCTAssertEqual(try Data(contentsOf: destination), Data("paused".utf8))
        try FileManager.default.removeItem(at: job)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        var replacement = AppleExportJournalCheckpoint()
        let replacementBytes = Data("paused".utf8)
        try replacement.publish(replacementBytes, to: destination,
            freshAdmission: true, lockURL: lock, durabilityRoot: root)
        var cleanupCalled = false
        XCTAssertThrowsError(try execution.withGenerationOwnership {
            cleanupCalled = true
            try replacement.publish(Data("stale pause".utf8), to: destination,
                freshAdmission: false, lockURL: lock, durabilityRoot: root)
        }) {
            XCTAssertEqual(($0 as? POSIXError)?.code, .EAGAIN)
        }
        XCTAssertFalse(cleanupCalled)
        XCTAssertEqual(try Data(contentsOf: destination), replacementBytes)
    }

    func testTemporaryFileURL_usesSameDirectoryAndHiddenUniqueName() {
        let destination = URL(fileURLWithPath: "/tmp/Health.md Export.md")
        let uuid = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!

        let temporary = AtomicFileWriter.temporaryFileURL(for: destination, uuid: uuid)

        XCTAssertEqual(temporary.deletingLastPathComponent(), destination.deletingLastPathComponent())
        XCTAssertTrue(temporary.lastPathComponent.hasPrefix(".Health.md Export.md."))
        XCTAssertTrue(temporary.lastPathComponent.hasSuffix(".tmp"))
    }

    func testWriteStringAtomically_writesFinalContentAndLeavesNoTemporaryFiles() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("export.md")

        try AtomicFileWriter.writeString("first", to: destination)
        try AtomicFileWriter.writeString("second", to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "second")
        XCTAssertEqual(try temporaryFiles(in: directory), [])
    }

    func testWriteStringAtomically_cleansTemporaryFileWhenRenameFails() throws {
        let directory = try makeTemporaryDirectory()
        let destinationDirectory = directory.appendingPathComponent("export.md", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try AtomicFileWriter.writeString("content", to: destinationDirectory))
        XCTAssertEqual(try temporaryFiles(in: directory), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationDirectory.path))
    }

    func testRequireAbsentPublishesOnceAndRetainsExistingBytes() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("journal.json")
        let original = Data("accepted-authority".utf8)
        try AtomicFileWriter.writeData(original, to: destination, attributes: [.posixPermissions: 0o600], commitPolicy: .requireAbsent)
        XCTAssertThrowsError(try AtomicFileWriter.writeData(Data("replacement-authority".utf8), to: destination, commitPolicy: .requireAbsent)) {
            XCTAssertEqual(($0 as? POSIXError)?.code, .EEXIST)
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try temporaryFiles(in: directory), [])
        let permissions = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testRequireAbsentRejectsWinnerInstalledImmediatelyBeforePublication() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("journal.json")
        let winner = Data("competing-accepted-authority".utf8)
        XCTAssertThrowsError(try AtomicFileWriter.writeFile(to: destination, commitPolicy: .requireAbsent,
            beforeCommit: { try winner.write(to: destination, options: .atomic) },
            producer: { try Data("losing-authority".utf8).write(to: $0) })) {
            XCTAssertEqual(($0 as? POSIXError)?.code, .EEXIST)
        }
        XCTAssertEqual(try Data(contentsOf: destination), winner)
        XCTAssertEqual(try temporaryFiles(in: directory), [])
    }

    func testRequireAbsentRetainsSymbolicLinkAndTarget() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("journal.json")
        let target = directory.appendingPathComponent("retained-source.json")
        let original = Data("retained-source-authority".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
        XCTAssertThrowsError(try AtomicFileWriter.writeData(Data("replacement".utf8), to: destination, commitPolicy: .requireAbsent)) {
            XCTAssertEqual(($0 as? POSIXError)?.code, .EEXIST)
        }
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(try temporaryFiles(in: directory), [])
    }

    func testRequiredDirectoryFailureDoesNotAcknowledgePublishedJournal() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("journal.json")
        let authority = Data("accepted-durable-authority".utf8)
        var synchronized: [URL] = []
        XCTAssertThrowsError(try AtomicFileWriter.writeData(
            authority, to: destination, commitPolicy: .requireAbsent,
            directoryDurability: .required(upTo: directory),
            directorySync: { synchronized.append($0); throw POSIXError(.EIO) }
        )) { XCTAssertEqual(($0 as? POSIXError)?.code, .EIO) }
        XCTAssertEqual(synchronized.map(\.path), [directory.path])
        XCTAssertEqual(try Data(contentsOf: destination), authority)
        XCTAssertEqual(try temporaryFiles(in: directory), [])
    }

    func testRequiredDirectorySyncCoversNestedAuthorityParentsInOrder() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appendingPathComponent("jobs", isDirectory: true)
        let leaf = first.appendingPathComponent("synthetic-job", isDirectory: true)
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        let destination = leaf.appendingPathComponent("journal.json")
        var synchronized: [URL] = []
        try AtomicFileWriter.writeData(Data("authority".utf8), to: destination,
            directoryDurability: .required(upTo: root), directorySync: {
                synchronized.append($0)
                try AtomicFileWriter.synchronizeDirectory($0)
            })
        XCTAssertEqual(synchronized.map(\.path), [leaf.path, first.path, root.path])
        synchronized.removeAll()
        XCTAssertThrowsError(try AtomicFileWriter.writeData(Data("checkpoint".utf8), to: destination,
            directoryDurability: .required(upTo: root), directorySync: {
                synchronized.append($0)
                if $0.path == first.path { throw POSIXError(.EIO) }
                try AtomicFileWriter.synchronizeDirectory($0)
            }))
        XCTAssertEqual(synchronized.map(\.path), [leaf.path, first.path])
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "checkpoint")
        XCTAssertEqual(try temporaryFiles(in: leaf), [])
    }

    func testRequiredDirectoryRootMustContainDestinationBeforeProducerRuns() throws {
        let root = try makeTemporaryDirectory()
        let unrelated = root.appendingPathComponent("unrelated", isDirectory: true)
        let destination = root.appendingPathComponent("journal.json")
        var produced = false
        XCTAssertThrowsError(try AtomicFileWriter.writeFile(to: destination,
            directoryDurability: .required(upTo: unrelated), producer: { _ in produced = true }))
        XCTAssertFalse(produced)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try temporaryFiles(in: root), [])
    }

    func testValueOwnedCheckpointCopiesCannotRefreshStaleReadAuthority() throws {
        let root = try makeTemporaryDirectory()
        let destination = root.appendingPathComponent("journal.json")
        let lock = root.appendingPathComponent(".publication.lock")
        let original = Data("accepted-authority".utf8)
        var stale = AppleExportJournalCheckpoint()
        try stale.publish(original, to: destination, freshAdmission: true, lockURL: lock, durabilityRoot: root)
        var independent = stale
        let paused = Data("independent-paused-checkpoint".utf8)
        try independent.publish(paused, to: destination, freshAdmission: false, lockURL: lock, durabilityRoot: root)
        XCTAssertEqual(independent.bytes, paused)
        XCTAssertEqual(stale.bytes, original)
        XCTAssertThrowsError(try stale.publish(Data("stale-progress".utf8), to: destination,
            freshAdmission: false, lockURL: lock, durabilityRoot: root)) {
            XCTAssertEqual(($0 as? POSIXError)?.code, .EAGAIN)
        }
        XCTAssertEqual(try Data(contentsOf: destination), paused)
        XCTAssertEqual(stale.bytes, original)
        var resumed = AppleExportJournalCheckpoint(bytes: try Data(contentsOf: destination),
            generation: independent.generation, completionIdentity: independent.completionIdentity)
        let completed = Data("resumed-completion".utf8)
        try resumed.publish(completed, to: destination, freshAdmission: false, lockURL: lock, durabilityRoot: root)
        XCTAssertEqual(resumed.bytes, completed)
        XCTAssertEqual(try Data(contentsOf: destination), completed)
        XCTAssertEqual(try temporaryFiles(in: root), [])
    }

    func testCheckpointWithoutReadReceiptCannotCreateOrReplaceAcceptedWork() throws {
        let root = try makeTemporaryDirectory()
        let destination = root.appendingPathComponent("journal.json")
        let lock = root.appendingPathComponent(".publication.lock")
        let authority = Data("retained-authority".utf8)
        try authority.write(to: destination)
        var unowned = AppleExportJournalCheckpoint()
        XCTAssertThrowsError(try unowned.publish(Data("unowned".utf8), to: destination,
            freshAdmission: false, lockURL: lock, durabilityRoot: root))
        XCTAssertNil(unowned.bytes)
        XCTAssertEqual(try Data(contentsOf: destination), authority)
        try FileManager.default.removeItem(at: destination)
        XCTAssertThrowsError(try unowned.publish(Data("unowned".utf8), to: destination,
            freshAdmission: false, lockURL: lock, durabilityRoot: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try temporaryFiles(in: root), [])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthMdAtomicFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func temporaryFiles(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix(".") && $0.hasSuffix(".tmp") }
            .sorted()
    }
}

final class ProductionAdapterTests: XCTestCase {

    func testSystemKeychainStore_conformsToProtocol() {
        let _: KeychainStoring = SystemKeychainStore(service: "com.test.runtime-protocol-tests")
        // Compile-time conformance check
    }

    func testSystemUserDefaults_conformsToProtocol() {
        let _: UserDefaultsStoring = SystemUserDefaults(defaults: .standard)
        // Compile-time conformance check
    }

    func testURLSessionHTTPClient_conformsToProtocol() {
        let _: HTTPClientProtocol = URLSessionHTTPClient()
        // Compile-time conformance check
    }

    func testSystemVaultFolderIdentityProbe_returnsStableIdentityForDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthMdIdentityProbeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let probe: VaultFolderIdentityProbing = SystemVaultFolderIdentityProbe()
        let values = try directory.resourceValues(forKeys: [
            .isDirectoryKey,
            .volumeSupportsPersistentIDsKey,
            .volumeUUIDStringKey,
            .fileIdentifierKey
        ])
        guard values.isDirectory == true,
              values.volumeSupportsPersistentIDs == true,
              values.volumeUUIDString?.isEmpty == false,
              values.fileIdentifier != nil else {
            throw XCTSkip("The test volume does not expose persistent directory identity")
        }

        let first = try XCTUnwrap(probe.persistentIdentity(for: directory))
        let second = try XCTUnwrap(probe.persistentIdentity(for: directory.standardizedFileURL))

        XCTAssertFalse(first.volumeUUIDString.isEmpty)
        XCTAssertEqual(first, second)
    }

    func testSystemVaultFolderIdentityProbe_rejectsRegularFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthMdIdentityProbeTests-\(UUID().uuidString).txt")
        try Data("test".utf8).write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: file)
        }
        let probe: VaultFolderIdentityProbing = SystemVaultFolderIdentityProbe()

        XCTAssertNil(try probe.persistentIdentity(for: file))
    }

    func testSystemFileSystem_writeStringAtomicallyWritesFinalContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthMdSystemFileSystemTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("export.md")
        let fs: FileSystemAccessing = SystemFileSystem()

        try fs.writeString("content", to: destination, atomically: true)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "content")
    }

    func testSystemFileManager_conformsToProtocol() {
        let _: FileSystemAccessing = SystemFileSystem()
        // Compile-time conformance check
    }
}
