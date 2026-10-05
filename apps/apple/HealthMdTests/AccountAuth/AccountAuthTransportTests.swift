import Foundation
#if !ACCOUNT_AUTH_SOURCE_HOST
import XCTest
@testable import HealthMd
#endif

nonisolated enum AccountAuthTransportChecks {
    static let replyHeaders = ["Content-Type": "application/json", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer"]
    static func run(root: URL) throws -> String {
        let corpus = try AccountAuthTestCheck.corpus(root: root)
        let row = (corpus["response_cases"] as! [[String: Any]])[0]
        let captured = try AccountAuthTestCheck.capture(row["context"] as! [String: String])
        let session = try AccountAuthWire.decodeSession(AccountAuthTestCheck.bytes(row), captured: captured)
        let p = AccountAuthPending(captured: captured,
            pkce: AccountAuthPKCE(state: String(repeating: "A", count: 43), verifier: String(repeating: "C", count: 43),
                challenge: "lCAUrwMZXJf8imEhoD4WYLiQJ6U4MloQHrpCbazX5Yc"), localGeneration: 1, expiresAt: 400)
        let code = try AccountAuthSecret("hmd_acode_" + String(repeating: "A", count: 43), kind: .code)
        let plans = [try AccountAuthTransportPlan.exchange(pending: p, code: code, requestID: 1),
            try .refresh(captured: captured, proof: session.refresh, requestID: 2),
            try .revoke(captured: captured, proof: session.refresh, requestID: 3)]
        for (index, plan) in plans.enumerated() {
            let fields = try JSONSerialization.jsonObject(with: plan.wireBody()) as! [String: String]
            let expectedKeys: Set<String> = index == 0 ? ["grant_type", "client_id", "redirect_uri", "code", "code_verifier", "installation_id"] :
                (index == 1 ? ["grant_type", "client_id", "installation_id", "refresh_token"] : ["client_id", "installation_id", "refresh_token"])
            try AccountAuthTestCheck.require(Set(fields.keys) == expectedKeys &&
                fields["client_id"] == captured.registration.clientID && fields["installation_id"] == captured.installationID &&
                plan.method == "POST" && plan.headers == ["Content-Type": "application/json", "Accept": "application/json"] &&
                !plan.permitsCookies && !plan.permitsRedirects && !plan.permitsTransparentReplay &&
                plan.timeoutSeconds == 5 && plan.responseByteLimit == 8192 &&
                plan.endpoint == captured.registration.issuer + (index == 2 ? "/api/account-auth/v1/revoke" : "/api/account-auth/v1/token"),
                "closed-transport-plan")
            if index == 0 {
                try AccountAuthTestCheck.require(fields["grant_type"] == "authorization_code" && fields["code"] == code.wireValue() &&
                    fields["code_verifier"] == p.pkce.verifier && fields["redirect_uri"] == captured.registration.callback, "exchange-body")
            } else {
                try AccountAuthTestCheck.require(fields["refresh_token"] == session.refresh.wireValue() &&
                    (index == 2 || fields["grant_type"] == "refresh_token"), "refresh-revoke-body")
            }
            let body = index == 2 ? Data("{\"revoked\":true}".utf8) : AccountAuthTestCheck.bytes(row)
            let good = AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint,
                redirectHistory: [], status: 200, headers: replyHeaders, body: body)
            try AccountAuthTestCheck.require(try good.validatedBody(for: plan) == body, "correlated-response-bytes")
            var proxy = replyHeaders; proxy["Proxy-Authorization"] = "synthetic-no-authority"
            let unsafe = AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint,
                redirectHistory: [], status: 200, headers: proxy, body: body)
            try AccountAuthTestCheck.denies("proxy-authorization-must-not-return-body") { _ = try unsafe.validatedBody(for: plan) }
            var badHeaders = replyHeaders; badHeaders["Set-Cookie"] = "synthetic"
            var duplicate = replyHeaders; duplicate["content-type"] = "application/json"
            let negatives = [
                AccountAuthTransportReply(requestID: plan.requestID + 1, effectiveEndpoint: plan.endpoint, redirectHistory: [], status: 200, headers: replyHeaders, body: body),
                AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint + "/", redirectHistory: [], status: 200, headers: replyHeaders, body: body),
                AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint, redirectHistory: [plan.endpoint], status: 200, headers: replyHeaders, body: body),
                AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint, redirectHistory: [], status: 302, headers: replyHeaders, body: body),
                AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint, redirectHistory: [], status: 200, headers: badHeaders, body: body),
                AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint, redirectHistory: [], status: 200, headers: duplicate, body: body),
                AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint, redirectHistory: [], status: 200, headers: [:], body: body),
                AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint, redirectHistory: [], status: 200, headers: replyHeaders, body: Data(repeating: 32, count: 8193))]
            for bad in negatives { try AccountAuthTestCheck.denies("transport-negative") { _ = try bad.validatedBody(for: plan) } }
        }
        try AccountAuthTestCheck.denies("code-cannot-refresh") { _ = try AccountAuthTransportPlan.refresh(captured: captured, proof: code, requestID: 4) }
        try AccountAuthTestCheck.denies("access-cannot-refresh") { _ = try AccountAuthTransportPlan.refresh(captured: captured, proof: session.access, requestID: 4) }
        try AccountAuthWire.decodeRevokeAcknowledgement(Data("{\"revoked\":true}".utf8))
        for raw in ["{}", "{\"revoked\":false}", "{\"revoked\":1}", "{\"revoked\":true,\"message\":\"private\"}",
                    "{\"revoked\":true,\"\\u0072evoked\":true}", "{\"error\":\"verification_pending\"}"] {
            try AccountAuthTestCheck.denies("revoke-not-acknowledged") { try AccountAuthWire.decodeRevokeAcknowledgement(Data(raw.utf8)) }
        }
        return "transport-plan=3 reply-negative=24 kind-negative=2 revoke-negative=6"
    }
}
#if !ACCOUNT_AUTH_SOURCE_HOST
final class AccountAuthTransportTests: XCTestCase {
    func testClosedSyntheticTransportPlans() throws { _ = try AccountAuthTransportChecks.run(root: AccountAuthTestCheck.root()) }
}
#endif
