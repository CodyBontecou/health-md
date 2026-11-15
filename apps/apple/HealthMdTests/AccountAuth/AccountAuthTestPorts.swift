import Foundation
#if !ACCOUNT_AUTH_SOURCE_HOST
@testable import HealthMd
#endif

// Only time/entropy/vault/transport SYSTEM boundaries are faulted; the coordinator/codecs/fence
// and the delegated synthetic vault transaction implementation are the actual source under test.
nonisolated final class AccountAuthTestEntropy: AccountAuthEntropy, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var fails = false
    private var wrongSize = false
    private let first: Data
    init(installation: String) {
        first = Data(base64Encoded: installation.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + "=")!
    }
    func configure(fails: Bool, wrongSize: Bool = false) {
        lock.lock(); defer { lock.unlock() }; self.fails = fails; self.wrongSize = wrongSize
    }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func bytes(count size: Int) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        count += 1
        if fails { throw AccountAuthSourceError.entropy }
        if wrongSize { return Data(repeating: 0, count: size - 1) }
        return count == 1 ? first : Data(repeating: UInt8(count % 256), count: size)
    }
}
nonisolated final class AccountAuthTestClock: AccountAuthClock, @unchecked Sendable {
    private let lock = NSLock()
    private var time: UInt64 = 100
    private var fails = false
    private var count = 0
    private var sequence: [UInt64] = []
    func configure(time: UInt64 = 100, fails: Bool = false) {
        lock.lock(); defer { lock.unlock() }; self.time = time; self.fails = fails; sequence = []
    }
    func configureSequence(_ times: [UInt64]) {
        lock.lock(); defer { lock.unlock() }
        sequence = times; time = times.last ?? 100; fails = false
    }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func seconds() throws -> UInt64 {
        lock.lock(); defer { lock.unlock() }; count += 1
        if fails { throw AccountAuthSourceError.uncertain }
        return sequence.isEmpty ? time : sequence.removeFirst()
    }
}
actor AccountAuthTestGate {
    private var entered = false
    private var released = false
    private var entrance: [CheckedContinuation<Void, Never>] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func pause() async {
        entered = true
        for c in entrance { c.resume() }; entrance = []
        if released { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entrance.append($0) }
    }
    func release() {
        released = true
        for c in waiting { c.resume() }; waiting = []
    }
}

actor AccountAuthFaultVault: AccountAuthVault {
    enum WriteMode: Sendable { case normal, noOp, lostReply }
    enum ReadMode: Sendable, CaseIterable { case normal, unreadable, corrupt, missingRecord, partialReceipt, stale, wrongOwner, wrongGeneration }
    let actual: AccountAuthSyntheticVault
    private var installMode: WriteMode = .normal
    private var eraseMode: WriteMode = .normal
    private var readMode: ReadMode = .normal
    private var afterInstall: ReadMode = .normal
    private var afterErase: ReadMode = .normal
    private var installGate: AccountAuthTestGate?
    private var eraseGate: AccountAuthTestGate?
    private var readGate: AccountAuthTestGate?
    private var readAfterInstallGate: AccountAuthTestGate?
    private var reads = 0
    private var writes = 0
    private var rejectedInstalls = 0
    init(actual: AccountAuthSyntheticVault = AccountAuthSyntheticVault()) { self.actual = actual }
    func counters() -> (Int, Int, Int) { (reads, writes, rejectedInstalls) }
    func configureInstall(write: WriteMode = .normal, readback: ReadMode = .normal) { installMode = write; afterInstall = readback }
    func configureErase(write: WriteMode = .normal, readback: ReadMode = .normal) { eraseMode = write; afterErase = readback }
    func configureRead(_ mode: ReadMode) { readMode = mode }
    func pauseInstall(_ gate: AccountAuthTestGate) { installGate = gate }
    func pauseErase(_ gate: AccountAuthTestGate) { eraseGate = gate }
    func pauseRead(_ gate: AccountAuthTestGate) { readGate = gate }
    func pauseReadAfterInstall(_ gate: AccountAuthTestGate) { readAfterInstallGate = gate }
    func transact(_ command: AccountAuthVaultCommand, fence: AccountAuthCommitFence) async throws {
        writes += 1
        var mode = WriteMode.normal
        if command.receipt.kind == .install {
            mode = installMode
            if let gate = installGate { installGate = nil; await gate.pause() }
        } else if command.receipt.kind == .erase {
            mode = eraseMode
            if let gate = eraseGate { eraseGate = nil; await gate.pause() }
        }
        if mode == .noOp { return }
        do { try await actual.transact(command, fence: fence) }
        catch { if command.receipt.kind == .install { rejectedInstalls += 1 }; throw error }
        if command.receipt.kind == .install {
            readMode = afterInstall
            if let gate = readAfterInstallGate { readAfterInstallGate = nil; readGate = gate }
        } else if command.receipt.kind == .erase { readMode = afterErase }
        if mode == .lostReply { throw AccountAuthSourceError.uncertain }
    }
    func read() async throws -> AccountAuthVaultSnapshot {
        reads += 1
        if let gate = readGate { readGate = nil; await gate.pause() }
        let s = await actual.read()
        let normal: AccountAuthStoredRecord?
        let receipt: AccountAuthVaultReceipt?
        var generation = s.durableGeneration
        var integrity = s.integrity
        switch readMode {
        case .unreadable: throw AccountAuthSourceError.uncertain
        case .corrupt: integrity = .corrupt; normal = s.normal; receipt = s.receipt
        case .missingRecord: normal = nil; receipt = s.receipt
        case .partialReceipt: normal = s.normal; receipt = nil
        case .stale: generation = generation == 0 ? 0 : generation - 1; normal = s.normal; receipt = s.receipt
        case .wrongOwner:
            if let row = s.normal {
                let a = row.session
                let b = AccountAuthSession(tokenType: a.tokenType, access: a.access, expiresIn: a.expiresIn,
                    refresh: a.refresh, sessionID: a.sessionID, scope: a.scope,
                    namespace: AccountAuthNamespace(issuer: a.namespace.issuer, environment: a.namespace.environment, accountID: "synthetic-account-b"),
                    audience: a.audience, clientID: a.clientID, installationID: a.installationID, serverGeneration: a.serverGeneration)
                normal = AccountAuthStoredRecord(captured: row.captured, session: b,
                    localGeneration: row.localGeneration, leaseStart: row.leaseStart, requestID: row.requestID)
            } else { normal = nil }
            receipt = s.receipt
        case .wrongGeneration:
            normal = s.normal.map { AccountAuthStoredRecord(captured: $0.captured, session: $0.session,
                localGeneration: $0.localGeneration + 1, leaseStart: $0.leaseStart, requestID: $0.requestID) }
            receipt = s.receipt
        case .normal: normal = s.normal; receipt = s.receipt
        }
        return AccountAuthVaultSnapshot(integrity: integrity, durableGeneration: generation, normal: normal, receipt: receipt)
    }
}

actor AccountAuthFaultTransport: AccountAuthSyntheticTransport {
    enum Reply: Sendable { case body(Data, Int), lost, wrongCorrelation(Data), redirect(Data) }
    private var exchangeReplies: [Reply] = []
    private var refreshReplies: [Reply] = []
    private var revokeReplies: [Reply] = []
    private var gate: AccountAuthTestGate?
    private var plans: [AccountAuthTransportPlan] = []
    func enqueue(_ reply: Reply, operation: AccountAuthTransportPlan.Operation) {
        switch operation { case .exchange: exchangeReplies.append(reply); case .refresh: refreshReplies.append(reply); case .revoke: revokeReplies.append(reply) }
    }
    func pauseNext(_ gate: AccountAuthTestGate) { self.gate = gate }
    func sent() -> [AccountAuthTransportPlan] { plans }
    func send(_ plan: AccountAuthTransportPlan) async throws -> AccountAuthTransportReply {
        plans.append(plan)
        let response: Reply
        switch plan.operation {
        case .exchange: guard !exchangeReplies.isEmpty else { throw AccountAuthSourceError.uncertain }; response = exchangeReplies.removeFirst()
        case .refresh: guard !refreshReplies.isEmpty else { throw AccountAuthSourceError.uncertain }; response = refreshReplies.removeFirst()
        case .revoke: guard !revokeReplies.isEmpty else { throw AccountAuthSourceError.uncertain }; response = revokeReplies.removeFirst()
        }
        if let gate { self.gate = nil; await gate.pause() }
        switch response {
        case .lost: throw AccountAuthSourceError.uncertain
        case .body(let body, let status):
            return AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint, redirectHistory: [],
                status: status, headers: AccountAuthTransportChecks.replyHeaders, body: body)
        case .wrongCorrelation(let body):
            return AccountAuthTransportReply(requestID: plan.requestID + 1, effectiveEndpoint: plan.endpoint, redirectHistory: [],
                status: 200, headers: AccountAuthTransportChecks.replyHeaders, body: body)
        case .redirect(let body):
            return AccountAuthTransportReply(requestID: plan.requestID, effectiveEndpoint: plan.endpoint, redirectHistory: [plan.endpoint],
                status: 200, headers: AccountAuthTransportChecks.replyHeaders, body: body)
        }
    }
}

nonisolated struct AccountAuthTestRig: Sendable {
    let coordinator: AccountAuthCoordinator
    let entropy: AccountAuthTestEntropy
    let clock: AccountAuthTestClock
    let vault: AccountAuthFaultVault
    let transport: AccountAuthFaultTransport
    let initial: Data
    let refreshed: Data
    let scope: String
    let registration: AccountAuthRegistration
    init(root: URL, client: AccountAuthAppleClient = .iOS, localGeneration: UInt64 = 0,
         vault: AccountAuthFaultVault = AccountAuthFaultVault(), recreated: Bool = false) throws {
        let corpus = try AccountAuthTestCheck.corpus(root: root)
        let rows = corpus["response_cases"] as! [[String: Any]]
        let row = rows.first { $0["id"] as? String == "success-\(client.rawValue)" }!
        let c = row["context"] as! [String: String]
        scope = c["scope"]!
        initial = AccountAuthTestCheck.bytes(row)
        var next = try JSONSerialization.jsonObject(with: initial) as! [String: Any]
        next["session_generation"] = 1
        next["access_token"] = "hmd_nac_" + String(repeating: "B", count: 42) + "A"
        next["refresh_token"] = "hmd_nrf_" + String(repeating: "T", count: 42) + "A"
        refreshed = try JSONSerialization.data(withJSONObject: next, options: [.sortedKeys])
        entropy = AccountAuthTestEntropy(installation: c["installation_id"]!)
        clock = AccountAuthTestClock()
        self.vault = vault
        transport = AccountAuthFaultTransport()
        registration = .reviewedSynthetic(apple: client)
        coordinator = AccountAuthCoordinator(syntheticForSourceTests: client, consent: .sourceMetadataOnly,
            entropy: entropy, clock: clock, vault: vault, transport: transport,
            initialLocalGeneration: localGeneration, recreated: recreated)
    }
    func begin() async throws -> AccountAuthAuthorizationPlan { try await coordinator.begin(scope: scope) }
    func callback(plan: AccountAuthAuthorizationPlan, denial: Bool = false) throws -> Data {
        let parts = URLComponents(string: plan.syntheticReviewURL())!.queryItems!
        let state = parts.first(where: { $0.name == "state" })!.value!
        let outcome = denial ? "error=access_denied" : "code=hmd_acode_" + String(repeating: "A", count: 43)
        return Data("\(registration.callback)?\(outcome)&state=\(state)&iss=\(registration.issuer)".utf8)
    }
    func signIn() async throws {
        await transport.enqueue(.body(initial, 200), operation: .exchange)
        let plan = try await begin()
        let result = await coordinator.consumeCallback(try callback(plan: plan))
        try AccountAuthTestCheck.require(result == .installed, "synthetic-signin")
    }
    func replacement(_ body: Data, fields: [String: Any]) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        for (key, value) in fields { object[key] = value }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
