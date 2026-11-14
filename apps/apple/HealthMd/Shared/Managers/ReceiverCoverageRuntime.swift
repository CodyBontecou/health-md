import Foundation
import Security
import CryptoKit

/// Local opt-in is deliberately outside portable profile/export settings. A pending request keeps
/// its original copy; editing/turning off this setting affects only subsequent admissions.
@MainActor final class ReceiverCoverageSettings {
    static let shared = ReceiverCoverageSettings()
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthMd/ReceiverCoverage", isDirectory: true)
    }
    private let keychain: any KeychainStoring
    private let storageDirectory: URL
    init(keychain: any KeychainStoring = SystemKeychainStore(), storageDirectory: URL? = nil) {
        self.keychain = keychain
        self.storageDirectory = storageDirectory ?? Self.directory
    }
    static func scope(_ profileID: UUID?) -> String { profileID?.uuidString.lowercased() ?? "legacy" }
    private func url(_ scope: String) throws -> URL {
        guard scope.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { throw ReceiverCoveragePreflight.BoundaryError.invalidConfiguration }
        return storageDirectory.appendingPathComponent("configuration-\(scope).json")
    }
    func configuration(_ scope: String) throws -> ReceiverCoverageConfiguration? {
        let url = try url(scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ReceiverCoverageConfiguration.self, from: Data(contentsOf: url))
    }
    func save(_ config: ReceiverCoverageConfiguration?, scope: String, uploadURL: String) throws {
        let url = try url(scope)
        if let config {
            _ = try ReceiverCoveragePreflight.prepare(policy: .missingDays, uploadURL: uploadURL,
                preflightURL: config.preflightURL, uploadHeaders: [:], scopeID: config.scopeID, calendarTimeZone: "UTC",
                frozenOutputSettings: Data("{}".utf8), refreshRecentDays: config.refreshRecentDays, installationKey: key(create: true))
            try ReceiverCoverageAtomicFile.write(JSONEncoder().encode(config), to: url)
        } else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func key(create: Bool = false) throws -> Data {
        let name = "receiver-coverage-installation-key-v1"
        if let encoded = try keychain.readStringOrThrow(key: name) {
            guard let data = Data(base64Encoded: encoded), data.count == 32 else { throw ReceiverCoveragePreflight.BoundaryError.destinationChanged }
            return data
        }
        let plans = storageDirectory.appendingPathComponent("plans")
        guard create else { throw ReceiverCoveragePreflight.BoundaryError.destinationChanged }
        do {
            guard try FileManager.default.contentsOfDirectory(atPath: plans.path).isEmpty else {
                throw ReceiverCoveragePreflight.BoundaryError.destinationChanged
            }
        } catch {
            // Only an absent journal permits initial setup. An unreadable/non-directory
            // location is unknown recovery state, never evidence that no plans exist.
            let failure = error as NSError
            guard failure.domain == NSCocoaErrorDomain, failure.code == NSFileReadNoSuchFileError else {
                throw ReceiverCoveragePreflight.BoundaryError.destinationChanged
            }
        }
        var data = Data(count: 32)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw ReceiverCoveragePreflight.BoundaryError.invalidConfiguration }
        try keychain.writeStringOrThrow(key: name, value: data.base64EncodedString())
        guard try keychain.readStringOrThrow(key: name) == data.base64EncodedString() else { throw ReceiverCoveragePreflight.BoundaryError.invalidConfiguration }
        return data
    }
    func bindScope(_ scope: String, settings: Data) throws {
        guard scope.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { throw ReceiverCoveragePreflight.BoundaryError.invalidConfiguration }
        // A scope is immutable for one output profile, including capture calendar/semantics.
        // Persist only a keyed digest, never provider authority or credentials in this ledger.
        let digest = HMAC<SHA256>.authenticationCode(for: Data("receiver-coverage-scope-v1:".utf8) + settings,
            using: SymmetricKey(data: try key())).map { String(format: "%02x", $0) }.joined()
        let path = storageDirectory.appendingPathComponent("scope-\(scope).binding")
        if FileManager.default.fileExists(atPath: path.path) {
            guard try String(contentsOf: path, encoding: .utf8) == digest else { throw ReceiverCoveragePreflight.BoundaryError.destinationChanged }
        } else { try ReceiverCoverageAtomicFile.write(Data(digest.utf8), to: path) }
    }
    static func snapshotBytes(_ snapshot: ExportSettingsSnapshot) throws -> Data {
        let encoder = JSONEncoder(); encoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        let value = try JSONSerialization.jsonObject(with: encoder.encode(snapshot))
        // These fields are sets in the owning Swift model. Preserve every other array's order.
        func normalize(_ value: Any, key: String = "") -> Any {
            if let object = value as? [String: Any] { return object.mapValues { $0 }.reduce(into: [String: Any]()) { $0[$1.key] = normalize($1.value, key: $1.key) } }
            if let array = value as? [String], ["exportFormats","enabledMetricIDs","enabledCategoryIDs","nativeDetailMetricIDs"].contains(key) { return array.sorted() }
            if let array = value as? [Any] { return array.map { normalize($0) } }
            return value
        }
        return try JSONSerialization.data(withJSONObject: normalize(value), options: [.sortedKeys, .withoutEscapingSlashes])
    }
    static func planID(authority: String) -> String {
        SHA256.hash(data: Data(("receiver-coverage-occurrence-v1:" + authority).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static var journal: ReceiverCoverageJournal { ReceiverCoverageJournal(directory: directory.appendingPathComponent("plans")) }
}
