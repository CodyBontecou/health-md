package com.healthmd.accountauth

import kotlinx.serialization.json.JsonPrimitive
import org.junit.Test

/** Static hold follow-up: these executable source scenarios are UNEXECUTED until guarded admission. */
class AccountAuthTimingTest {
    private class Scenario(val refresh: Boolean, channel: AndroidAuthChannel) {
        val rig = AuthRig(channel)
        private val callback = if (refresh) { rig.signIn(); null } else rig.begin()
        val original = rig.vault.inspect()
        fun act(): AuthAction = if (refresh) rig.owner.refresh() else rig.owner.acceptCallback(callback!!)
        fun noNewRow() {
            val after = rig.vault.inspect()
            checkSource(if (original == null) after == null else after != null && original.same(after), "no temporal candidate written")
        }
        fun quarantined() {
            val status = rig.owner.status()
            checkSource(status.phase == AccountPhase.AUTHENTICATION_UNCERTAIN && status.namespace == null &&
                !status.accountOperationsAllowed && status.remoteRevocation == RemoteRevocation.PENDING, "temporal uncertainty fences account operations")
            val requests = rig.transport.count()
            checkSource(rig.owner.refresh() == AuthAction.REJECTED && rig.transport.count() == requests, "temporal uncertainty cannot replay consumed proof")
        }
    }
    private data class TimingCase(val ttl: Long, val receipt: Long, val later: Long)
    private fun response(rig: AuthRig, request: AuthRequestPlan, ttl: Long): SyntheticReply {
        checkSource(request.window.startedAtSeconds == 100L && request.window.deadlineAtSeconds == 105L &&
            request.window.timeoutSeconds == 5L, "captured closed request window")
        val issued = rig.transport.normalReply(request)
        return SyntheticReply(request, request.url, 200, patched(issued.bytes(), mapOf("expires_in" to JsonPrimitive(ttl))))
    }

    @Test fun closedFiniteWindowAndStartBoundedTtlRejectUnsafeStartAndExhaustion() {
        val window = AuthRequestWindow.capture(100)
        checkSource(window.timeoutSeconds == 5L && window.deadlineAtSeconds == 105L &&
            window.leaseBound(1, 100) == 101L && window.leaseBound(300, 102) == 400L, "lease starts at request, not arrival")
        rejection("TTL1 exhausted at equality") { window.leaseBound(1, 101) }
        rejection("request deadline equality") { window.leaseBound(300, 105) }
        rejection("clock below request start") { window.requireCurrent(99) }
        for (ttl in listOf(0L, 301L, Long.MAX_VALUE)) rejection("closed TTL") { window.leaseBound(ttl, 100) }
        for (start in listOf(-1L, Long.MAX_VALUE, AccountAuthWire.MAX_SERVER_GENERATION - 299)) rejection("safe bounded start") {
            AuthRequestWindow.capture(start)
        }
        val maximum = AuthRequestWindow.capture(AccountAuthWire.MAX_SERVER_GENERATION - 300)
        checkSource(maximum.leaseBound(300, maximum.startedAtSeconds) == AccountAuthWire.MAX_SERVER_GENERATION, "no lease overflow")
    }

    @Test fun actualDelayedResponseTtlDeadlineAndStartRollbackRejectExchangeAndRefresh() {
        val cases = listOf(TimingCase(1, 100, 101), TimingCase(300, 100, 105), TimingCase(300, 100, 400), TimingCase(300, 100, 99))
        for (channel in AndroidAuthChannel.entries) for (refresh in listOf(false, true)) for (case in cases) {
            val scenario = Scenario(refresh, channel)
            val rig = scenario.rig
            val point = DeferredPoint()
            rig.transport.handler = { request -> val issued = response(rig, request, case.ttl); point.pause(); issued }
            val operation = RunningAction { scenario.act() }
            try { point.awaitReached(); rig.clock.value.set(case.later) } finally { point.release() }
            checkSource(operation.finish() == AuthAction.UNCERTAIN, "actual late/rollback response rejected")
            scenario.noNewRow(); scenario.quarantined()
        }
        println("TEMPORAL delayed-response-source-cases=16 both-Android-channels exchange/refresh TTL1/300/deadline/rollback")
    }

    @Test fun actualPositiveDelayedReplyNeverRebasesLeaseAndInstalledLeaseOutlivesRequestWindow() {
        for (channel in AndroidAuthChannel.entries) for (refresh in listOf(false, true)) {
            val scenario = Scenario(refresh, channel)
            val rig = scenario.rig
            rig.transport.handler = { request -> val issued = response(rig, request, 300); rig.clock.value.set(102); issued }
            checkSource(scenario.act() == if (refresh) AuthAction.REFRESHED else AuthAction.INSTALLED, "actual delayed response within window")
            val record = rig.vault.inspect()!!.normal!!
            checkSource(record.requestStartedAtSeconds == 100L && record.expiresAt == 400L, "private vault lease is start+TTL not 402")
            rig.clock.value.set(106)
            checkSource(rig.owner.status().phase == AccountPhase.SIGNED_IN, "completed request deadline not normal access expiry")
            rig.clock.value.set(400)
            checkSource(rig.owner.status().phase == AccountPhase.EXPIRED && rig.owner.status().remoteRevocation == RemoteRevocation.PENDING,
                "conservative access expiry equality preserves remote uncertainty")
        }
        for (channel in AndroidAuthChannel.entries) for (refresh in listOf(false, true)) {
            val scenario = Scenario(refresh, channel)
            scenario.rig.transport.handler = { request -> response(scenario.rig, request, 1) }
            checkSource(scenario.act() == if (refresh) AuthAction.REFRESHED else AuthAction.INSTALLED, "actual fresh TTL1")
            checkSource(scenario.rig.vault.inspect()!!.normal!!.expiresAt == 101L, "TTL1 exact conservative bound")
            scenario.rig.clock.value.set(101)
            checkSource(scenario.rig.owner.status().phase == AccountPhase.EXPIRED, "TTL1 normal authority expires at equality")
        }
    }

    @Test fun actualDeferredAuthoritativeCommitRejectsTtlDeadlineAndRelativeRollback() {
        val cases = listOf(TimingCase(1, 100, 101), TimingCase(300, 100, 105), TimingCase(300, 100, 99), TimingCase(300, 102, 101))
        for (channel in AndroidAuthChannel.entries) for (refresh in listOf(false, true)) for (case in cases) {
            val scenario = Scenario(refresh, channel)
            val rig = scenario.rig
            val point = DeferredPoint()
            rig.transport.handler = { request -> val issued = response(rig, request, case.ttl); rig.clock.value.set(case.receipt); issued }
            rig.vault.beforeCommit.set { point.pause() }
            val operation = RunningAction { scenario.act() }
            try { point.awaitReached(); rig.clock.value.set(case.later) } finally { point.release() }
            checkSource(operation.finish() == AuthAction.UNCERTAIN, "actual authoritative temporal gate rejects")
            scenario.noNewRow(); scenario.quarantined()
        }
        println("TEMPORAL deferred-authoritative-commit-source-cases=16 both-Android-channels includes-rollback-above-request-start")
    }

    @Test fun actualCommittedRowDeferredReadbackCannotInstallAfterTtlDeadlineOrClockRollback() {
        val cases = listOf(TimingCase(1, 100, 101), TimingCase(300, 100, 105), TimingCase(300, 100, 99), TimingCase(300, 102, 102))
        for (channel in AndroidAuthChannel.entries) for (refresh in listOf(false, true)) for (case in cases) {
            val scenario = Scenario(refresh, channel)
            val rig = scenario.rig
            val point = DeferredPoint()
            rig.transport.handler = { request -> val issued = response(rig, request, case.ttl); rig.clock.value.set(case.receipt); issued }
            if (case.receipt == 102L) rig.vault.beforeCommit.set { rig.clock.value.set(103) }
            if (case.ttl == 1L) rig.vault.fault = VaultFault.LOST_REPLY // actual TTL1 write + lost commit reply, still no lease extension
            rig.vault.afterCommit.set { rig.vault.beforeRead.set { point.pause() } }
            val operation = RunningAction { scenario.act() }
            try {
                point.awaitReached() // actual fresh readback is deferred AFTER actual candidate installation
                val committed = rig.vault.inspect()!!.normal!!
                checkSource(committed.requestStartedAtSeconds == 100L && committed.expiresAt == 100L + case.ttl &&
                    committed.session?.sessionGeneration == if (refresh) 1L else 0L, "actual candidate committed with conservative lease")
                rig.clock.value.set(case.later)
            } finally { point.release() }
            checkSource(operation.finish() == AuthAction.UNCERTAIN, "actual temporal visibility fence rejects")
            scenario.quarantined()
            val recreated = AccountAuthCoordinator.forSyntheticTests(channel, rig.ports)
            checkSource(recreated.restore() == AuthAction.UNAVAILABLE && recreated.begin(TEST_SCOPE) == AuthAction.UNCERTAIN,
                "temporally unverified populated row is not restoration authority")
        }
        println("TEMPORAL committed-row/deferred-readback-source-cases=16 both-Android-channels no visible lease resurrection")
    }

    @Test fun refreshRequestWindowIncludesActualDeferredVaultLoadBeforeDispatch() {
        for (channel in AndroidAuthChannel.entries) for (later in listOf(105L, 99L)) {
            val rig = AuthRig(channel); rig.signIn()
            val point = DeferredPoint()
            rig.vault.beforeRead.set { point.pause() }
            val refresh = RunningAction { rig.owner.refresh() }
            try { point.awaitReached(); rig.clock.value.set(later) } finally { point.release() }
            checkSource(refresh.finish() == AuthAction.UNCERTAIN && rig.transport.count(AuthRequestKind.REFRESH) == 0 &&
                rig.owner.status().namespace == null, "actual load interval deadline/rollback before dispatch")
        }
    }

    @Test fun actualRevokeReceiptAndAckCommitRejectLateProofDeadlineAndRelativeRollback() {
        val cases = listOf(TimingCase(1, 101, 101), TimingCase(300, 105, 105), TimingCase(300, 99, 99),
            TimingCase(1, 100, 101), TimingCase(300, 100, 105), TimingCase(300, 102, 101))
        for (channel in AndroidAuthChannel.entries) for (case in cases) {
            val rig = AuthRig(channel)
            val callback = rig.begin()
            rig.transport.handler = { request -> response(rig, request, case.ttl) }
            checkSource(rig.owner.acceptCallback(callback) == AuthAction.INSTALLED && rig.owner.signOut() == AuthAction.FENCED,
                "actual prior session/proof for revoke timing")
            rig.transport.handler = { request ->
                checkSource(request.kind == AuthRequestKind.REVOKE && request.window.startedAtSeconds == 100L &&
                    request.window.deadlineAtSeconds == 105L, "actual revoke window")
                rig.clock.script(case.receipt, case.later)
                rig.transport.normalReply(request)
            }
            checkSource(rig.owner.revokeRemote() == AuthAction.UNCERTAIN && rig.owner.status().remoteRevocation == RemoteRevocation.PENDING &&
                rig.owner.status().localErasure == LocalErasure.VERIFIED && rig.transport.count(AuthRequestKind.REVOKE) == 1,
                "late/rollback revoke cannot acknowledge or rebase proof expiry")
        }
        println("TEMPORAL revoke-receipt/ack-source-cases=12 both-Android-channels TTL1/deadline/start-and-relative-rollback")
    }

    @Test fun clockRollbackAfterInstalledAuthorityQuarantinesButLocalSignoutStillFences() {
        for (channel in AndroidAuthChannel.entries) {
            val rig = AuthRig(channel); rig.signIn(); rig.clock.value.set(99)
            checkSource(rig.owner.status().phase == AccountPhase.AUTHENTICATION_UNCERTAIN && rig.owner.status().namespace == null &&
                rig.owner.status().remoteRevocation == RemoteRevocation.PENDING, "process-local clock rollback cannot prolong normal authority")
            checkSource(rig.owner.signOut() == AuthAction.FENCED && rig.owner.status().localErasure == LocalErasure.VERIFIED &&
                rig.owner.status().remoteRevocation == RemoteRevocation.PENDING, "local erasure remains distinct from timed remote acknowledgement")
        }
    }
}
