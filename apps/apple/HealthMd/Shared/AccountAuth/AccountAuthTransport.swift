import Foundation

nonisolated struct AccountAuthTransportPlan: Sendable, CustomStringConvertible, CustomReflectable {
    enum Operation: Sendable { case exchange, refresh, revoke }
    let operation: Operation
    let requestID: UInt64
    let endpoint: String
    let method = "POST"
    let headers = ["Content-Type": "application/json", "Accept": "application/json"]
    let permitsCookies = false
    let permitsRedirects = false
    let permitsTransparentReplay = false
    let timeoutSeconds: UInt64 = 5
    let responseByteLimit = 8192
    private let body: Data

    private init(operation: Operation, requestID: UInt64, registration: AccountAuthRegistration,
                 fields: [String: String]) throws {
        self.operation = operation
        self.requestID = requestID
        endpoint = registration.issuer + (operation == .revoke ? "/api/account-auth/v1/revoke" : "/api/account-auth/v1/token")
        body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        guard body.count <= 8192 else { throw AccountAuthSourceError.malformed }
    }
    static func exchange(pending: AccountAuthPending, code: AccountAuthSecret, requestID: UInt64) throws -> Self {
        guard code.kind == .code else { throw AccountAuthSourceError.malformed }
        let r = pending.captured.registration
        return try Self(operation: .exchange, requestID: requestID, registration: r, fields: [
            "grant_type": "authorization_code", "client_id": r.clientID, "redirect_uri": r.callback,
            "code": code.wireValue(), "code_verifier": pending.pkce.verifier,
            "installation_id": pending.captured.installationID])
    }
    static func refresh(captured: AccountAuthCapture, proof: AccountAuthSecret, requestID: UInt64) throws -> Self {
        guard proof.kind == .refresh else { throw AccountAuthSourceError.malformed }
        return try Self(operation: .refresh, requestID: requestID, registration: captured.registration, fields: [
            "grant_type": "refresh_token", "client_id": captured.registration.clientID,
            "installation_id": captured.installationID, "refresh_token": proof.wireValue()])
    }
    static func revoke(captured: AccountAuthCapture, proof: AccountAuthSecret, requestID: UInt64) throws -> Self {
        guard proof.kind == .refresh else { throw AccountAuthSourceError.malformed }
        return try Self(operation: .revoke, requestID: requestID, registration: captured.registration, fields: [
            "client_id": captured.registration.clientID, "installation_id": captured.installationID,
            "refresh_token": proof.wireValue()])
    }
    func wireBody() -> Data { body }
    var description: String { "[account-auth transport plan redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Original decoded pair, not a raw HTTP stream or credential/provenance claim.
nonisolated struct AccountAuthReplyHeader: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
    let name: String
    let value: String
    var description: String { "[synthetic account-auth header redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Fake-transport receipt only. Echoed JSON or this DTO cannot certify real TLS/provenance.
nonisolated struct AccountAuthTransportReply: Sendable, CustomStringConvertible, CustomReflectable {
    let requestID: UInt64
    let effectiveEndpoint: String
    let redirectHistory: [String]
    let status: Int
    let headers: [AccountAuthReplyHeader]
    let body: Data
    init(requestID: UInt64, effectiveEndpoint: String, redirectHistory: [String], status: Int,
         headers: [AccountAuthReplyHeader], body: Data) {
        self.requestID = requestID; self.effectiveEndpoint = effectiveEndpoint
        self.redirectHistory = Array(redirectHistory); self.status = status
        self.headers = headers.map { AccountAuthReplyHeader(name: $0.name, value: $0.value) }
        self.body = body
    }
    var description: String { "[synthetic account-auth transport reply redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    func validatedBody(for plan: AccountAuthTransportPlan) throws -> Data {
        guard requestID == plan.requestID, effectiveEndpoint == plan.endpoint, redirectHistory.isEmpty,
              body.count > 0, body.count <= plan.responseByteLimit, headers.count <= 16 else {
            throw AccountAuthSourceError.malformed
        }
        // Inactive source profile v1: decoded pair bytes only, NOT HTTP framing/stream bounds.
        // ASCII grammar/budgets precede folding and insertion; original pairs are never rewritten.
        var h: [String: String] = [:]
        var total = 0
        for pair in headers {
            let name = pair.name.utf8, value = pair.value.utf8
            guard (1...64).contains(name.count), value.count <= 1024,
                  name.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                      (48...57).contains($0) || $0 == 45 }),
                  value.allSatisfy({ (32...126).contains($0) }) else { throw AccountAuthSourceError.malformed }
            total += name.count + value.count
            let folded = pair.name.lowercased()
            guard total <= 4096, h[folded] == nil,
                  !["cookie", "set-cookie", "authorization", "proxy-authorization"].contains(folded) else {
                throw AccountAuthSourceError.malformed
            }
            h[folded] = pair.value
        }
        guard ["application/json", "application/json; charset=utf-8"].contains(h["content-type"] ?? ""),
              h["cache-control"] == "no-store", h["referrer-policy"] == "no-referrer" else {
            throw AccountAuthSourceError.malformed
        }
        if status == 200 { return body }
        let code = try AccountAuthWire.decodeFailure(body)
        let expected: Int
        switch code {
        case .unavailable, .verificationPending: expected = 503
        case .invalidRequest, .invalidGrant, .reuseFamilyRevoked: expected = 400
        case .unauthorized: expected = 401
        case .forbidden: expected = 403
        case .notFound: expected = 404
        case .rateLimited: expected = 429
        }
        guard status == expected else { throw AccountAuthSourceError.malformed }
        throw code
    }
}

/// No URLSession/network implementation or retry loop is installed in this slice.
nonisolated protocol AccountAuthSyntheticTransport: Sendable {
    func send(_ plan: AccountAuthTransportPlan) async throws -> AccountAuthTransportReply
}
