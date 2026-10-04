package com.healthmd.accountauth

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.serialization.json.*
import org.junit.Test

/** These tests execute the source owner, requests, lock, CAS/gate, and verified readback, not phase predicates. */
class AccountAuthLifecycleTest {
    @Test fun defaultUnavailableAndMissingConsentNeverTouchAnyPortIncludingCleanup() {
        val absent = AuthRig()
        val withoutConsent = AuthRig(consentPresent = false)
        val owners = listOf(AccountAuthCoordinator.unavailable(), AccountAuthCoordinator.unavailableForSyntheticTests(absent.ports), withoutConsent.owner)
        for (owner in owners) {
            checkSource(owner.status().phase == AccountPhase.UNAVAILABLE && owner.restore() == AuthAction.UNAVAILABLE, "unavailable construction/restoration")
            checkSource(owner.begin(TEST_SCOPE) == AuthAction.UNAVAILABLE && owner.cancelAttempt() == AuthAction.UNAVAILABLE &&
                owner.acceptCallback(bytes("untrusted")) == AuthAction.UNAVAILABLE && owner.refresh() == AuthAction.UNAVAILABLE &&
                owner.signOut() == AuthAction.UNAVAILABLE && owner.switchTo(AndroidAuthChannel.PLAY) == AuthAction.UNAVAILABLE &&
                owner.switchTo(null) == AuthAction.UNAVAILABLE && owner.revokeRemote() == AuthAction.UNAVAILABLE, "all unavailable operations")
            checkSource(owner.status().localGeneration == 0L, "unavailable cannot become admitted via switch")
        }
        absent.noPortCalls(); withoutConsent.noPortCalls()
    }

    @Test fun admittedUncertainCleanupIsDistinctFromNeverAdmittedUnavailable() {
        val rig = AuthRig()
        val callback = rig.begin()
        rig.vault.fault = VaultFault.NOOP
        checkSource(rig.owner.acceptCallback(callback) == AuthAction.UNCERTAIN, "actual custody failure")
        val before = rig.vault.writes.get()
        rig.vault.fault = VaultFault.NONE
        checkSource(rig.owner.signOut() == AuthAction.FENCED && rig.vault.writes.get() == before + 1, "admitted uncertain cleanup uses actual vault")
        checkSource(rig.owner.status().localErasure == LocalErasure.VERIFIED && rig.owner.status().remoteRevocation == RemoteRevocation.PENDING, "custody failure still has remote uncertainty")
        checkSource(rig.owner.switchTo(null) == AuthAction.FENCED && rig.owner.status().phase == AccountPhase.UNAVAILABLE, "admitted switch to unavailable fences")
        checkSource(rig.owner.signOut() == AuthAction.FENCED && rig.owner.begin(TEST_SCOPE) == AuthAction.UNAVAILABLE, "already-owned unavailable can erase, not authenticate")
    }

    @Test fun freshStateVerifierButStableProcessOwnerInstallationAcrossSignoutReauthentication() {
        val rig = AuthRig()
        rig.signIn()
        val firstQuery = rig.consent.query()
        val first = Json.parseToJsonElement(rig.transport.all().last().bodyBytes().toString(Charsets.UTF_8)).jsonObject
        checkSource(rig.entropy.calls.get() == 3, "one installation plus first state/verifier")
        checkSource(rig.owner.signOut() == AuthAction.FENCED, "actual signout for reauth")
        rig.signIn()
        val secondQuery = rig.consent.query()
        val second = Json.parseToJsonElement(rig.transport.all().last().bodyBytes().toString(Charsets.UTF_8)).jsonObject
        checkSource(first.text("installation_id") == second.text("installation_id") && rig.entropy.calls.get() == 5, "stable owner installation, two fresh attempt values")
        checkSource(firstQuery["state"] != secondQuery["state"] && first.text("code_verifier") != second.text("code_verifier"), "fresh private state/verifier")
        checkSource(rig.owner.switchTo(AndroidAuthChannel.FDROID) == AuthAction.FENCED, "channel switch")
        rig.signIn()
        val third = Json.parseToJsonElement(rig.transport.all().last().bodyBytes().toString(Charsets.UTF_8)).jsonObject
        checkSource(third.text("installation_id") == first.text("installation_id") && third.text("client_id") == "synthetic-android-fdroid", "stable process owner, separate registered channel")
    }

    @Test fun onePendingAndConcurrentCallbackConsumeAtMostOnce() {
        val rig = AuthRig()
        val callback = rig.begin()
        checkSource(rig.owner.begin(TEST_SCOPE) == AuthAction.REJECTED && rig.entropy.calls.get() == 3, "one pending avoids extra entropy")
        val point = DeferredPoint()
        rig.transport.handler = { request -> point.pause(); rig.transport.normalReply(request) }
        val first = RunningAction { rig.owner.acceptCallback(callback) }
        try {
            point.awaitReached()
            checkSource(rig.owner.acceptCallback(callback) == AuthAction.REJECTED && rig.transport.count() == 1, "actual callback one use while deferred")
        } finally { point.release() }
        checkSource(first.finish() == AuthAction.INSTALLED && rig.owner.acceptCallback(callback) == AuthAction.REJECTED, "replay after actual install")
    }

    @Test fun switchThenLateExchangeCannotClobberNewPendingOwner() {
        val rig = AuthRig()
        val old = rig.begin()
        val point = DeferredPoint()
        rig.transport.handler = { request -> point.pause(); rig.transport.normalReply(request) }
        val exchange = RunningAction { rig.owner.acceptCallback(old) }
        try {
            point.awaitReached()
            checkSource(rig.owner.switchTo(AndroidAuthChannel.FDROID) == AuthAction.FENCED, "actual switch during exchange")
            val fresh = rig.begin()
            point.release()
            checkSource(exchange.finish() == AuthAction.REJECTED && rig.owner.status().phase == AccountPhase.PENDING, "late exchange does not install or clobber pending")
            rig.transport.handler = null
            checkSource(rig.owner.acceptCallback(fresh) == AuthAction.INSTALLED && rig.owner.status().clientId == "synthetic-android-fdroid", "only fresh owner can install")
        } finally { point.release() }
    }

    @Test fun signoutAfterParsingBeforeAuthoritativeCommitRejectsInstallation() {
        val rig = AuthRig()
        val callback = rig.begin()
        val point = DeferredPoint()
        rig.vault.beforeCommit.set { point.pause() }
        val exchange = RunningAction { rig.owner.acceptCallback(callback) }
        try {
            point.awaitReached() // actual response parsed and candidate prepared; vault gate has NOT run
            checkSource(rig.owner.signOut() == AuthAction.FENCED && !rig.owner.status().accountOperationsAllowed, "signout before commit")
        } finally { point.release() }
        checkSource(exchange.finish() == AuthAction.REJECTED && rig.vault.inspect()?.normal == null &&
            rig.vault.inspect()?.signedOut == true, "late gate denies secure write")
    }

    @Test fun signoutAfterWriteBeforeVisibilityAlsoRejectsInstallation() {
        val rig = AuthRig()
        val callback = rig.begin()
        val point = DeferredPoint()
        rig.vault.afterCommit.set { point.pause() }
        val exchange = RunningAction { rig.owner.acceptCallback(callback) }
        try {
            point.awaitReached() // the actual candidate row committed but not yet verified/visible
            checkSource(rig.vault.inspect()?.normal != null, "actual write preceded signout")
            checkSource(rig.owner.signOut() == AuthAction.FENCED, "signout before visible readback")
        } finally { point.release() }
        checkSource(exchange.finish() == AuthAction.REJECTED && rig.owner.status().namespace == null &&
            rig.vault.inspect()?.normal == null, "visibility rechecks generation")
    }

    @Test fun lostCommitReplyVerifiedReadbackInstallsButNoopPartialUnreadableNeverDo() {
        val faults = listOf(VaultFault.NOOP, VaultFault.BEFORE_COMMIT, VaultFault.UNREADABLE_AFTER_COMMIT, VaultFault.STALE_READBACK,
            VaultFault.PARTIAL, VaultFault.WRONG_OWNER, VaultFault.WRONG_GENERATION, VaultFault.WRONG_INSTALLATION, VaultFault.MISSING_RECEIPT)
        for (fault in faults) {
            val rig = AuthRig()
            val callback = rig.begin()
            rig.vault.fault = fault
            checkSource(rig.owner.acceptCallback(callback) == AuthAction.UNCERTAIN && rig.owner.status().namespace == null &&
                !rig.owner.status().accountOperationsAllowed, "faulted actual commit never installs")
            checkSource(rig.owner.refresh() == AuthAction.REJECTED && rig.transport.count() == 1, "fault cannot roll back to/replay token")
        }
        val lost = AuthRig()
        val callback = lost.begin()
        lost.vault.fault = VaultFault.LOST_REPLY
        checkSource(lost.owner.acceptCallback(callback) == AuthAction.INSTALLED && lost.owner.status().sessionGeneration == 0L &&
            lost.vault.reads.get() == 2 && lost.vault.writes.get() == 1, "held result only installed after exact readable lost-reply proof")
        println("VAULT actual-initial-commit-faults=9 lost-reply-readable-positive=1")
    }

    @Test fun initialServerGenerationMustBeZeroRegardlessOfLocalGeneration() {
        val rig = AuthRig(seed = 500)
        rig.signIn()
        checkSource(rig.owner.status().localGeneration == 500L && rig.owner.status().sessionGeneration == 0L, "independent actual generations")
        for (generation in listOf(1L, AccountAuthWire.MAX_SERVER_GENERATION)) {
            val invalid = AuthRig()
            invalid.transport.handler = { request ->
                val response = invalid.transport.normalReply(request)
                SyntheticReply(request, request.url, 200, patched(response.bytes(), mapOf("session_generation" to JsonPrimitive(generation))))
            }
            checkSource(invalid.owner.acceptCallback(invalid.begin()) == AuthAction.UNCERTAIN && invalid.vault.writes.get() == 0, "nonzero initial rejected before custody")
        }
    }

    @Test fun overlappingRefreshSerializesLoadRequestValidateCommitAndCoalescesOneConsumption() {
        val rig = AuthRig()
        rig.signIn()
        val original = rig.vault.inspect()!!.normal!!.session!!
        val point = DeferredPoint()
        rig.transport.handler = { request -> point.pause(); rig.transport.normalReply(request) }
        val first = RunningAction { rig.owner.refresh() }
        val second: RunningAction
        try {
            point.awaitReached()
            second = RunningAction { rig.owner.refresh() }
            second.awaitWaiting() // actual ReentrantLock wait, not a phase-label prediction
            checkSource(rig.transport.count(AuthRequestKind.REFRESH) == 1 && rig.vault.writes.get() == 1, "only one actual in-flight refresh")
        } finally { point.release() }
        checkSource(first.finish() == AuthAction.REFRESHED && second.finish() == AuthAction.COALESCED, "serialized/coalesced actual refresh outcomes")
        val requests = rig.transport.all().filter { it.kind == AuthRequestKind.REFRESH }
        val sent = Json.parseToJsonElement(requests.single().bodyBytes().toString(Charsets.UTF_8)).jsonObject
        checkSource(sent.text("refresh_token") == original.refreshToken.wire && rig.vault.writes.get() == 2 &&
            rig.owner.status().sessionGeneration == 1L, "one parent consumption and one verified replacement")
    }

    @Test fun refreshPreservesNamespaceClientInstallationFamilyAndScopes() {
        val rig = AuthRig()
        rig.signIn()
        val before = rig.vault.inspect()!!.normal!!.session!!
        checkSource(rig.owner.refresh() == AuthAction.REFRESHED, "actual refresh")
        val after = rig.vault.inspect()!!.normal!!.session!!
        checkSource(before.namespace.same(after.namespace) && before.clientId == after.clientId && before.installationId == after.installationId &&
            before.sessionId == after.sessionId && before.scope == after.scope && before.audience == after.audience &&
            after.sessionGeneration == before.sessionGeneration + 1 && after.accessToken.wire != before.accessToken.wire &&
            after.refreshToken.wire != before.refreshToken.wire, "all refresh binding/secret transitions privately")
        checkSource(rig.owner.status().localGeneration == 0L, "refresh not local account switch")
    }

    @Test fun refreshWrongOwnerBindingScopeGenerationAndTokenReuseQuarantineActualResponses() {
        val patches = listOf(mapOf("account_id" to JsonPrimitive("synthetic-account-b")), mapOf("client_id" to JsonPrimitive("synthetic-android-fdroid")),
            mapOf("installation_id" to JsonPrimitive(reference(44))), mapOf("session_id" to JsonPrimitive(reference(45))),
            mapOf("scope" to JsonPrimitive("config:profiles:read")), mapOf("scope" to JsonPrimitive("$TEST_SCOPE health:read")),
            mapOf("session_generation" to JsonPrimitive(0)), mapOf("session_generation" to JsonPrimitive(2)))
        for (patch in patches) {
            val rig = AuthRig(); rig.signIn()
            rig.transport.handler = { request ->
                val reply = rig.transport.normalReply(request)
                SyntheticReply(request, request.url, 200, patched(reply.bytes(), patch))
            }
            checkSource(rig.owner.refresh() == AuthAction.UNCERTAIN && rig.owner.status().namespace == null &&
                rig.owner.refresh() == AuthAction.REJECTED && rig.transport.count(AuthRequestKind.REFRESH) == 1, "wrong actual refresh quarantined no replay")
        }
        val sameProof = AuthRig(); sameProof.signIn()
        val old = sameProof.vault.inspect()!!.normal!!.session!!
        sameProof.transport.handler = { request ->
            val reply = sameProof.transport.normalReply(request)
            SyntheticReply(request, request.url, 200, patched(reply.bytes(), mapOf("refresh_token" to JsonPrimitive(old.refreshToken.wire))))
        }
        checkSource(sameProof.owner.refresh() == AuthAction.UNCERTAIN, "unchanged parent cannot be reinstalled")
        println("REFRESH binding/transition-negative-responses=9 actual-coordinator-quarantines")
    }

    @Test fun corruptStalePartialWrongOwnerVaultLoadPreventsRefreshBeforeNetwork() {
        for (mode in 0..4) {
            val rig = AuthRig(); rig.signIn()
            val original = rig.vault.inspect()!!
            val record = original.normal!!
            when (mode) {
                0 -> rig.vault.failReads = true
                1 -> rig.vault.inject(VaultImage(Any(), original.localGeneration, false, record, original.receipt))
                2 -> rig.vault.inject(VaultImage(original.processOwner, original.localGeneration + 1, false, record, original.receipt))
                3 -> rig.vault.inject(VaultImage(original.processOwner, original.localGeneration, false,
                    VaultSession(null, record.localGeneration, record.expiresAt, record.installationBinding), original.receipt))
                4 -> rig.vault.inject(VaultImage(original.processOwner, original.localGeneration, false,
                    VaultSession(record.session, record.localGeneration, record.expiresAt, reference(12)), original.receipt))
            }
            checkSource(rig.owner.refresh() == AuthAction.UNCERTAIN && rig.transport.count(AuthRequestKind.REFRESH) == 0 &&
                !rig.owner.status().accountOperationsAllowed, "actual invalid load before request")
        }
    }

    @Test fun lostRefreshReplyAndLocalCommitFailureNeverReplayOrResurrectParent() {
        val rig = AuthRig(); rig.signIn()
        rig.transport.handler = { request -> rig.transport.normalReply(request); throw IllegalStateException("synthetic lost rotated response") }
        checkSource(rig.owner.refresh() == AuthAction.UNCERTAIN && rig.owner.refresh() == AuthAction.REJECTED &&
            rig.transport.count(AuthRequestKind.REFRESH) == 1 && rig.owner.status().namespace == null, "lost rotated reply requires fresh auth no parent replay")
        for (fault in listOf(VaultFault.NOOP, VaultFault.UNREADABLE_AFTER_COMMIT, VaultFault.STALE_READBACK)) {
            val local = AuthRig(); local.signIn(); local.vault.fault = fault
            checkSource(local.owner.refresh() == AuthAction.UNCERTAIN && local.owner.refresh() == AuthAction.REJECTED &&
                local.transport.count(AuthRequestKind.REFRESH) == 1, "failed custody after rotation never reuses parent")
        }
    }

    @Test fun lateRefreshAfterSignoutDuringResponseAndDuringCommitCannotInstall() {
        for (atCommit in listOf(false, true)) {
            val rig = AuthRig(); rig.signIn()
            val point = DeferredPoint()
            if (atCommit) rig.vault.beforeCommit.set { point.pause() }
            else rig.transport.handler = { request -> point.pause(); rig.transport.normalReply(request) }
            val refresh = RunningAction { rig.owner.refresh() }
            try {
                point.awaitReached()
                checkSource(rig.owner.signOut() == AuthAction.FENCED && rig.owner.status().namespace == null &&
                    rig.owner.refresh() == AuthAction.REJECTED, "immediate local fence while refresh deferred")
            } finally { point.release() }
            checkSource(refresh.finish() == AuthAction.REJECTED && rig.vault.inspect()?.normal == null, "late rotated result rejected at owner gate")
        }
    }

    @Test fun signoutImmediateFenceWhileEraseDeferredNoopOrUnreadableNeverClaimsLocalCompletion() {
        val rig = AuthRig(); rig.signIn()
        val point = DeferredPoint()
        rig.vault.beforeCommit.set { point.pause() }
        val erase = RunningAction { rig.owner.signOut() }
        try {
            point.awaitReached()
            val status = rig.owner.status()
            checkSource(status.phase == AccountPhase.LOCAL_SIGNED_OUT && status.localErasure == LocalErasure.PENDING &&
                status.namespace == null && !status.accountOperationsAllowed && rig.owner.refresh() == AuthAction.REJECTED, "local fence precedes deferred erase")
        } finally { point.release() }
        checkSource(erase.finish() == AuthAction.FENCED && rig.owner.status().localErasure == LocalErasure.VERIFIED, "verified local erase readback")
        for (fault in listOf(VaultFault.NOOP, VaultFault.UNREADABLE_AFTER_COMMIT, VaultFault.WRONG_OWNER, VaultFault.MISSING_RECEIPT)) {
            val broken = AuthRig(); broken.signIn(); broken.vault.fault = fault
            checkSource(broken.owner.signOut() == AuthAction.UNCERTAIN && broken.owner.status().localErasure == LocalErasure.UNVERIFIED &&
                broken.owner.status().remoteRevocation == RemoteRevocation.PENDING && broken.owner.status().namespace == null, "unverified erase never completion")
        }
        val lost = AuthRig(); lost.signIn(); lost.vault.fault = VaultFault.LOST_REPLY
        checkSource(lost.owner.signOut() == AuthAction.FENCED && lost.owner.status().localErasure == LocalErasure.VERIFIED, "lost erase reply readable postcondition")
    }

    @Test fun expiryClockFaultAndCustodyFailureSignoutKeepRemoteFamilyObligations() {
        val expired = AuthRig(); expired.signIn(); expired.clock.value.set(400)
        checkSource(expired.owner.status().phase == AccountPhase.EXPIRED && expired.owner.status().remoteRevocation == RemoteRevocation.PENDING, "access expiry at equality not family revocation")
        checkSource(expired.owner.signOut() == AuthAction.FENCED && expired.owner.status().remoteRevocation == RemoteRevocation.PENDING &&
            expired.owner.revokeRemote() == AuthAction.REJECTED, "expired access signout cannot imply no remote obligation")
        val clockFault = AuthRig(); clockFault.signIn(); clockFault.clock.value.set(-1)
        checkSource(clockFault.owner.status().phase == AccountPhase.AUTHENTICATION_UNCERTAIN, "clock fault quarantines access")
        clockFault.clock.value.set(100)
        checkSource(clockFault.owner.signOut() == AuthAction.FENCED && clockFault.owner.status().remoteRevocation == RemoteRevocation.PENDING, "clock fault keeps obligation")
        val custody = AuthRig(); val callback = custody.begin(); custody.vault.fault = VaultFault.UNREADABLE_AFTER_COMMIT
        checkSource(custody.owner.acceptCallback(callback) == AuthAction.UNCERTAIN, "actual unreadable committed credentials")
        custody.vault.failReads = false; custody.vault.fault = VaultFault.NONE
        checkSource(custody.owner.signOut() == AuthAction.FENCED && custody.owner.status().remoteRevocation == RemoteRevocation.PENDING, "custody loss signout keeps obligation")
    }

    @Test fun offlineRemoteRevokeIsPendingAndProofCannotRefreshOrConfigure() {
        val rig = AuthRig(); rig.signIn(); checkSource(rig.owner.signOut() == AuthAction.FENCED, "actual signout")
        val before = rig.transport.count()
        checkSource(rig.owner.refresh() == AuthAction.REJECTED && rig.transport.count() == before && rig.vault.inspect()?.normal == null &&
            rig.owner.status().namespace == null && !rig.owner.status().accountOperationsAllowed, "revoke-only proof not normal credentials/config")
        rig.transport.handler = { throw IllegalStateException("synthetic offline") }
        checkSource(rig.owner.revokeRemote() == AuthAction.UNCERTAIN && rig.owner.status().remoteRevocation == RemoteRevocation.PENDING &&
            rig.owner.status().localErasure == LocalErasure.VERIFIED && rig.transport.count(AuthRequestKind.REVOKE) == 1, "offline not remote completion, no transparent retry")
        val request = Json.parseToJsonElement(rig.transport.all().last().bodyBytes().toString(Charsets.UTF_8)).jsonObject
        checkSource(request.keys == setOf("client_id", "installation_id", "refresh_token") && !request.containsKey("grant_type") &&
            rig.transport.all().last().kind == AuthRequestKind.REVOKE, "proof is confined to closed self-revoke request")
        checkSource(VaultImage::class.java.declaredFields.none { it.type == RevocationOnlyMemory::class.java }, "normal vault cannot read revocation compartment")
    }

    @Test fun onlyClosedCorrelatedCurrentRevokeResponseAcknowledgesNotAny2xx() {
        val cases = listOf(200 to "{}", 200 to "{\"revoked\":false}", 200 to "{\"revoked\":\"true\"}",
            200 to "{\"revoked\":true,\"message\":\"synthetic\"}", 201 to "{\"revoked\":true}", 503 to "{\"error\":\"verification_pending\"}")
        for ((status, body) in cases) {
            val rig = AuthRig(); rig.signIn(); rig.owner.signOut()
            rig.transport.handler = { request -> SyntheticReply(request, request.url, status, bytes(body)) }
            checkSource(rig.owner.revokeRemote() == AuthAction.UNCERTAIN && rig.owner.status().remoteRevocation == RemoteRevocation.PENDING, "unverified revoke never acknowledged")
            rig.transport.handler = null
            checkSource(rig.owner.revokeRemote() == AuthAction.REVOKED && rig.owner.status().remoteRevocation == RemoteRevocation.CONFIRMED &&
                rig.owner.status().localErasure == LocalErasure.VERIFIED, "actual closed revoke acknowledgement")
        }
        val wrong = AuthRig(); wrong.signIn(); wrong.owner.signOut()
        wrong.transport.handler = { request -> SyntheticReply(AuthRequestPlan.refresh(SyntheticRegistration.android(AndroidAuthChannel.PLAY), decodeFixture()),
            request.url, 200, bytes("{\"revoked\":true}")) }
        checkSource(wrong.owner.revokeRemote() == AuthAction.UNCERTAIN && wrong.owner.status().remoteRevocation == RemoteRevocation.PENDING, "uncorrelated revoke denied")
    }

    @Test fun lateRevokeAckAfterSwitchAndPriorUnresolvedFamilyNeverBecomeGlobalConfirmation() {
        val rig = AuthRig(); rig.signIn(); rig.owner.signOut()
        val point = DeferredPoint()
        rig.transport.handler = { request -> point.pause(); rig.transport.normalReply(request) }
        val revoke = RunningAction { rig.owner.revokeRemote() }
        try {
            point.awaitReached()
            checkSource(rig.owner.switchTo(AndroidAuthChannel.FDROID) == AuthAction.FENCED, "switch while revoke in flight")
        } finally { point.release() }
        checkSource(revoke.finish() == AuthAction.REJECTED && rig.owner.status().remoteRevocation == RemoteRevocation.PENDING, "late ack not current request/generation")
        val two = AuthRig(); two.signIn(); two.owner.signOut() // first family deliberately unresolved
        two.signIn(); two.owner.signOut()
        checkSource(two.owner.revokeRemote() == AuthAction.REVOKED && two.owner.status().remoteRevocation == RemoteRevocation.PENDING, "new family ack cannot confirm older unresolved family")
    }

    @Test fun recreationStaleCorruptPartialOrFailedSignoutRowCannotResurrectAndPendingIsUnsecured() {
        val rig = AuthRig()
        val callback = rig.begin()
        val recreated = AccountAuthCoordinator.forSyntheticTests(AndroidAuthChannel.PLAY, rig.ports)
        val before = rig.vault.reads.get()
        checkSource(recreated.restore() == AuthAction.UNAVAILABLE && recreated.acceptCallback(callback) == AuthAction.REJECTED &&
            rig.vault.reads.get() == before && rig.transport.count() == 0, "process loss invalidates unsecured pending with no restore I/O")
        rig.owner.acceptCallback(callback)
        val old = rig.vault.inspect()!!
        rig.vault.fault = VaultFault.NOOP
        checkSource(rig.owner.signOut() == AuthAction.UNCERTAIN && rig.vault.inspect()!!.same(old), "failed durable fence leaves old row, not proof of intent")
        for (partial in listOf(false, true)) {
            if (partial) rig.vault.inject(VaultImage(Any(), -1, false, VaultSession(null, -1, -1, "corrupt"), Any()))
            val owner = AccountAuthCoordinator.forSyntheticTests(AndroidAuthChannel.PLAY, rig.ports)
            val reads = rig.vault.reads.get()
            checkSource(owner.restore() == AuthAction.UNAVAILABLE && owner.status().namespace == null && rig.vault.reads.get() == reads, "no durable attestation available")
            checkSource(owner.begin(TEST_SCOPE) == AuthAction.UNCERTAIN && !owner.status().accountOperationsAllowed, "explicit fresh auth rejects stale/corrupt row")
            rig.vault.fault = VaultFault.NONE
            checkSource(owner.signOut() == AuthAction.FENCED && owner.begin(TEST_SCOPE) == AuthAction.STARTED, "explicit verified local erase permits only fresh authentication")
            owner.cancelAttempt()
            rig.vault.inject(old)
        }
    }

    @Test fun generationExhaustionFailsClosedAndNeverWrapsToAnOldOwner() {
        val rig = AuthRig(seed = Long.MAX_VALUE - 1)
        rig.signIn()
        checkSource(rig.owner.signOut() == AuthAction.FENCED && rig.owner.status().localGeneration == Long.MAX_VALUE &&
            rig.owner.status().phase == AccountPhase.GENERATION_EXHAUSTED && rig.owner.status().lastFence?.reason == FenceReason.EXHAUSTION, "actual terminal local fence")
        val calls = rig.entropy.calls.get()
        checkSource(rig.owner.begin(TEST_SCOPE) == AuthAction.UNAVAILABLE && rig.owner.refresh() == AuthAction.UNAVAILABLE &&
            rig.entropy.calls.get() == calls, "terminal cannot start more work")
        checkSource(rig.owner.signOut() == AuthAction.FENCED && rig.owner.status().localGeneration == Long.MAX_VALUE, "no overflow on repeated erasure")
        rejection("negative local seed") { AccountAuthCoordinator.forSyntheticTests(AndroidAuthChannel.PLAY, rig.ports, -1) }
    }

    @Test fun unreadableBootRowAndUnknownPriorFamilyCannotBeConfirmedByFreshFamilyAck() {
        val rig = AuthRig(); rig.signIn()
        val freshOwner = AccountAuthCoordinator.forSyntheticTests(AndroidAuthChannel.PLAY, rig.ports)
        rig.vault.failReads = true
        val entropy = rig.entropy.calls.get()
        checkSource(freshOwner.begin(TEST_SCOPE) == AuthAction.UNCERTAIN && rig.entropy.calls.get() == entropy &&
            freshOwner.status().remoteRevocation == RemoteRevocation.PENDING, "unreadable boot quarantines without entropy")
        rig.vault.failReads = false
        checkSource(freshOwner.signOut() == AuthAction.FENCED && freshOwner.begin(TEST_SCOPE) == AuthAction.STARTED, "fresh auth only after verified erase")
        checkSource(freshOwner.acceptCallback(rig.callback()) == AuthAction.INSTALLED && freshOwner.signOut() == AuthAction.FENCED &&
            freshOwner.revokeRemote() == AuthAction.REVOKED && freshOwner.status().remoteRevocation == RemoteRevocation.PENDING,
            "current family ack cannot prove unknown prior family revoked")
        val badClock = AuthRig(); badClock.signIn(); badClock.clock.value.set(-1)
        checkSource(badClock.owner.refresh() == AuthAction.UNCERTAIN && badClock.transport.count(AuthRequestKind.REFRESH) == 0, "clock preflight cannot throw or dispatch")
    }

    @Test fun cancellationAfterParseBeforeCommitCannotInstallEvenWithoutGenerationChange() {
        val rig = AuthRig(); val old = rig.begin()
        val point = DeferredPoint()
        rig.vault.beforeCommit.set { point.pause() }
        val exchange = RunningAction { rig.owner.acceptCallback(old) }
        try {
            point.awaitReached()
            checkSource(rig.owner.cancelAttempt() == AuthAction.CANCELLED, "cancel actual deferred commit")
            val fresh = rig.begin()
            point.release()
            checkSource(exchange.finish() == AuthAction.REJECTED && rig.owner.status().phase == AccountPhase.PENDING &&
                rig.owner.acceptCallback(fresh) == AuthAction.INSTALLED, "operation identity fences cancelled attempt before write")
        } finally { point.release() }
    }

    @Test fun priorVerifiedEraseIsSupersededBeforeReauthCustodyCanCommitWithUnreadableProof() {
        for (fault in listOf(VaultFault.UNREADABLE_AFTER_COMMIT, VaultFault.LOST_REPLY_AND_UNREADABLE)) {
            val rig = AuthRig(); rig.signIn()
            checkSource(rig.owner.signOut() == AuthAction.FENCED && rig.owner.status().localErasure == LocalErasure.VERIFIED, "prior correlated erasure verified")
            val callback = rig.begin()
            checkSource(rig.owner.status().localErasure == LocalErasure.NOT_REQUESTED, "new attempt supersedes historical erase proof before custody")
            rig.vault.fault = fault
            checkSource(rig.owner.acceptCallback(callback) == AuthAction.UNCERTAIN, "actual reauth commit lacks readable proof")
            val populated = rig.vault.inspect()
            checkSource(populated?.normal?.session != null && populated.signedOut == false, "actual new credentials committed despite lost/unreadable reply")
            val status = rig.owner.status()
            checkSource(status.phase == AccountPhase.AUTHENTICATION_UNCERTAIN && status.namespace == null &&
                status.localErasure == LocalErasure.NOT_REQUESTED && status.remoteRevocation == RemoteRevocation.PENDING,
                "historical erase cannot certify current populated uncertain row")
            checkSource(rig.owner.begin(TEST_SCOPE) == AuthAction.REJECTED && rig.owner.refresh() == AuthAction.REJECTED, "fresh auth required, no parent replay")
            rig.vault.failReads = false; rig.vault.fault = VaultFault.NONE
            val recreated = AccountAuthCoordinator.forSyntheticTests(AndroidAuthChannel.PLAY, rig.ports)
            val reads = rig.vault.reads.get()
            checkSource(recreated.restore() == AuthAction.UNAVAILABLE && rig.vault.reads.get() == reads &&
                recreated.begin(TEST_SCOPE) == AuthAction.UNCERTAIN, "populated stale row is not restoration authority")
            checkSource(rig.owner.signOut() == AuthAction.FENCED && rig.owner.status().remoteRevocation == RemoteRevocation.PENDING,
                "verified new local erase does not erase possible remote-family obligations")
        }
        println("ERASURE prior-proof-supersession actual-committed-reauth/unreadable=2 includes-lost-commit-reply")
    }

    @Test fun unknownRevocationObligationCapFailsBeforeMorePortsOrInventedExpiry() {
        val rig = AuthRig()
        repeat(20) { rig.signIn(); checkSource(rig.owner.signOut() == AuthAction.FENCED, "actual unresolved family") }
        val entropy = rig.entropy.calls.get()
        val reads = rig.vault.reads.get()
        val requests = rig.transport.count()
        checkSource(rig.owner.begin(TEST_SCOPE) == AuthAction.UNCERTAIN && rig.entropy.calls.get() == entropy &&
            rig.vault.reads.get() == reads && rig.transport.count() == requests && rig.owner.status().remoteRevocation == RemoteRevocation.PENDING,
            "bounded unresolved memory fails closed, no fake retention cleanup")
    }

    @Test fun entropyFailureNoFallbackAndIndependentLocalOfflineSentinelsRemainUnchanged() {
        val rig = AuthRig()
        rig.entropy.failure = true
        checkSource(rig.owner.begin(TEST_SCOPE) == AuthAction.REJECTED && rig.transport.count() == 0 && rig.consent.calls.get() == 0, "actual entropy failure no fallback or fake consent")
        rig.entropy.failure = false
        val sentinels = linkedMapOf("health" to "local-only", "profile" to "accepted-local-revision", "destination" to "local-destination",
            "schedule" to "local-schedule", "purchase" to "independent", "provider" to "independent", "direct" to "paired-local", "offline" to "local-outbox")
        val before = sentinels.toMap()
        val forbiddenCalls = AtomicInteger()
        // Deliberately NOT injected: the auth port interface has no way to reach these local owners.
        val localOwner = { forbiddenCalls.incrementAndGet(); sentinels["health"] = "changed" }
        checkSource(SyntheticAuthPorts::class.java.declaredFields.none { it.type == localOwner.javaClass }, "independent owner is not an auth port")
        rig.signIn(); rig.owner.refresh(); rig.owner.signOut(); rig.owner.revokeRemote(); rig.owner.switchTo(AndroidAuthChannel.FDROID)
        checkSource(sentinels == before && forbiddenCalls.get() == 0 && SyntheticAuthPorts::class.java.declaredFields.size == 5, "library boundary preserves independent sentinels")
        println("BOUNDARY independent-sentinels=8 forbidden-library-calls=0 (not app-root/foreground/widget evidence)")
    }
}
