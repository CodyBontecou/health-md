//
//  RuntimeProtocols.swift
//  HealthMd
//
//  Protocol-based seams for runtime services, enabling deterministic
//  unit testing of managers without direct OS framework calls.
//

import Foundation

// MARK: - Keychain

/// Abstracts keychain integer storage used by PurchaseManager.
protocol KeychainStoring: Sendable {
    func readInt(key: String) -> Int
    func writeInt(key: String, value: Int)
}

// MARK: - UserDefaults

/// Abstracts UserDefaults access used by managers for settings persistence.
protocol UserDefaultsStoring: Sendable {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

// MARK: - HTTP Client

/// Abstracts URL-based network requests used by PurchaseManager for server verification.
protocol HTTPClientProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - File System

/// Abstracts file system operations used by VaultManager and exporters.
protocol FileSystemAccessing: Sendable {
    func fileExists(atPath path: String) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func contentsOfFile(at url: URL) throws -> String
    func writeString(_ string: String, to url: URL, atomically: Bool) throws
}
