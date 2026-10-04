import Foundation
#if !ACCOUNT_AUTH_SOURCE_HOST
import XCTest
@testable import HealthMd
#endif

nonisolated enum AccountAuthTemporalChecks {
    private static func runAttempt(rig: AccountAuthTestRig, refreshing: Bool, body: Data,
                                   stage: Int, gate: AccountAuthTestGate) async throws -> Task<AccountAuthOutcome, Never> {
        if stage == 0 { await rig.transport.pauseNext(gate) }
        if stage == 1 { await rig.vault.pauseInstall(gate) }
        if stage == 2 { await rig.vault.pauseReadAfterInstall(gate) }
        await rig.transport.enqueue(.body(body, 200), operation: refreshing ? .refresh : .exchange)
        if refreshing { return Task { await rig.coordinator.refresh() } }
        let plan = try await rig.begin(), raw = try rig.callback(plan: plan)
        return Task { await rig.coordinator.consumeCallback(raw) }
    }
    static func run(root: URL) async throws -> String {
        var negatives = 0
        for refreshing in [false, true] {
            // Initial exchange and refresh both capture the literal request-start clock=100.
            for stage in 0..<3 {
                for time in [UInt64(101), 102, 104, 99, 105] {
                    let rig = try AccountAuthTestRig(root: root), gate = AccountAuthTestGate()
                    if refreshing { try await rig.signIn() }
                    let body = try rig.replacement(refreshing ? rig.refreshed : rig.initial, fields: ["expires_in": 1])
                    let task = try await runAttempt(rig: rig, refreshing: refreshing, body: body, stage: stage, gate: gate)
                    await gate.waitUntilEntered()
                    rig.clock.configure(time: time)
                    await gate.release()
                    let result = await task.value
                    let state = await rig.coordinator.snapshot()
                    let stored = await rig.vault.actual.read()
                    try AccountAuthTestCheck.require(result == .uncertain && state.namespace == nil && state.phase == .uncertain,
                        "ttl-one-delay-expiry-or-rollback-rejected")
                    if stage == 2 {
                        try AccountAuthTestCheck.require(stored.normal?.session.expiresIn == 1 && state.localErase == .uncertain &&
                            state.durableFence == .uncertain, "expired-or-rollback-readback-with-real-custody-commit")
                    } else {
                        try AccountAuthTestCheck.require(refreshing ? stored.normal?.session.serverGeneration == 0 : stored.normal == nil,
                            "temporal-response-or-authoritative-write-rejected")
                    }
                    rig.clock.configure()
                    let out = await rig.coordinator.signOut()
                    try AccountAuthTestCheck.require(out.namespace == nil && out.localErase == .verified && out.remoteRevoke == .pending,
                        "expired-access-still-has-own-revoke-obligation")
                    negatives += 1
                }
                // Isolate the five-second dispatch/commit deadline from the longer access TTL.
                let rig = try AccountAuthTestRig(root: root), gate = AccountAuthTestGate()
                if refreshing { try await rig.signIn() }
                let body = refreshing ? rig.refreshed : rig.initial // TTL300; the deadline alone expires at105.
                let task = try await runAttempt(rig: rig, refreshing: refreshing, body: body, stage: stage, gate: gate)
                await gate.waitUntilEntered(); rig.clock.configure(time: 105); await gate.release()
                let result = await task.value
                let state = await rig.coordinator.snapshot()
                try AccountAuthTestCheck.require(result == .uncertain && state.namespace == nil, "dispatch-deadline-equality-rejected")
                negatives += 1
            }
            // A rollback from an already observed104 to103 must deny, even though103 is
            // still above request-start100, within timeout105 and within the TTL300 lease.
            for stage in 1...3 {
                let rig = try AccountAuthTestRig(root: root)
                if refreshing { try await rig.signIn() }
                let replyGate = AccountAuthTestGate(), nextGate = AccountAuthTestGate()
                if stage == 1 { await rig.vault.pauseInstall(nextGate) }
                else { await rig.vault.pauseReadAfterInstall(nextGate) }
                let task = try await runAttempt(rig: rig, refreshing: refreshing,
                    body: refreshing ? rig.refreshed : rig.initial, stage: 0, gate: replyGate)
                await replyGate.waitUntilEntered(); rig.clock.configure(time: 104); await replyGate.release()
                await nextGate.waitUntilEntered()
                if stage == 3 { rig.clock.configureSequence([104, 103]) }
                else { rig.clock.configure(time: 103) }
                await nextGate.release()
                let result = await task.value
                let state = await rig.coordinator.snapshot()
                let stored = await rig.vault.actual.read()
                try AccountAuthTestCheck.require(result == .uncertain && state.namespace == nil, "observed-clock-rollback-between-seams")
                if stage == 1 {
                    try AccountAuthTestCheck.require(refreshing ? stored.normal?.session.serverGeneration == 0 : stored.normal == nil,
                        "observed-clock-rollback-rejects-real-commit")
                } else {
                    try AccountAuthTestCheck.require(stored.normal?.leaseStart == 100, "observed-clock-rollback-after-real-commit")
                }
                negatives += 1
            }
            // Clock can change again after valid readback and before the final visibility check.
            let visible = try AccountAuthTestRig(root: root), gate = AccountAuthTestGate()
            if refreshing { try await visible.signIn() }
            let body = try visible.replacement(refreshing ? visible.refreshed : visible.initial, fields: ["expires_in": 1])
            let task = try await runAttempt(rig: visible, refreshing: refreshing, body: body, stage: 2, gate: gate)
            await gate.waitUntilEntered(); visible.clock.configureSequence([100, 101]); await gate.release()
            let result = await task.value
            let state = await visible.coordinator.snapshot()
            let stored = await visible.vault.actual.read()
            try AccountAuthTestCheck.require(result == .uncertain && state.namespace == nil && stored.normal != nil &&
                state.localErase == .uncertain, "ttl-expires-between-readback-and-visibility")
            negatives += 1

            // A still-valid delayed TTL300 reply can install, but its held lease is NOT rebased to104.
            let positive = try AccountAuthTestRig(root: root), positiveGate = AccountAuthTestGate()
            if refreshing { try await positive.signIn() }
            let positiveTask = try await runAttempt(rig: positive, refreshing: refreshing,
                body: refreshing ? positive.refreshed : positive.initial, stage: 0, gate: positiveGate)
            await positiveGate.waitUntilEntered(); positive.clock.configure(time: 104); await positiveGate.release()
            try AccountAuthTestCheck.require(await positiveTask.value == .installed, "delayed-still-valid-conservative-lease")
            let held = await positive.vault.actual.read().normal!
            try AccountAuthTestCheck.require(held.leaseStart == 100 && held.session.expiresIn == 300, "lease-bound-is-request-start-not-response")
            positive.clock.configure(time: 399)
            try AccountAuthTestCheck.require(await positive.coordinator.snapshot().phase == .signedIn, "conservative-lease-before-expiry")
            positive.clock.configure(time: 400)
            try AccountAuthTestCheck.require(await positive.coordinator.snapshot().phase == .expired, "no-transport-delay-lease-extension")
        }
        try AccountAuthTestCheck.require(negatives == 44, "temporal-scenario-count")
        return "temporal-negative=44 temporal-positive=2 request-start-lease=exchange-and-refresh"
    }
}
#if !ACCOUNT_AUTH_SOURCE_HOST
final class AccountAuthTemporalTests: XCTestCase {
    func testConservativeLeaseAtResponseCommitReadbackAndVisibility() async throws {
        _ = try await AccountAuthTemporalChecks.run(root: AccountAuthTestCheck.root())
    }
}
#endif
