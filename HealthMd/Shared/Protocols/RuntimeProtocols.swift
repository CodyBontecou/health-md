//
//  RuntimeProtocols.swift
//  HealthMd
//
//  Protocol-based seams for runtime services, enabling deterministic
//  unit testing of managers without direct OS framework calls.
//

import Foundation
import ExportKit

// MARK: - Keychain

/// Abstracts keychain integer storage used by PurchaseManager.
protocol KeychainStoring: Sendable {
    func readInt(key: String) -> Int
    func writeInt(key: String, value: Int)
}

// MARK: - UserDefaults

/// Abstracts UserDefaults access used by managers for settings persistence.
nonisolated protocol UserDefaultsStoring: ExportDestinationDataStoring, Sendable {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaultsStoring {
    func destinationString(forKey key: String) -> String? {
        string(forKey: key)
    }

    func destinationBookmarkData(forKey key: String) -> Data? {
        data(forKey: key)
    }

    func setDestinationString(_ value: String?, forKey key: String) {
        set(value, forKey: key)
    }

    func setDestinationBookmarkData(_ value: Data?, forKey key: String) {
        set(value, forKey: key)
    }

    func removeDestinationValue(forKey key: String) {
        removeObject(forKey: key)
    }
}

// MARK: - HTTP Client

/// Abstracts URL-based network requests used by PurchaseManager for server verification.
protocol HTTPClientProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - Bookmark Resolution

/// Abstracts URL bookmark resolution and security-scoped resource access
/// used by VaultManager for vault folder persistence.
protocol BookmarkResolving: ExportBookmarkAccessing {
    /// Resolve bookmark data to a URL, reporting whether the bookmark is stale.
    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool)
    /// Create bookmark data for a URL.
    func createBookmarkData(for url: URL) throws -> Data
    /// Begin security-scoped access to a resource.
    func startAccessing(_ url: URL) -> Bool
    /// End security-scoped access to a resource.
    func stopAccessing(_ url: URL)
}

extension BookmarkResolving {
    func resolveDestinationBookmark(data: Data) throws -> ExportBookmarkResolution {
        let resolved = try resolveBookmark(data: data)
        return ExportBookmarkResolution(url: resolved.url, isStale: resolved.isStale)
    }

    func createDestinationBookmarkData(for url: URL) throws -> Data {
        try createBookmarkData(for: url)
    }

    func startAccessingDestination(_ url: URL) -> Bool {
        startAccessing(url)
    }

    func stopAccessingDestination(_ url: URL) {
        stopAccessing(url)
    }
}

// MARK: - File System

/// Abstracts file system operations used by VaultManager and exporters.
protocol FileSystemAccessing: Sendable {
    func fileExists(atPath path: String) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func contentsOfFile(at url: URL) throws -> String
    func writeString(_ string: String, to url: URL, atomically: Bool) throws
}

struct FileSystemAccessingExportAdapter: ExportFileSystem {
    private let fileSystem: any FileSystemAccessing

    init(_ fileSystem: any FileSystemAccessing) {
        self.fileSystem = fileSystem
    }

    func fileExists(at url: URL) -> Bool {
        fileSystem.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
        try fileSystem.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func readString(at url: URL) throws -> String {
        try fileSystem.contentsOfFile(at: url)
    }

    func writeString(_ value: String, to url: URL, atomically: Bool) throws {
        try fileSystem.writeString(value, to: url, atomically: atomically)
    }
}
