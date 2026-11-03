package com.healthmd.domain.practice

import kotlinx.coroutines.CompletableDeferred
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
}
