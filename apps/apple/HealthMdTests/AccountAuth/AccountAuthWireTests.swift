import Foundation
#if !ACCOUNT_AUTH_SOURCE_HOST
import XCTest
@testable import HealthMd
#endif

nonisolated enum AccountAuthTestCheck {
    struct Failed: Error { let category: String }
    static func require(_ condition: Bool, _ category: String) throws {
        if !condition { throw Failed(category: category) }
    }
    static func denies(_ category: String, _ action: () throws -> Void) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try require(rejected, category)
    }
    static func root(file: String = #filePath) -> URL {
        (0..<5).reduce(URL(fileURLWithPath: file)) { url, _ in url.deletingLastPathComponent() }
    }
    static func corpus(root: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
            "packages/contracts/account-auth/v1/fixtures/native-client-vectors.json"))) as! [String: Any]
    }
    static func bytes(_ row: [String: Any]) -> Data {
        if let raw = row["raw"] as? String { return Data(raw.utf8) }
        if let hex = row["hex"] as? String {
            let chars = Array(hex)
            return Data(stride(from: 0, to: chars.count, by: 2).map {
                UInt8(String(chars[$0...($0 + 1)]), radix: 16)!
            })
        }
        return Data(repeating: 32, count: row["repeat"] as! Int)
    }
    static func capture(_ c: [String: String]) throws -> AccountAuthCapture {
        let r = try AccountAuthRegistration.reviewedSynthetic(clientID: c["client_id"]!)
        try require(r.issuer == c["issuer"] && r.environment == c["environment"] &&
            r.audience == c["audience"] && r.callback == c["callback"], "pinned-context")
        return try AccountAuthCapture(registration: r, installationID: c["installation_id"]!, scope: c["scope"]!)
    }
}

nonisolated enum AccountAuthWireChecks {
    static func tracer(root: URL) throws {
        let corpus = try AccountAuthTestCheck.corpus(root: root)
        let row = (corpus["response_cases"] as! [[String: Any]])[0]
        let capture = try AccountAuthTestCheck.capture(row["context"] as! [String: String])
        let session = try AccountAuthWire.decodeSession(AccountAuthTestCheck.bytes(row), captured: capture)
        try AccountAuthTestCheck.require(session.serverGeneration == 0 && session.expiresIn == 300,
            "initial-session-tracer")
    }
    static func run(root: URL) throws -> String {
        let corpus = try AccountAuthTestCheck.corpus(root: root)
        let rows = corpus["response_cases"] as! [[String: Any]]
        let errors = corpus["error_cases"] as! [[String: Any]]
        let pkce = corpus["pkce_vectors"] as! [[String: String]]
        var positives = 0
        for (index, row) in rows.enumerated() {
            let capture = try AccountAuthTestCheck.capture(row["context"] as! [String: String])
            let bytes = AccountAuthTestCheck.bytes(row)
            if row["valid"] as! Bool {
                let s: AccountAuthSession
                do { s = try AccountAuthWire.decodeSession(bytes, captured: capture) }
                catch { throw AccountAuthTestCheck.Failed(category: "positive-response-\(index)") }
                let e = row["expected"] as! [String: Any]
                try AccountAuthTestCheck.require(s.tokenType == e["token_type"] as! String &&
                    s.access.wireValue() == e["access_token"] as! String &&
                    s.refresh.wireValue() == e["refresh_token"] as! String &&
                    s.expiresIn == (e["expires_in"] as! NSNumber).uint64Value &&
                    s.sessionID == e["session_id"] as! String && s.scope == e["scope"] as! String &&
                    s.namespace.issuer == e["issuer"] as! String &&
                    s.namespace.environment == e["environment"] as! String &&
                    s.namespace.accountID == e["account_id"] as! String &&
                    s.audience == e["audience"] as! String && s.clientID == e["client_id"] as! String &&
                    s.installationID == e["installation_id"] as! String &&
                    s.serverGeneration == (e["session_generation"] as! NSNumber).uint64Value, "all-13-fields")
                try AccountAuthTestCheck.require(!String(describing: s).contains(s.access.wireValue()) &&
                    !String(reflecting: s.refresh).contains(s.refresh.wireValue()) &&
                    Mirror(reflecting: s).children.isEmpty, "redaction")
                positives += 1
            } else {
                try AccountAuthTestCheck.denies("negative-response-\(index)") {
                    _ = try AccountAuthWire.decodeSession(bytes, captured: capture)
                }
            }
        }
        for row in errors {
            let bytes = AccountAuthTestCheck.bytes(row)
            if row["valid"] as! Bool {
                try AccountAuthTestCheck.require(try AccountAuthWire.decodeFailure(bytes).rawValue ==
                    row["expected"] as! String, "fixed-error")
            } else {
                try AccountAuthTestCheck.denies("negative-error") { _ = try AccountAuthWire.decodeFailure(bytes) }
            }
            let capture = try AccountAuthTestCheck.capture(rows[0]["context"] as! [String: String])
            try AccountAuthTestCheck.denies("errors-never-sessions") {
                _ = try AccountAuthWire.decodeSession(bytes, captured: capture)
            }
        }
        for row in pkce {
            try AccountAuthTestCheck.require(try AccountAuthPKCE.challenge(verifier: row["verifier"]!) ==
                row["challenge"]!, "real-pkce-golden")
        }
        let first = rows[0], capture = try AccountAuthTestCheck.capture(first["context"] as! [String: String])
        let raw = first["raw"] as! String
        let extras = ["", "[]", "{\"revoked\":true}",
            raw.replacingOccurrences(of: "\"expires_in\":300", with: "\"expires_in\":300.0"),
            raw.replacingOccurrences(of: "\"expires_in\":300", with: "\"expires_in\":3e2"),
            raw.replacingOccurrences(of: "\"expires_in\":300", with: "\"expires_in\":0300"),
            raw.replacingOccurrences(of: "synthetic-account-a", with: "synthetic-account-a\\u0000"),
            raw.replacingOccurrences(of: "synthetic-account-a", with: "\\udc00"),
            raw.replacingOccurrences(of: "synthetic-account-a", with: "\\ud800\\u0041"),
            raw.replacingOccurrences(of: "synthetic-account-a", with: "\\ud83d\\ude00"),
            raw.replacingOccurrences(of: "\"access_token\":", with: "\"access_token\":[] ,\"x\":"),
            raw + "\u{FEFF}"]
        for raw in extras {
            try AccountAuthTestCheck.denies("raw-extra-negative") {
                _ = try AccountAuthWire.decodeSession(Data(raw.utf8), captured: capture)
            }
        }
        let escaped = raw.replacingOccurrences(of: "\"account_id\":", with: "\"\\u0061ccount_id\":")
        let escapedSession = try AccountAuthWire.decodeSession(Data(escaped.utf8), captured: capture)
        try AccountAuthTestCheck.require(escapedSession.namespace.accountID == "synthetic-account-a", "escaped-key-lossless")
        let padded = Data((raw + String(repeating: " ", count: 8192 - raw.utf8.count)).utf8)
        try AccountAuthTestCheck.require(padded.count == 8192, "byte-bound")
        _ = try AccountAuthWire.decodeSession(padded, captured: capture)
        try AccountAuthTestCheck.denies("byte-over-bound") {
            _ = try AccountAuthWire.decodeSession(padded + Data([32]), captured: capture)
        }
        for bad in ["short", String(repeating: "a", count: 129), String(repeating: "é", count: 43)] {
            try AccountAuthTestCheck.denies("pkce-negative") { _ = try AccountAuthPKCE.challenge(verifier: bad) }
        }
        try AccountAuthTestCheck.require(rows.count == 73 && errors.count == 15 && pkce.count == 3, "corpus-count")
        return "response=73 positive=\(positives) negative=\(rows.count - positives) error=15 pkce=3 raw-extra=15 pkce-negative=3"
    }
}

#if !ACCOUNT_AUTH_SOURCE_HOST
final class AccountAuthWireTests: XCTestCase {
    func testSharedRawCorpus() throws { _ = try AccountAuthWireChecks.run(root: AccountAuthTestCheck.root()) }
}
#endif
