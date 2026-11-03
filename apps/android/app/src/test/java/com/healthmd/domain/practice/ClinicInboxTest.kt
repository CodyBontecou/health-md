package com.healthmd.domain.practice

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class ClinicInboxTest {
    private val now = 1_000_000_000L
    @Test fun consentAndExactDigestAreRequired() = runBlocking {
        val transport = SyntheticClinicInboxTransport(now)
        val controller = ClinicInboxController(transport, { true }, { now })
        controller.load(); assertEquals(0, transport.exports)
        controller.openReview("setup_synthetic")
        assertFalse(controller.canApply); assertFalse(controller.apply())
        controller.setConsent(true); assertTrue(controller.apply())
        assertTrue(transport.value.reviews.isEmpty()); assertFalse(controller.state.value.consent)
    }
    @Test fun uploadedAndProcessedRemainDistinctAndReceiptRetryNeverExports() = runBlocking {
        val transport = SyntheticClinicInboxTransport(now)
        val controller = ClinicInboxController(transport, { true }, { now })
        controller.load(); controller.export("refresh_synthetic")
        controller.export("refresh_synthetic"); controller.reportReceipt("refresh_synthetic")
        assertEquals(1, transport.exports); assertEquals(1, transport.receiptsReported)
        assertEquals(ClinicInboxStatus.UPLOADED, controller.state.value.snapshot.refreshes.single().status)
        assertFalse(controller.state.value.snapshot.refreshes.single().receiptPending)
        controller.revoke("connection_synthetic")
        assertEquals(ClinicInboxStatus.UPLOADED, controller.state.value.snapshot.refreshes.single().status)
        assertFalse(controller.state.value.snapshot.refreshes.single().sharingActive)
    }
    @Test fun expiryAndAccountChangesBlockApplication() = runBlocking {
        val transport = SyntheticClinicInboxTransport(now); var clock = now
        val controller = ClinicInboxController(transport, { true }, { clock })
        controller.load(); controller.openReview("setup_synthetic"); controller.setConsent(true)
        clock += 900_001; assertFalse(controller.canApply); assertFalse(controller.apply())
        clock = now; transport.sessionId = null
        assertFalse(controller.apply())
        assertTrue(controller.state.value.snapshot.refreshes.isEmpty()); assertEquals(0, transport.exports)
    }
    @Test fun defaultGateNeverLoadsOrExports() = runBlocking {
        val transport = SyntheticClinicInboxTransport(now)
        val controller = ClinicInboxController(transport)
        controller.load(); assertTrue(controller.state.value.unavailable)
        assertTrue(controller.state.value.snapshot.reviews.isEmpty()); assertEquals(0, transport.exports)
    }
    @Test fun cancellationAndRevocationAreExplicit() = runBlocking {
        val transport = SyntheticClinicInboxTransport(now)
        val controller = ClinicInboxController(transport, { true }, { now })
        controller.load(); controller.cancel("refresh_synthetic")
        assertEquals(ClinicInboxStatus.CANCELLED, controller.state.value.snapshot.refreshes.single().status)
        controller.revoke("connection_synthetic")
        assertEquals(ClinicInboxStatus.CANCELLED, controller.state.value.snapshot.refreshes.single().status)
        assertFalse(controller.state.value.snapshot.refreshes.single().sharingActive)
        assertEquals(0, transport.exports)
    }
    @Test fun staleLoadDoesNotOverwriteNewerAccountState() = runBlocking {
        val waiting = CompletableDeferred<ClinicInboxSnapshot>()
        val fixture = SyntheticClinicInboxTransport(now)
        var first = true
        val transport = object : ClinicInboxTransport by fixture {
            override suspend fun load(): ClinicInboxSnapshot {
                if (first) { first = false; return waiting.await() }
                return ClinicInboxSnapshot(refreshes = fixture.value.refreshes)
            }
        }
        val controller = ClinicInboxController(transport, { true }, { now })
        val old = async { controller.load() }
        kotlinx.coroutines.yield()
        controller.clear(); controller.load()
        waiting.complete(fixture.value); old.await()
        assertTrue(controller.state.value.snapshot.reviews.isEmpty())
        assertEquals(1, controller.state.value.snapshot.refreshes.size)
        assertFalse(controller.state.value.loading)
    }
    @Test fun uncertainActionCannotBeBlindlyRepeatedBeforeReload() = runBlocking {
        val fixture = SyntheticClinicInboxTransport(now)
        var offline = false
        val transport = object : ClinicInboxTransport by fixture {
            override suspend fun export(id: String) { fixture.export(id); offline = true }
            override suspend fun load(): ClinicInboxSnapshot { if (offline) error("offline"); return fixture.load() }
        }
        val controller = ClinicInboxController(transport, { true }, { now })
        controller.load(); controller.export("refresh_synthetic"); controller.export("refresh_synthetic")
        assertEquals(1, fixture.exports); assertTrue(controller.state.value.error)
    }
    @Test fun cancelAndRevokeRemainAvailableDuringSuspendedExport() = runBlocking {
        for ((revoke, outcome) in listOf(false to 0, true to 0, false to 1, true to 1, false to 2, true to 2)) {
            val fixture = SyntheticClinicInboxTransport(now); val release = CompletableDeferred<Unit>()
            var stopped = false; var publications = 0; var attempts = 0
            val transport = object : ClinicInboxTransport by fixture {
                // Intentionally stale reads must not undo confirmed local controls.
                override suspend fun export(id: String) {
                    attempts++; release.await()
                    if (stopped) {
                        if (outcome == 0) error("revoked")
                        if (outcome == 1) throw kotlinx.coroutines.CancellationException("revoked")
                        return
                    }
                    publications++
                }
                override suspend fun cancel(id: String) { stopped = true }
                override suspend fun revoke(connectionId: String) { stopped = true }
            }
            val controller = ClinicInboxController(transport, { true }, { now })
            controller.load()
            val operation = async(start = CoroutineStart.UNDISPATCHED) { controller.export("refresh_synthetic") }
            assertTrue(controller.state.value.busy)
            if (revoke) controller.revoke("connection_synthetic") else controller.cancel("refresh_synthetic")
            val expected = if (revoke) ClinicInboxStatus.REVOKED else ClinicInboxStatus.CANCELLED
            assertTrue(stopped); assertEquals(expected, controller.state.value.snapshot.refreshes.single().status)
            release.complete(Unit); operation.await()
            assertEquals(0, publications); assertEquals(expected, controller.state.value.snapshot.refreshes.single().status)
            if (revoke) assertFalse(controller.state.value.snapshot.refreshes.single().sharingActive)
            assertFalse(controller.state.value.busy); assertFalse(controller.state.value.error)
            controller.load() // stale same-session reload must also retain confirmed controls
            controller.export("refresh_synthetic"); assertEquals(1, attempts)
        }
    }

    @Test fun accountChangeDuringControlClearsOldSnapshot() = runBlocking {
        val fixture = SyntheticClinicInboxTransport(now)
        val transport = object : ClinicInboxTransport by fixture {
            override suspend fun revoke(connectionId: String) { fixture.sessionId = null }
        }
        val controller = ClinicInboxController(transport, { true }, { now })
        controller.load(); controller.revoke("connection_synthetic")
        assertTrue(controller.state.value.snapshot.refreshes.isEmpty()); assertTrue(controller.state.value.controls.isEmpty())
    }

}
