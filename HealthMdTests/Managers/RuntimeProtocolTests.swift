//
//  RuntimeProtocolTests.swift
//  HealthMdTests
//
//  TDD tests for runtime service protocol seams.
//  Validates that fake implementations work correctly and that
//  managers can accept injected dependencies.
//

import XCTest
@testable import HealthMd

// MARK: - Fake Implementations

final class FakeKeychainStore: KeychainStoring, @unchecked Sendable {
    var storage: [String: Int] = [:]

    func readInt(key: String) -> Int {
        storage[key] ?? 0
    }

    func writeInt(key: String, value: Int) {
        storage[key] = value
    }
}

final class FakeUserDefaults: UserDefaultsStoring, @unchecked Sendable {
    var storage: [String: Any] = [:]

    func string(forKey key: String) -> String? {
        storage[key] as? String
    }

    func bool(forKey key: String) -> Bool {
        storage[key] as? Bool ?? false
    }

    func integer(forKey key: String) -> Int {
        storage[key] as? Int ?? 0
    }

    func data(forKey key: String) -> Data? {
        storage[key] as? Data
    }

    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }

    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
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

final class FakeFileSystem: FileSystemAccessing, @unchecked Sendable {
    var files: [String: String] = [:]
    var directories: Set<String> = []

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        directories.insert(url.path)
    }

    func contentsOfFile(at url: URL) throws -> String {
        guard let content = files[url.path] else {
            throw NSError(domain: "FakeFS", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        return content
    }

    func writeString(_ string: String, to url: URL, atomically: Bool) throws {
        files[url.path] = string
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
