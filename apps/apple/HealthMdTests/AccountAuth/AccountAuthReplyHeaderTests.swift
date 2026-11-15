import Foundation
#if !ACCOUNT_AUTH_SOURCE_HOST
import XCTest
@testable import HealthMd
#endif

/// The fixture decoder ONLY determines whether a literal can cross the declared String-pair seam.
/// It never supplies a header verdict. Every representable literal goes to validatedBody(for:).
nonisolated enum AccountAuthReplyHeaderChecks {
    private struct Literal {
        let id: String
        let pairs: [AccountAuthReplyHeader]
        let valid: Bool
    }
    private static let unrepresentable: Set<String> = ["input-map", "input-null", "input-string", "pair-map",
        "pair-short", "pair-long", "pair-null", "name-boolean", "value-boolean", "name-number",
        "value-number", "name-null", "value-null"]

    private static func originalBytes(_ left: [AccountAuthReplyHeader], _ right: [AccountAuthReplyHeader]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { pair in
            pair.0.name.utf8.elementsEqual(pair.1.name.utf8) && pair.0.value.utf8.elementsEqual(pair.1.value.utf8)
        }
    }
    private static func denies(_ reply: AccountAuthTransportReply, plan: AccountAuthTransportPlan, category: String) throws {
        var rejected = false
        do { _ = try reply.validatedBody(for: plan) }
        catch let failure as AccountAuthSourceError {
            if case .malformed = failure { rejected = true }
            try AccountAuthTestCheck.require(String(describing: failure) == "malformed" &&
                Mirror(reflecting: failure).children.isEmpty, "header-error-has-no-reflecting-payload")
        }
        catch { throw AccountAuthTestCheck.Failed(category: "header-unexpected-error-type") }
        try AccountAuthTestCheck.require(rejected, category)
    }
    static func run(root: URL, headerRoot: URL) throws -> String {
        let bytes = try Data(contentsOf: headerRoot.appendingPathComponent(
            "packages/contracts/account-auth/v1/fixtures/native-reply-header-vectors.json"))
        let fixture = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        try AccountAuthTestCheck.require(fixture["schema"] as? String == "healthmd.account_auth.native_reply_header_vectors" &&
            fixture["schema_version"] as? Int == 1 && fixture["synthetic_only"] as? Bool == true &&
            fixture["native_consumers_qualified"] as? Bool == false && fixture["grants_authority"] as? Bool == false &&
            fixture["policy_sha256"] as? String == "8ca01a50ebae81ac50dbb8551f15023d611ed83b4076ea16c4ab74213f5b3ef7" &&
            fixture["operations"] as? [String] == ["code_exchange", "refresh", "revoke"], "header-fixture-profile")
        let rows = fixture["cases"] as! [[String: Any]]
        var literals: [Literal] = [], excluded: Set<String> = [], ids: Set<String> = []
        var totalPositives = 0
        for row in rows {
            let id = row["id"] as! String, valid = row["valid"] as! Bool
            try AccountAuthTestCheck.require(ids.insert(id).inserted, "header-fixture-unique-id")
            if valid { totalPositives += 1 }
            guard let pairs = row["pairs"] as? [[String]], pairs.allSatisfy({ $0.count == 2 }) else {
                // Not a native rejection or pass: these thirteen values cannot construct the typed DTO.
                try AccountAuthTestCheck.require(!valid && unrepresentable.contains(id), "header-unrepresentable-classification")
                excluded.insert(id)
                continue
            }
            try AccountAuthTestCheck.require(!unrepresentable.contains(id), "header-no-false-exclusion")
            literals.append(Literal(id: id, pairs: pairs.map { AccountAuthReplyHeader(name: $0[0], value: $0[1]) }, valid: valid))
        }
        try AccountAuthTestCheck.require(rows.count == 99 && totalPositives == 9 && excluded == unrepresentable &&
            literals.count == 86 && literals.filter(\.valid).count == 9, "header-exact-86-plus-13-classification")

        let native = try AccountAuthTestCheck.corpus(root: root)
        let row = (native["response_cases"] as! [[String: Any]])[0]
        let captured = try AccountAuthTestCheck.capture(row["context"] as! [String: String])
        let session = try AccountAuthWire.decodeSession(AccountAuthTestCheck.bytes(row), captured: captured)
        let pending = AccountAuthPending(captured: captured,
            pkce: AccountAuthPKCE(state: String(repeating: "A", count: 43), verifier: String(repeating: "C", count: 43),
                challenge: "lCAUrwMZXJf8imEhoD4WYLiQJ6U4MloQHrpCbazX5Yc"), localGeneration: 1, expiresAt: 400)
        let code = try AccountAuthSecret("hmd_acode_" + String(repeating: "A", count: 43), kind: .code)
        let plans = [try AccountAuthTransportPlan.exchange(pending: pending, code: code, requestID: 11),
            try .refresh(captured: captured, proof: session.refresh, requestID: 12),
            try .revoke(captured: captured, proof: session.refresh, requestID: 13)]
        var positives = 0, negatives = 0, statusErrors = 0
        for plan in plans {
            let body = plan.operation == .revoke ? Data("{\"revoked\":true}".utf8) : AccountAuthTestCheck.bytes(row)
            for literal in literals {
                var callerPairs = literal.pairs
                let reply = AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint,
                    redirectHistory: [], status: 200, headers: callerPairs, body: body)
                callerPairs.removeAll() // Genuine value ownership, not a mutable array shared with the caller.
                if literal.valid {
                    try AccountAuthTestCheck.require(try reply.validatedBody(for: plan) == body,
                        "header-literal-positive-" + literal.id)
                    try AccountAuthTestCheck.require(originalBytes(reply.headers, literal.pairs), "header-original-order-case-value-bytes")
                    var returnedPairs = reply.headers
                    returnedPairs[0] = AccountAuthReplyHeader(name: "X-Changed", value: "changed")
                    try AccountAuthTestCheck.require(originalBytes(reply.headers, literal.pairs), "header-returned-array-cannot-mutate-receipt")
                    positives += 1
                } else {
                    try denies(reply, plan: plan, category: "header-literal-negative-" + literal.id)
                    negatives += 1
                }
                try AccountAuthTestCheck.require(String(describing: reply) == "[synthetic account-auth transport reply redacted]" &&
                    Mirror(reflecting: reply).children.isEmpty && reply.headers.allSatisfy {
                        String(describing: $0) == "[synthetic account-auth header redacted]" && Mirror(reflecting: $0).children.isEmpty
                    }, "header-receipt-and-pairs-nonreflecting")
            }
            // Header success never overrides the original status/error/body contract.
            let errors = native["error_cases"] as! [[String: Any]]
            for error in errors {
                let body = AccountAuthTestCheck.bytes(error)
                if error["valid"] as! Bool {
                    let expected = AccountAuthFailure(rawValue: error["expected"] as! String)!
                    let status: Int
                    switch expected {
                    case .unavailable, .verificationPending: status = 503
                    case .invalidRequest, .invalidGrant, .reuseFamilyRevoked: status = 400
                    case .unauthorized: status = 401
                    case .forbidden: status = 403
                    case .notFound: status = 404
                    case .rateLimited: status = 429
                    }
                    let reply = AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint,
                        redirectHistory: [], status: status, headers: AccountAuthTransportChecks.replyHeaders, body: body)
                    var observed: AccountAuthFailure?
                    do { _ = try reply.validatedBody(for: plan) } catch let failure as AccountAuthFailure { observed = failure }
                    try AccountAuthTestCheck.require(observed == expected, "header-preserves-fixed-status-error")
                    let wrong = AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint,
                        redirectHistory: [], status: status + 1, headers: AccountAuthTransportChecks.replyHeaders, body: body)
                    try denies(wrong, plan: plan, category: "header-error-status-mismatch")
                    statusErrors += 2
                } else {
                    let reply = AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint,
                        redirectHistory: [], status: 400, headers: AccountAuthTransportChecks.replyHeaders, body: body)
                    try denies(reply, plan: plan, category: "header-malformed-error-body")
                    statusErrors += 1
                }
            }
            let empty = AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint,
                redirectHistory: [], status: 200, headers: AccountAuthTransportChecks.replyHeaders, body: Data())
            try denies(empty, plan: plan, category: "header-empty-body-still-denied")
        }
        try AccountAuthTestCheck.require(positives == 27 && negatives == 231 && statusErrors == 72, "header-runtime-case-counts")
        return "reply-header-literals=86 positive=9 negative=77 per-operation=3 executed=258 positive=27 negative=231 unrepresentable-unexecuted=13 status-error=72 empty-body-negative=3 original-pairs=preserved"
    }
}
#if !ACCOUNT_AUTH_SOURCE_HOST
nonisolated final class AccountAuthReplyHeaderTests: XCTestCase {
    func testLiteralOrderedPairsAtActualReceiptSeam() throws {
        let root = AccountAuthTestCheck.root()
        let explicit = ProcessInfo.processInfo.environment["ACCOUNT_AUTH_REPLY_HEADER_ROOT"]
        _ = try AccountAuthReplyHeaderChecks.run(root: root, headerRoot: explicit.map { URL(fileURLWithPath: $0) } ?? root)
    }
}
#endif
