//
//  ProductionAdapters.swift
//  HealthMd
//
//  Default production implementations of runtime protocols.
//  These wrap real OS APIs and are used by managers at runtime.
//

import Foundation
import Security

// MARK: - SystemKeychainStore

/// Production keychain adapter wrapping Security framework.
final class SystemKeychainStore: KeychainStoring, @unchecked Sendable {
    private let service: String

    init(service: String = "com.codybontecou.obsidianhealth") {
        self.service = service
    }

    func readInt(key: String) -> Int {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count >= MemoryLayout<Int32>.size else { return 0 }
        return Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
    }

    func writeInt(key: String, value: Int) {
        var v = Int32(value)
        let data = Data(bytes: &v, count: MemoryLayout<Int32>.size)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

// MARK: - SystemUserDefaults

/// Production UserDefaults adapter.
final class SystemUserDefaults: UserDefaultsStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func integer(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - SystemBookmarkResolver

/// Production bookmark resolver wrapping URL bookmark APIs.
final class SystemBookmarkResolver: BookmarkResolving, @unchecked Sendable {
    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        #if os(iOS)
        let options: URL.BookmarkResolutionOptions = []
        #elseif os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #endif
        let url = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    func createBookmarkData(for url: URL) throws -> Data {
        #if os(iOS)
        let options: URL.BookmarkCreationOptions = []
        #elseif os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #endif
        return try url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

// MARK: - URLSessionHTTPClient

/// Production HTTP client wrapping URLSession.
final class URLSessionHTTPClient: HTTPClientProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

// MARK: - SystemFileSystem

/// Production file system adapter wrapping FileManager.
final class SystemFileSystem: FileSystemAccessing, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    func contentsOfFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func writeString(_ string: String, to url: URL, atomically: Bool) throws {
        try string.write(to: url, atomically: atomically, encoding: .utf8)
    }
}
