import Foundation
#if !ACCOUNT_AUTH_SOURCE_HOST
import XCTest
@testable import HealthMd
#endif

nonisolated enum AccountAuthLifecycleChecks {
    private static func require(_ value: Bool, _ category: String) throws { try AccountAuthTestCheck.require(value, category) }
    private static func asyncDenies(_ category: String, _ action: () async throws -> Void) async throws {
        var denied = false
        do { try await action() } catch { denied = true }
        try require(denied, category)
    }
    private static func until(_ condition: () async -> Bool) async throws {
        for _ in 0..<10_000 { if await condition() { return }; await Task.yield() }
        throw AccountAuthTestCheck.Failed(category: "race-progress-bound")
    }
    private static func count(_ rig: AccountAuthTestRig, _ operation: AccountAuthTransportPlan.Operation) async -> Int {
        await rig.transport.sent().filter { $0.operation == operation }.count
    }

    private static func defaultZero(root: URL) async throws {
        let rig = try AccountAuthTestRig(root: root)
        rig.entropy.configure(fails: true); rig.clock.configure(fails: true)
        await rig.vault.configureRead(.unreadable)
        let owners = [AccountAuthCoordinator(),
            AccountAuthCoordinator(syntheticForSourceTests: nil, consent: .sourceMetadataOnly,
                entropy: rig.entropy, clock: rig.clock, vault: rig.vault, transport: rig.transport),
            AccountAuthCoordinator(syntheticForSourceTests: .iOS, consent: nil,
                entropy: rig.entropy, clock: rig.clock, vault: rig.vault, transport: rig.transport),
            AccountAuthCoordinator(syntheticForSourceTests: nil, consent: nil,
                entropy: rig.entropy, clock: rig.clock, vault: rig.vault, transport: rig.transport)]
        for owner in owners {
            let before = await owner.snapshot()
            try require(before.phase == .unavailable && before.namespace == nil, "absent-admission-unavailable")
            try await asyncDenies("absent-admission-begin") { _ = try await owner.begin(scope: rig.scope) }
            await owner.cancel()
            try require(await owner.consumeCallback(Data("untrusted".utf8)) == .unavailable, "absent-admission-callback")
            try require(await owner.refresh() == .unavailable, "absent-admission-refresh")
            let erased = await owner.signOut()
            let switched = await owner.switchAccount()
            let revoked = await owner.retryRemoteRevocation()
            try require(erased == before && switched == before && revoked == before, "absent-admission-cleanup-inert")
            try require(await owner.snapshot() == before, "absent-admission-status-inert")
        }
        let counters = await rig.vault.counters()
        let requests = await rig.transport.sent()
        try require(rig.entropy.calls == 0 && rig.clock.calls == 0 && counters.0 == 0 && counters.1 == 0 &&
            requests.isEmpty, "zero-all-system-ports")
    }
    private static func priorMissingRecord(root: URL) async throws {
        let old = try AccountAuthTestRig(root: root)
        try await old.signIn()
        let populated = await old.vault.actual.read()
        try require(populated.normal != nil && populated.receipt?.kind == .install, "prior-custody-real-install")
        let boundary = AccountAuthFaultVault(actual: old.vault.actual)
        await boundary.configureRead(.missingRecord)
        let partial = try await boundary.read()
        try require(partial.integrity == .complete && partial.normal == nil && partial.receipt == populated.receipt,
            "prior-custody-missing-row-retains-install-receipt")
        let fresh = try AccountAuthTestRig(root: root, vault: boundary)
        let plan = try await fresh.begin()
        let state = await fresh.coordinator.snapshot()
        let cleared = await boundary.actual.read()
        try require(cleared.normal == nil && cleared.receipt?.kind == .prepare && state.localErase == .verified &&
            state.namespace == nil && state.remoteRevoke == .unknown, "prior-missing-row-begin-preserves-unknown")
        await boundary.configureRead(.normal)
        let different = try fresh.replacement(fresh.initial, fields: ["account_id": "synthetic-account-b",
            "session_id": String(repeating: "F", count: 42) + "A",
            "access_token": "hmd_nac_" + String(repeating: "D", count: 42) + "A",
            "refresh_token": "hmd_nrf_" + String(repeating: "U", count: 42) + "A"])
        await fresh.transport.enqueue(.body(different, 200), operation: .exchange)
        try require(await fresh.coordinator.consumeCallback(try fresh.callback(plan: plan)) == .installed,
            "prior-missing-row-fresh-different-family")
        let installed = await boundary.actual.read()
        try require(installed.normal?.session.namespace.accountID == "synthetic-account-b" &&
            installed.normal?.session.sessionID != populated.normal?.session.sessionID, "new-family-real-custody-only")
        let out = await fresh.coordinator.signOut()
        let erased = await boundary.actual.read()
        try require(out.localErase == .verified && out.remoteRevoke == .pending && erased.normal == nil &&
            erased.receipt?.kind == .erase, "unknown-prior-and-known-new-family-independent-of-erasure")
        await fresh.transport.enqueue(.body(Data("{\"revoked\":true}".utf8), 200), operation: .revoke)
        let ack = await fresh.coordinator.retryRemoteRevocation()
        let requests = await fresh.transport.sent()
        let revoke = requests.filter { $0.operation == .revoke }
        let fields = try JSONSerialization.jsonObject(with: revoke[0].wireBody()) as! [String: String]
        try require(ack.remoteRevoke == .unknown && ack.localErase == .verified && ack.namespace == nil &&
            revoke.count == 1 && fields["refresh_token"] == installed.normal?.session.refresh.wireValue() &&
            fields["refresh_token"] != populated.normal?.session.refresh.wireValue(), "different-family-ack-not-prior-confirmation")
        _ = await fresh.coordinator.retryRemoteRevocation()
        try require(await count(fresh, .revoke) == 1, "unknown-prior-has-no-adopted-revoke-proof")

        let oldDirect = try AccountAuthTestRig(root: root)
        try await oldDirect.signIn()
        let directBoundary = AccountAuthFaultVault(actual: oldDirect.vault.actual)
        await directBoundary.configureRead(.missingRecord)
        let direct = try AccountAuthTestRig(root: root, vault: directBoundary)
        let signedOut = await direct.coordinator.signOut()
        let directlyErased = await directBoundary.actual.read()
        try require(signedOut.localErase == .verified && signedOut.durableFence == .verified &&
            signedOut.remoteRevoke == .unknown && directlyErased.normal == nil && directlyErased.receipt?.kind == .erase,
            "direct-signout-missing-installed-row-remains-unknown")
        _ = await direct.coordinator.retryRemoteRevocation()
        try require(await direct.transport.sent().isEmpty, "direct-signout-no-unproven-proof-adoption")

        let empty = try AccountAuthTestRig(root: root)
        let bootstrap = await empty.vault.actual.read()
        try require(bootstrap.normal == nil && bootstrap.receipt == nil && bootstrap.durableGeneration == 0,
            "structurally-empty-bootstrap")
        _ = try await empty.begin()
        let emptyPrepared = await empty.coordinator.snapshot()
        try require(emptyPrepared.remoteRevoke == .notRequested && emptyPrepared.localErase == .verified,
            "coherent-empty-bootstrap-does-not-invent-unknown")
        let emptyErased = await empty.coordinator.signOut()
        try require(emptyErased.remoteRevoke == .notRequested && emptyErased.localErase == .verified,
            "coherent-empty-prepare-does-not-invent-unknown")
        let newEmpty = try AccountAuthTestRig(root: root, vault: AccountAuthFaultVault(actual: empty.vault.actual))
        _ = try await newEmpty.begin()
        try require(await newEmpty.coordinator.snapshot().remoteRevoke == .notRequested,
            "coherent-empty-erase-does-not-invent-unknown")
    }
    private static func pendingAndCancel(root: URL) async throws {
        let rig = try AccountAuthTestRig(root: root)
        let plan = try await rig.begin()
        let before = await rig.vault.counters()
        try await asyncDenies("one-pending-attempt") { _ = try await rig.begin() }
        let after = await rig.vault.counters()
        try require(before.0 == after.0 && before.1 == after.1 && rig.entropy.calls == 3, "second-attempt-no-ports")
        await rig.coordinator.cancel()
        let cancelled = await rig.coordinator.consumeCallback(try rig.callback(plan: plan))
        let cancelledState = await rig.coordinator.snapshot()
        let cancelledCalls = await count(rig, .exchange)
        try require(cancelled == .superseded && cancelledState.phase == .cancelled && cancelledCalls == 0, "cancel-late-callback")
        let preparing = try AccountAuthTestRig(root: root), gate = AccountAuthTestGate()
        await preparing.vault.pauseRead(gate)
        let start = Task { try await preparing.begin() }
        await gate.waitUntilEntered()
        try await asyncDenies("one-preparing-attempt") { _ = try await preparing.begin() }
        await preparing.coordinator.cancel(); await gate.release()
        try await asyncDenies("cancel-before-attempt-material") { _ = try await start.value }
        try require(preparing.entropy.calls == 0, "cancelled-prepare-no-entropy")
        let denial = try AccountAuthTestRig(root: root)
        let deniedPlan = try await denial.begin()
        let denied = await denial.coordinator.consumeCallback(try denial.callback(plan: deniedPlan, denial: true))
        let deniedCalls = await count(denial, .exchange)
        try require(denied == .denied && deniedCalls == 0, "denied-consumes-without-network")
        try require(await denial.coordinator.consumeCallback(try denial.callback(plan: deniedPlan)) == .superseded, "denial-no-replay")
        let timeout = try AccountAuthTestRig(root: root)
        let timedPlan = try await timeout.begin()
        timeout.clock.configure(time: 400)
        let timed = await timeout.coordinator.consumeCallback(try timeout.callback(plan: timedPlan))
        let timedCalls = await count(timeout, .exchange)
        try require(timed == .superseded && timedCalls == 0, "attempt-expiry-equality")
        for wrongSize in [false, true] {
            let entropy = try AccountAuthTestRig(root: root)
            entropy.entropy.configure(fails: !wrongSize, wrongSize: wrongSize)
            try await asyncDenies("entropy-no-fallback") { _ = try await entropy.begin() }
            let calls = await count(entropy, .exchange)
            try require(entropy.entropy.calls == 1 && calls == 0, "entropy-failure-no-success")
        }
    }
    private static func callbackReplayAndSwitch(root: URL) async throws {
        for switching in [false, true] {
            let rig = try AccountAuthTestRig(root: root)
            await rig.transport.enqueue(.body(rig.initial, 200), operation: .exchange)
            let plan = try await rig.begin(), raw = try rig.callback(plan: plan)
            let gate = AccountAuthTestGate(); await rig.transport.pauseNext(gate)
            let request = Task { await rig.coordinator.consumeCallback(raw) }
            await gate.waitUntilEntered()
            let replay = await rig.coordinator.consumeCallback(raw)
            let replayCalls = await count(rig, .exchange)
            try require(replay == .superseded && replayCalls == 1, "callback-one-consumption")
            if switching {
                let state = await rig.coordinator.switchAccount()
                try require(state.phase == .signedOut && state.namespace == nil && state.localErase == .verified &&
                    state.remoteRevoke == .unknown, "switch-unknown-inflight-family")
            }
            await gate.release()
            try require(await request.value == (switching ? .superseded : .installed), "late-exchange-fence")
            let stored = await rig.vault.actual.read()
            try require(switching ? stored.normal == nil : stored.normal?.session.serverGeneration == 0, "exchange-vault-postcondition")
            if switching {
                _ = await rig.coordinator.retryRemoteRevocation()
                try require(await count(rig, .revoke) == 0, "unknown-family-not-fictitious-revoke")
            }
        }
    }
    private static func installFaults(root: URL) async throws {
        let noop = try AccountAuthTestRig(root: root)
        await noop.vault.configureInstall(write: .noOp)
        await noop.transport.enqueue(.body(noop.initial, 200), operation: .exchange)
        let plan = try await noop.begin()
        let noWrite = await noop.coordinator.consumeCallback(try noop.callback(plan: plan))
        let noWriteState = await noop.coordinator.snapshot()
        let noWriteRow = await noop.vault.actual.read()
        try require(noWrite == .uncertain && noWriteState.namespace == nil && noWriteRow.normal == nil, "install-noop-not-success")
        let known = await noop.coordinator.signOut()
        try require(known.remoteRevoke == .pending && known.localErase == .verified, "parsed-custody-failure-retains-revoke-knowledge")
        let lost = try AccountAuthTestRig(root: root)
        await lost.vault.configureInstall(write: .lostReply)
        try await lost.signIn()
        try require(await lost.vault.actual.read().normal?.session.serverGeneration == 0, "lost-install-reply-exact-readback")
        for fault in AccountAuthFaultVault.ReadMode.allCases where fault != .normal {
            let rig = try AccountAuthTestRig(root: root)
            await rig.vault.configureInstall(readback: fault)
            await rig.transport.enqueue(.body(rig.initial, 200), operation: .exchange)
            let plan = try await rig.begin()
            let result = await rig.coordinator.consumeCallback(try rig.callback(plan: plan))
            let state = await rig.coordinator.snapshot()
            try require(result == .uncertain && state.namespace == nil && state.localErase == .uncertain &&
                state.durableFence == .uncertain, "install-readback-fault-quarantine")
            let actuallyCommitted = await rig.vault.actual.read()
            try require(actuallyCommitted.normal != nil, "actual-install-commit-before-faulted-readback")
            await rig.vault.configureRead(.normal)
            let out = await rig.coordinator.signOut()
            try require(out.remoteRevoke == .pending && out.localErase == .verified, "uncertain-account-cleanup-still-admitted")
        }
    }
    private static func installRaces(root: URL) async throws {
        for afterCommit in [false, true] {
            let rig = try AccountAuthTestRig(root: root)
            let gate = AccountAuthTestGate()
            if afterCommit { await rig.vault.pauseReadAfterInstall(gate) } else { await rig.vault.pauseInstall(gate) }
            await rig.transport.enqueue(.body(rig.initial, 200), operation: .exchange)
            let plan = try await rig.begin(), raw = try rig.callback(plan: plan)
            let request = Task { await rig.coordinator.consumeCallback(raw) }
            await gate.waitUntilEntered()
            let before = await rig.vault.actual.read()
            try require(afterCommit ? before.normal != nil : before.normal == nil, "real-commit-race-stage")
            let signedOut = await rig.coordinator.signOut()
            try require(signedOut.namespace == nil && signedOut.localErase == .verified, "signout-during-install")
            await gate.release()
            let result = await request.value
            let finalState = await rig.coordinator.snapshot()
            let finalRow = await rig.vault.actual.read()
            try require(result == .superseded && finalState.phase == .signedOut && finalRow.normal == nil, "no-late-install-or-visibility")
            let counters = await rig.vault.counters()
            try require(counters.2 == (afterCommit ? 0 : 1), "actual-authoritative-fence-rejection")
        }
        let cancelled = try AccountAuthTestRig(root: root), gate = AccountAuthTestGate()
        await cancelled.vault.pauseInstall(gate)
        await cancelled.transport.enqueue(.body(cancelled.initial, 200), operation: .exchange)
        let plan = try await cancelled.begin(), raw = try cancelled.callback(plan: plan)
        let task = Task { await cancelled.coordinator.consumeCallback(raw) }
        await gate.waitUntilEntered(); task.cancel(); await gate.release()
        let cancelledResult = await task.value
        let cancelledRow = await cancelled.vault.actual.read()
        let cancelledState = await cancelled.coordinator.snapshot()
        try require(cancelledResult == .uncertain && cancelledRow.normal == nil && cancelledState.namespace == nil, "caller-cancellation-at-commit")
        let cleaned = await cancelled.coordinator.signOut()
        try require(cleaned.remoteRevoke == .pending, "cancelled-custody-still-revoke-obligation")
    }
    private static func initialZero(root: URL) async throws {
        for client in AccountAuthAppleClient.allCases {
            let rig = try AccountAuthTestRig(root: root, client: client)
            try await rig.signIn()
            let s = await rig.vault.actual.read()
            try require(s.normal?.session.clientID == client.rawValue && s.normal?.session.serverGeneration == 0 &&
                s.normal?.localGeneration == 1, "apple-client-and-two-generations")
        }
        for generation in [UInt64(1), AccountAuthWire.maximumSafeInteger] {
            let rig = try AccountAuthTestRig(root: root)
            await rig.transport.enqueue(.body(try rig.replacement(rig.initial, fields: ["session_generation": generation]), 200), operation: .exchange)
            let plan = try await rig.begin()
            let result = await rig.coordinator.consumeCallback(try rig.callback(plan: plan))
            let stored = await rig.vault.actual.read()
            try require(result == .uncertain && stored.normal == nil, "nonzero-initial-denied")
        }
    }
    private static func serializedRefresh(root: URL) async throws {
        for seam in 0..<3 {
            let rig = try AccountAuthTestRig(root: root)
            try await rig.signIn()
            let old = await rig.vault.actual.read().normal!
            let gate = AccountAuthTestGate()
            if seam == 0 { await rig.vault.pauseRead(gate) }
            if seam == 1 { await rig.transport.pauseNext(gate) }
            if seam == 2 { await rig.vault.pauseInstall(gate) }
            await rig.transport.enqueue(.body(rig.refreshed, 200), operation: .refresh)
            let first = Task { await rig.coordinator.refresh() }
            await gate.waitUntilEntered()
            let second = Task { await rig.coordinator.refresh() }
            try await until { await rig.coordinator.snapshot().refreshCallers == 2 }
            await gate.release()
            let firstResult = await first.value
            let secondResult = await second.value
            let calls = await count(rig, .refresh)
            try require(firstResult == .installed && secondResult == .installed && calls == 1, "serialized-refresh-one-parent")
            let next = await rig.vault.actual.read().normal!
            try require(next.session.namespace == old.session.namespace && next.captured == old.captured &&
                next.session.sessionID == old.session.sessionID && next.session.serverGeneration == 1 &&
                next.localGeneration == old.localGeneration && next.session.access != old.session.access &&
                next.session.refresh != old.session.refresh, "refresh-preserves-all-bindings")
            let requests = await rig.transport.sent().filter { $0.operation == .refresh }
            let request = try JSONSerialization.jsonObject(with: requests[0].wireBody()) as! [String: String]
            try require(request["refresh_token"] == old.session.refresh.wireValue(), "actual-parent-consumption")
            // Next explicit refresh uses the child, never the consumed parent.
            let thirdBody = try rig.replacement(rig.refreshed, fields: ["session_generation": 2,
                "access_token": "hmd_nac_" + String(repeating: "N", count: 42) + "A",
                "refresh_token": "hmd_nrf_" + String(repeating: "O", count: 42) + "A"])
            await rig.transport.enqueue(.body(thirdBody, 200), operation: .refresh)
            try require(await rig.coordinator.refresh() == .installed, "explicit-next-child-refresh")
            let final = await rig.transport.sent().last!
            let finalBody = try JSONSerialization.jsonObject(with: final.wireBody()) as! [String: String]
            try require(finalBody["refresh_token"] == next.session.refresh.wireValue(), "no-parent-replay-after-rotation")
        }
    }
    private static func refreshFaults(root: URL) async throws {
        let patches: [[String: Any]] = [
            ["account_id": "synthetic-account-b"], ["client_id": "synthetic-android-play"],
            ["installation_id": String(repeating: "J", count: 42) + "A"],
            ["session_id": String(repeating: "F", count: 42) + "A"], ["scope": "config:profiles:read"],
            ["session_generation": 0], ["session_generation": 2], ["session_generation": AccountAuthWire.maximumSafeInteger],
            ["access_token": "hmd_acode_" + String(repeating: "A", count: 43)],
            ["refresh_token": "hmd_nac_" + String(repeating: "A", count: 43)],
            ["access_token": "hmd_nac_" + String(repeating: "A", count: 43)],
            ["refresh_token": "hmd_nrf_" + String(repeating: "R", count: 42) + "A"]]
        for patch in patches {
            let rig = try AccountAuthTestRig(root: root)
            try await rig.signIn()
            await rig.transport.enqueue(.body(try rig.replacement(rig.refreshed, fields: patch), 200), operation: .refresh)
            let result = await rig.coordinator.refresh()
            let state = await rig.coordinator.snapshot()
            try require(result == .uncertain && state.namespace == nil, "refresh-binding-fault-quarantine")
            let retried = await rig.coordinator.refresh()
            let calls = await count(rig, .refresh)
            try require(retried == .superseded && calls == 1, "refresh-fault-no-replay")
            let out = await rig.coordinator.signOut()
            try require(out.remoteRevoke == .pending, "wrong-owner-quarantine-retains-own-family")
        }
        let unreadableCommit = try AccountAuthTestRig(root: root)
        try await unreadableCommit.signIn()
        await unreadableCommit.vault.configureInstall(readback: .unreadable)
        await unreadableCommit.transport.enqueue(.body(unreadableCommit.refreshed, 200), operation: .refresh)
        let unreadableResult = await unreadableCommit.coordinator.refresh()
        let unreadableState = await unreadableCommit.coordinator.snapshot()
        let committedChild = await unreadableCommit.vault.actual.read()
        try require(unreadableResult == .uncertain && unreadableState.namespace == nil && unreadableState.localErase == .uncertain &&
            unreadableState.durableFence == .uncertain && committedChild.normal?.session.serverGeneration == 1,
            "refresh-current-custody-proof-not-prior-clear-receipt")
        let unreadableOut = await unreadableCommit.coordinator.signOut()
        try require(unreadableOut.remoteRevoke == .pending && unreadableOut.localErase == .verified, "refresh-uncertain-commit-cleanup")
        for fault in [AccountAuthFaultVault.ReadMode.wrongOwner, .wrongGeneration, .partialReceipt, .missingRecord, .corrupt, .stale] {
            let rig = try AccountAuthTestRig(root: root)
            try await rig.signIn(); await rig.vault.configureRead(fault)
            let result = await rig.coordinator.refresh()
            let calls = await count(rig, .refresh)
            try require(result == .uncertain && calls == 0, "vault-load-fault-before-proof")
            await rig.vault.configureRead(.normal)
            try require(await rig.coordinator.signOut().remoteRevoke == .pending, "custody-quarantine-revoke-knowledge")
        }
        for reply in [AccountAuthFaultTransport.Reply.lost,
            .body(Data("{\"error\":\"verification_pending\"}".utf8), 503),
            .body(Data("{\"error\":\"reuse_family_revoked\"}".utf8), 400)] {
            let rig = try AccountAuthTestRig(root: root)
            try await rig.signIn(); await rig.transport.enqueue(reply, operation: .refresh)
            let result = await rig.coordinator.refresh()
            let state = await rig.coordinator.snapshot()
            try require(result != .installed && state.namespace == nil, "ambiguous-or-reused-refresh")
            let retried = await rig.coordinator.refresh()
            let calls = await count(rig, .refresh)
            try require(retried == .superseded && calls == 1, "lost-refresh-no-parent-replay")
            try require(await rig.coordinator.signOut().remoteRevoke == .pending, "lost-refresh-revoke-only-parent")
            await rig.transport.enqueue(.body(Data("{\"revoked\":true}".utf8), 200), operation: .revoke)
            try require(await rig.coordinator.retryRemoteRevocation().remoteRevoke == .confirmed, "spent-parent-self-revoke-only")
        }
    }
    private static func refreshSignoutRaces(root: URL) async throws {
        for seam in 0..<3 {
            let rig = try AccountAuthTestRig(root: root)
            try await rig.signIn()
            let gate = AccountAuthTestGate()
            if seam == 0 { await rig.vault.pauseRead(gate) }
            if seam == 1 { await rig.transport.pauseNext(gate) }
            if seam == 2 { await rig.vault.pauseInstall(gate) }
            await rig.transport.enqueue(.body(rig.refreshed, 200), operation: .refresh)
            let task = Task { await rig.coordinator.refresh() }
            await gate.waitUntilEntered()
            let out = await rig.coordinator.signOut()
            try require(out.namespace == nil && out.localErase == .verified && out.remoteRevoke == .pending, "refresh-immediate-signout-fence")
            await gate.release()
            let result = await task.value
            let stored = await rig.vault.actual.read()
            let state = await rig.coordinator.snapshot()
            try require(result == .superseded && stored.normal == nil && state.phase == .signedOut, "late-refresh-cannot-install")
        }
    }
    private static func signoutFaultsAndRestart(root: URL) async throws {
        let noop = try AccountAuthTestRig(root: root)
        try await noop.signIn(); await noop.vault.configureErase(write: .noOp)
        let out = await noop.coordinator.signOut()
        let surviving = await noop.vault.actual.read()
        try require(out.localErase == .uncertain && out.durableFence == .uncertain && out.namespace == nil &&
            out.remoteRevoke == .pending && surviving.normal != nil, "noop-erase-not-verified")
        let stale = try AccountAuthTestRig(root: root, vault: noop.vault, recreated: true)
        let before = await stale.vault.counters()
        let staleState = await stale.coordinator.snapshot()
        let staleRefresh = await stale.coordinator.refresh()
        try require(staleState.phase == .freshAuthenticationRequired && staleState.namespace == nil &&
            staleState.remoteRevoke == .unknown && staleRefresh == .superseded, "failed-durable-fence-restart-refuses-authority")
        let after = await stale.vault.counters()
        try require(before.0 == after.0 && before.1 == after.1, "restart-no-implicit-store-restore")
        // Honest limit: the surviving old row cannot prove the previous process intended signout.
        try require(await stale.vault.actual.read().normal != nil, "stale-row-does-not-prove-erasure")
        // Even without a caller's recreated hint, explicit preparation must notice stale custody
        // WITHOUT adopting its account/refresh proof, before clearing that normal row.
        let fresh = try AccountAuthTestRig(root: root, vault: AccountAuthFaultVault(actual: noop.vault.actual))
        _ = try await fresh.begin()
        let prepared = await fresh.coordinator.snapshot()
        let preparedStore = await fresh.vault.actual.read()
        try require(prepared.namespace == nil && prepared.remoteRevoke == .unknown && prepared.localErase == .verified &&
            preparedStore.normal == nil, "stale-row-preparation-preserves-unknown-remote-obligation")
        let preparedOut = await fresh.coordinator.signOut()
        try require(preparedOut.remoteRevoke == .unknown && preparedOut.localErase == .verified, "stale-row-fresh-prepare-signout-not-remote-completion")
        _ = await fresh.coordinator.retryRemoteRevocation()
        try require(await count(fresh, .revoke) == 0, "unproven-stale-row-not-revoke-authority")
        let lost = try AccountAuthTestRig(root: root)
        try await lost.signIn(); await lost.vault.configureErase(write: .lostReply)
        try require(await lost.coordinator.signOut().localErase == .verified, "lost-erase-reply-readable-postcondition")
        for mode in [AccountAuthFaultVault.ReadMode.unreadable, .corrupt, .partialReceipt, .stale] {
            let rig = try AccountAuthTestRig(root: root)
            try await rig.signIn(); await rig.vault.configureErase(readback: mode)
            let out = await rig.coordinator.signOut()
            try require(out.localErase == .uncertain && out.durableFence == .uncertain && out.namespace == nil &&
                out.remoteRevoke == .pending, "unreadable-erase-not-completion")
            let restarted = try AccountAuthTestRig(root: root, vault: rig.vault, recreated: true)
            let state = await restarted.coordinator.snapshot()
            let refresh = await restarted.coordinator.refresh()
            try require(state.namespace == nil && refresh == .superseded, "unreadable-restart-no-resurrection")
        }
        let immediate = try AccountAuthTestRig(root: root), gate = AccountAuthTestGate()
        try await immediate.signIn(); await immediate.vault.pauseErase(gate)
        let task = Task { await immediate.coordinator.signOut() }
        await gate.waitUntilEntered()
        let fenced = await immediate.coordinator.snapshot()
        let fencedRefresh = await immediate.coordinator.refresh()
        try require(fenced.phase == .signedOut && fenced.namespace == nil && fenced.localErase == .uncertain &&
            fenced.remoteRevoke == .pending && fencedRefresh == .superseded, "signout-before-erase-immediate-fence")
        await gate.release()
        try require(await task.value.localErase == .verified, "signout-verified-after-actual-erase")
        let pending = try AccountAuthTestRig(root: root)
        let oldPlan = try await pending.begin()
        let recreated = try AccountAuthTestRig(root: root, vault: pending.vault, recreated: true)
        let lateCallback = await recreated.coordinator.consumeCallback(try pending.callback(plan: oldPlan))
        let lateCalls = await count(recreated, .exchange)
        try require(lateCallback == .superseded && lateCalls == 0, "process-loss-unsecured-attempt-invalidated")
        let corrupt = AccountAuthSyntheticVault(syntheticSeed: .init(integrity: .corrupt, durableGeneration: 4, normal: nil, receipt: nil))
        let bad = try AccountAuthTestRig(root: root, vault: AccountAuthFaultVault(actual: corrupt), recreated: true)
        try require(await bad.coordinator.snapshot().namespace == nil, "corrupt-restart-no-auto-restore")
        try await asyncDenies("corrupt-fresh-auth-refuses-unreadable-fence") { _ = try await bad.begin() }
    }
    private static func revokeCompartment(root: URL) async throws {
        let failures: [AccountAuthFaultTransport.Reply] = [.lost,
            .body(Data("{\"error\":\"verification_pending\"}".utf8), 503),
            .body(Data("{\"revoked\":false}".utf8), 200), .body(Data("{\"revoked\":1}".utf8), 200),
            .body(Data("{\"revoked\":true,\"message\":\"private\"}".utf8), 200),
            .wrongCorrelation(Data("{\"revoked\":true}".utf8)), .redirect(Data("{\"revoked\":true}".utf8)),
            .body(Data(), 204), .body(Data("{\"revoked\":true}".utf8), 201)]
        for reply in failures {
            let rig = try AccountAuthTestRig(root: root)
            try await rig.signIn()
            let normal = await rig.vault.actual.read().normal!
            let out = await rig.coordinator.signOut()
            let beforeRevoke = await count(rig, .revoke)
            try require(out.remoteRevoke == .pending && beforeRevoke == 0, "offline-signout-no-automatic-network")
            await rig.transport.enqueue(reply, operation: .revoke)
            let pending = await rig.coordinator.retryRemoteRevocation()
            try require(pending.remoteRevoke == .pending && pending.localErase == .verified && pending.namespace == nil,
                "unverified-revoke-remains-pending")
            let sent = await rig.transport.sent().last!
            let fields = try JSONSerialization.jsonObject(with: sent.wireBody()) as! [String: String]
            let erased = await rig.vault.actual.read()
            try require(sent.operation == .revoke && Set(fields.keys) == ["refresh_token", "client_id", "installation_id"] &&
                fields["refresh_token"] == normal.session.refresh.wireValue() && erased.normal == nil, "minimum-proof-only-in-revoke-request")
            let refresh = await rig.coordinator.refresh()
            let refreshCalls = await count(rig, .refresh)
            try require(refresh == .superseded && refreshCalls == 0, "revoke-proof-inaccessible-to-refresh")
            // There is no config/health transport or credential getter in the source API.
            try require(!pending.profileSyncEnabled, "revoke-proof-no-config-authority")
            await rig.transport.enqueue(.body(Data("{\"revoked\":true}".utf8), 200), operation: .revoke)
            try require(await rig.coordinator.retryRemoteRevocation().remoteRevoke == .confirmed, "correlated-exact-revoke-ack")
        }
        let late = try AccountAuthTestRig(root: root), gate = AccountAuthTestGate()
        try await late.signIn(); _ = await late.coordinator.signOut()
        await late.transport.enqueue(.body(Data("{\"revoked\":true}".utf8), 200), operation: .revoke)
        await late.transport.pauseNext(gate)
        let task = Task { await late.coordinator.retryRemoteRevocation() }
        await gate.waitUntilEntered(); _ = await late.coordinator.signOut(); await gate.release()
        try require(await task.value.remoteRevoke == .pending, "late-revoke-ack-not-current-generation")
    }
    private static func expiryUncertaintyAndInstallation(root: URL) async throws {
        for mode in 0..<4 {
            let rig = try AccountAuthTestRig(root: root)
            try await rig.signIn()
            if mode == 0 {
                rig.clock.configure(time: 400)
                try require(await rig.coordinator.snapshot().phase == .expired, "access-expiry-equality")
            } else if mode == 1 {
                rig.clock.configure(fails: true)
                try require(await rig.coordinator.snapshot().phase == .uncertain, "clock-uncertainty-hides-normal-authority")
            } else if mode == 2 {
                await rig.vault.configureRead(.unreadable)
                await rig.vault.configureErase(readback: .unreadable)
                try require(await rig.coordinator.refresh() == .uncertain, "custody-uncertainty-hides-normal-authority")
            } else {
                rig.clock.configure(time: 99)
                try require(await rig.coordinator.snapshot().phase == .uncertain, "clock-rollback-hides-normal-authority")
            }
            let out = await rig.coordinator.signOut()
            try require(out.namespace == nil && out.remoteRevoke == .pending, "expired-or-uncertain-family-survives-visibility-clear")
            rig.clock.configure(time: mode == 0 ? 401 : 100)
            await rig.transport.enqueue(.body(Data("{\"revoked\":true}".utf8), 200), operation: .revoke)
            let ack = await rig.coordinator.retryRemoteRevocation()
            try require(ack.remoteRevoke == .confirmed && (mode != 2 || ack.localErase == .uncertain),
                "remote-ack-independent-of-local-erasure")
        }
        let rig = try AccountAuthTestRig(root: root)
        try await rig.signIn()
        let firstPlan = await rig.transport.sent()[0]
        let first = try JSONSerialization.jsonObject(with: firstPlan.wireBody()) as! [String: String]
        _ = await rig.coordinator.signOut()
        let secondBody = try rig.replacement(rig.initial, fields: [
            "session_id": String(repeating: "F", count: 42) + "A",
            "access_token": "hmd_nac_" + String(repeating: "D", count: 42) + "A",
            "refresh_token": "hmd_nrf_" + String(repeating: "U", count: 42) + "A"])
        await rig.transport.enqueue(.body(secondBody, 200), operation: .exchange)
        let plan = try await rig.begin()
        var raw = String(data: try rig.callback(plan: plan), encoding: .utf8)!
        raw = raw.replacingOccurrences(of: "hmd_acode_" + String(repeating: "A", count: 43),
            with: "hmd_acode_" + String(repeating: "B", count: 42) + "A")
        try require(await rig.coordinator.consumeCallback(Data(raw.utf8)) == .installed, "explicit-inprocess-reauth")
        let secondPlan = await rig.transport.sent().last!
        let second = try JSONSerialization.jsonObject(with: secondPlan.wireBody()) as! [String: String]
        try require(first["installation_id"] == second["installation_id"] && first["code_verifier"] != second["code_verifier"] &&
            rig.entropy.calls == 5, "installation-stable-attempt-verifier-fresh")
        let queries = URLComponents(string: plan.syntheticReviewURL())!.queryItems!
        try require(!queries.contains(where: { ["installation_id", "account_id", "session_id"].contains($0.name) }),
            "installation-not-url-authority")
        _ = await rig.coordinator.signOut()
        for expected in [AccountAuthRemoteRevoke.pending, .confirmed] {
            await rig.transport.enqueue(.body(Data("{\"revoked\":true}".utf8), 200), operation: .revoke)
            try require(await rig.coordinator.retryRemoteRevocation().remoteRevoke == expected, "reauth-preserves-both-revoke-obligations")
        }
    }
    private static func exhaustionAndIndependentState(root: URL) async throws {
        let rig = try AccountAuthTestRig(root: root, localGeneration: UInt64.max)
        try await asyncDenies("local-generation-exhaustion") { _ = try await rig.begin() }
        let state = await rig.coordinator.snapshot()
        let calls = await count(rig, .exchange)
        try require(state.phase == .exhausted && rig.entropy.calls == 0 && calls == 0, "exhaustion-no-wrap-no-issuance")
        let out = await rig.coordinator.signOut()
        try require(out.phase == .exhausted && out.namespace == nil && out.localErase != .verified, "exhaustion-signout-not-fictitious-erase")
        let corpus = try AccountAuthTestCheck.corpus(root: root), rows = corpus["response_cases"] as! [[String: Any]]
        let max = rows.first { $0["id"] as? String == "generation-safe-max" }!
        let captured = try AccountAuthTestCheck.capture(max["context"] as! [String: String])
        let session = try AccountAuthWire.decodeSession(AccountAuthTestCheck.bytes(max), captured: captured)
        try AccountAuthTestCheck.denies("server-generation-overflow") { try AccountAuthWire.validateRefresh(session, previous: session) }
        let local = ["profile": "offline-local", "active": "local-selection", "destination": "local-binding",
            "schedule": "unchanged-enabled", "job": "frozen-engine-pin", "provider": "independent", "purchase": "independent",
            "health-permission": "unchanged", "foreign-extension": "preserved", "configuration-protection": "unchanged"]
        let before = local
        let normal = try AccountAuthTestRig(root: root)
        try await normal.signIn(); _ = await normal.coordinator.switchAccount()
        let stateAfter = await normal.coordinator.snapshot()
        try require(local == before && !stateAfter.profileSyncEnabled, "independent-local-offline-sentinel-preserved")
        // This library has no reference/port/import for that state. This is NOT a whole-app foreground assertion.
    }

    static func run(root: URL) async throws -> String {
        var covered: Set<String> = []
        try await defaultZero(root: root); covered.insert("default_unavailable_zero_ports")
        try await priorMissingRecord(root: root)
        try await pendingAndCancel(root: root); covered.formUnion(["one_pending_attempt", "cancel_then_late_callback"])
        try await callbackReplayAndSwitch(root: root); covered.formUnion(["callback_replay", "switch_then_late_exchange"])
        try await installFaults(root: root); covered.formUnion(["commit_noop", "commit_lost_reply_verified_readback", "commit_unreadable_uncertain"])
        try await installRaces(root: root); covered.insert("signout_before_secure_commit")
        try await initialZero(root: root); covered.insert("initial_generation_zero")
        try await serializedRefresh(root: root); covered.formUnion(["serialized_refresh_one_consumption", "refresh_preserves_account_client_install_family"])
        try await refreshFaults(root: root); covered.formUnion(["refresh_wrong_owner_quarantine", "refresh_lost_reply_no_parent_replay"])
        try await refreshSignoutRaces(root: root); covered.insert("signout_immediate_local_fence")
        try await signoutFaultsAndRestart(root: root); covered.formUnion(["signout_clear_noop_not_verified", "restart_stale_or_corrupt_no_resurrection", "process_loss_invalidates_unsecured_attempt"])
        try await revokeCompartment(root: root); covered.formUnion(["offline_remote_revocation_pending", "revocation_proof_not_refresh_or_config"])
        try await expiryUncertaintyAndInstallation(root: root)
        try await exhaustionAndIndependentState(root: root); covered.formUnion(["generation_exhaustion_fail_closed", "no_health_or_profile_or_destination_or_schedule_or_purchase_effects"])
        let required = try AccountAuthTestCheck.corpus(root: root)["lifecycle_required"] as! [String]
        try require(Set(required) == covered && covered.count == 22, "all-required-actual-lifecycle-seams")
        return "lifecycle-required=22 covered=22 default-admission-cases=4 install-read-faults=7 refresh-binding-faults=12 refresh-load-faults=6 revoke-negative=9 actor-races=14 clock-expiry-custody=4 installation-stability=1 prior-custody-scenarios=4"
    }
}
#if !ACCOUNT_AUTH_SOURCE_HOST
final class AccountAuthLifecycleTests: XCTestCase {
    func testActualSyntheticCoordinatorFaultsAndRaces() async throws {
        _ = try await AccountAuthLifecycleChecks.run(root: AccountAuthTestCheck.root())
    }
}
#endif
