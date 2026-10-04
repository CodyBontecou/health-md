import Foundation
#if !ACCOUNT_AUTH_SOURCE_HOST
import XCTest
@testable import HealthMd
#endif

nonisolated enum AccountAuthCallbackChecks {
    static func run(root: URL) throws -> String {
        let data = try Data(contentsOf: root.appendingPathComponent(
            "packages/contracts/account-auth/v1/fixtures/security-vectors.json"))
        let corpus = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rows = corpus["callback_vectors"] as! [[String: Any]]
        let source = try AccountAuthTestCheck.corpus(root: root)
        let first = (source["response_cases"] as! [[String: Any]])[0]
        let c = first["context"] as! [String: String]
        let pkce = AccountAuthPKCE(state: String(repeating: "A", count: 43),
            verifier: String(repeating: "C", count: 43), challenge: "lCAUrwMZXJf8imEhoD4WYLiQJ6U4MloQHrpCbazX5Yc")
        let code = "hmd_acode_" + String(repeating: "A", count: 43)
        let refresh = "hmd_nrf_" + String(repeating: "A", count: 43)
        for row in rows {
            let patch = row["context"] as? [String: Any] ?? [:]
            var raw = row["uri"] as! String
            for (key, value) in ["callback": c["callback"]!, "issuer": c["issuer"]!, "state": pkce.state,
                                 "code": code, "refresh": refresh] {
                raw = raw.replacingOccurrences(of: "{\(key)}", with: value)
            }
            func decode() throws -> AccountAuthCallback {
                let r = try AccountAuthRegistration.reviewedSynthetic(
                    clientID: patch["client_id"] as? String ?? c["client_id"]!,
                    environment: patch["environment"] as? String ?? "synthetic")
                let captured = try AccountAuthCapture(registration: r, installationID: c["installation_id"]!, scope: c["scope"]!)
                let pending = AccountAuthPending(captured: captured, pkce: pkce, localGeneration: 1, expiresAt: 400)
                return try AccountAuthCallback.decode(Data(raw.utf8),
                    pending: patch["pending"] as? Bool == false ? nil : pending,
                    localGeneration: patch["generation_matches"] as? Bool == false ? 2 : 1, now: 100)
            }
            switch row["expected"] as! String {
            case "accept_code":
                guard case .code(let received) = try decode() else { throw AccountAuthTestCheck.Failed(category: "callback-code") }
                try AccountAuthTestCheck.require(received.kind == .code && received.wireValue() == code, "callback-secret-bytes")
            case "accept_denial":
                guard case .denied = try decode() else { throw AccountAuthTestCheck.Failed(category: "callback-denial") }
            default: try AccountAuthTestCheck.denies("callback-negative") { _ = try decode() }
            }
        }
        for client in AccountAuthAppleClient.allCases {
            let r = AccountAuthRegistration.reviewedSynthetic(apple: client)
            let captured = try AccountAuthCapture(registration: r, installationID: c["installation_id"]!, scope: c["scope"]!)
            let p = AccountAuthPending(captured: captured, pkce: pkce, localGeneration: 1, expiresAt: 400)
            let bytes = Data("\(r.callback)?code=\(code)&state=\(pkce.state)&iss=\(r.issuer)".utf8)
            guard case .code(let accepted) = try AccountAuthCallback.decode(bytes, pending: p, localGeneration: 1, now: 100) else {
                throw AccountAuthTestCheck.Failed(category: "apple-exact-client")
            }
            try AccountAuthTestCheck.require(accepted.wireValue() == code, "apple-callback-bytes")
            try AccountAuthTestCheck.denies("callback-expiry-equality") {
                _ = try AccountAuthCallback.decode(bytes, pending: p, localGeneration: 1, now: 400)
            }
            for extra in [bytes + Data([32]), bytes + Data([0]), Data(repeating: 65, count: 4097)] {
                try AccountAuthTestCheck.denies("callback-extra-bound") {
                    _ = try AccountAuthCallback.decode(extra, pending: p, localGeneration: 1, now: 100)
                }
            }
        }
        try AccountAuthTestCheck.require(rows.count == 32, "callback-count")
        return "callback=32 apple-exact-positive=3 extra-negative=12"
    }
}
#if !ACCOUNT_AUTH_SOURCE_HOST
final class AccountAuthCallbackTests: XCTestCase {
    func testSharedRawCallbacks() throws { _ = try AccountAuthCallbackChecks.run(root: AccountAuthTestCheck.root()) }
}
#endif
