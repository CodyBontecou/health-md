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

/// Fake-transport receipt only. Echoed JSON or this DTO cannot certify real TLS/provenance.
nonisolated struct AccountAuthTransportReply: Sendable, CustomStringConvertible, CustomReflectable {
    let requestID: UInt64
    let effectiveEndpoint: String
    let redirectHistory: [String]
    let status: Int
    let headers: [String: String]
    let body: Data
    var description: String { "[synthetic account-auth transport reply redacted]" }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    func validatedBody(for plan: AccountAuthTransportPlan) throws -> Data {
        let keys = headers.keys.map { $0.lowercased() }
        guard requestID == plan.requestID, effectiveEndpoint == plan.endpoint, redirectHistory.isEmpty,
              body.count > 0, body.count <= plan.responseByteLimit, Set(keys).count == keys.count,
              !keys.contains("set-cookie"), !keys.contains("cookie"), !keys.contains("authorization") else {
            throw AccountAuthSourceError.malformed
        }
        let h = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
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
