package com.healthmd.myselfclaim

import com.healthmd.export.MainDispatcherRule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MyselfClaimViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun openingDoesNothingAndOnlyExplicitVerificationOpensTheBrowser() = runTest(main.testDispatcher) {
        var reads = 0
        var verifications = 0
        val opened = mutableListOf<String>()
        val model = MyselfClaimViewModel(MyselfClaimPurchaseSource { reads++; "proof" },
            MyselfClaimVerifier { assertEquals("proof", it); verifications++; "https://myself.md/claim#ticket" })
        runCurrent()
        assertEquals(0, reads)
        assertEquals(0, verifications)
        assertFalse(model.state.value.awaitingUser)
        model.verify { opened.add(it) }
        runCurrent()
        assertEquals(1, reads)
        assertEquals(1, verifications)
        assertEquals(1, opened.size)
        assertTrue(model.state.value.awaitingUser)
        assertFalse(model.state.value.busy)
    }

    @Test fun missingOrPendingPurchaseNeverReachesServerAndRetryReadsFreshEvidence() = runTest(main.testDispatcher) {
        var eligible = false
        var verifications = 0
        val model = MyselfClaimViewModel(MyselfClaimPurchaseSource {
            if (!eligible) throw MyselfClaimException(MyselfClaimFailure.NO_PURCHASE)
            "fresh"
        }, MyselfClaimVerifier { verifications++; "claim" })
        model.verify { fail("No browser for an ineligible purchase") }
        runCurrent()
        assertEquals(MyselfClaimFailure.NO_PURCHASE, model.state.value.failure)
        assertEquals(0, verifications)
        eligible = true
        model.verify { }
        runCurrent()
        assertEquals(1, verifications)
        assertTrue(model.state.value.awaitingUser)
    }

    @Test fun duplicateTapsAreCoalescedAndCancelNeverOpensBrowser() = runTest(main.testDispatcher) {
        val gate = CompletableDeferred<String>()
        var reads = 0
        val model = MyselfClaimViewModel(MyselfClaimPurchaseSource { reads++; gate.await() },
            MyselfClaimVerifier { fail("Cancelled evidence must not be submitted"); "" })
        model.verify { fail("No browser after cancellation") }
        runCurrent()
        model.verify { fail("No duplicate") }
        assertEquals(1, reads)
        assertTrue(model.state.value.busy)
        model.cancel()
        gate.complete("late proof")
        runCurrent()
        assertEquals(MyselfClaimState(), model.state.value)
    }

    @Test fun serverDenialAndNetworkOutageRemainRetryableWithoutClaimedState() = runTest(main.testDispatcher) {
        var failVerification = true
        val model = MyselfClaimViewModel(MyselfClaimPurchaseSource { "proof" },
            MyselfClaimVerifier { if (failVerification) throw java.io.IOException("Do not display proof") else "claim" })
        model.verify { fail("No browser on server failure") }
        runCurrent()
        assertEquals(MyselfClaimFailure.VERIFICATION_FAILED, model.state.value.failure)
        assertFalse(model.state.value.awaitingUser)
        failVerification = false
        model.verify { }
        runCurrent()
        assertTrue(model.state.value.awaitingUser)
    }

    @Test fun missingBrowserNeverReportsSuccessfulHandoff() = runTest(main.testDispatcher) {
        val model = MyselfClaimViewModel(MyselfClaimPurchaseSource { "proof" }, MyselfClaimVerifier { "claim" })
        model.verify { throw IllegalStateException("no browser") }
        runCurrent()
        assertEquals(MyselfClaimFailure.BROWSER_UNAVAILABLE, model.state.value.failure)
        assertFalse(model.state.value.awaitingUser)
    }

    @Test fun exactDeepLinkIsPlayOnlyAndCannotCarryEvidenceOrCredentials() {
        assertTrue(MyselfClaimLinks.accepts("android.intent.action.VIEW", MyselfClaimLinks.URL, true))
        assertFalse(MyselfClaimLinks.accepts("android.intent.action.VIEW", MyselfClaimLinks.URL, false))
        assertFalse(MyselfClaimLinks.accepts("android.intent.action.SEND", MyselfClaimLinks.URL, true))
        for (url in listOf("healthmd://user@myself/claim", "healthmd://myself:80/claim",
            "healthmd://myself/claim?proof=token", "healthmd://myself/claim#token",
            "healthmd://myself/claim/", "https://myself.md/claim", "healthmd://other/claim")) {
            assertFalse(url, MyselfClaimLinks.accepts("android.intent.action.VIEW", url, true))
        }
    }
}
