package com.healthmd.accountauth

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** All adapters are explicit, fake-only ports. Consent absence keeps every operation unavailable. */
class SyntheticAuthPorts(
    val entropy: SyntheticEntropy,
    val clock: SyntheticClock,
    val vault: SyntheticAccountVault,
    val transport: SyntheticAuthTransport,
    val consent: SyntheticConsentPort?,
) {
    override fun toString(): String = "SyntheticAuthPorts(not qualified native adapters)"
}

/**
 * Root-free synchronous JVM owner, not a native sign-in feature. Refresh is serialized across
 * load/request/validate/commit; signout/switch bypass that lock and immediately invalidate ownership.
 * The one-use vault gate rechecks ownership at installation, AND again at visible readback.
 * There are no health/config/provider/purchase dependencies or automatic restoration/retries.
 */
class AccountAuthCoordinator private constructor(
    private var registration: SyntheticRegistration?,
    private val ports: SyntheticAuthPorts?,
    initialLocalGeneration: Long,
) {
    private val ownerLock = ReentrantLock()
    private val refreshLock = ReentrantLock()
    private val revokeLock = ReentrantLock()
    private val processOwner = Any()
    // Never-admitted construction cannot become admitted via switch or perform cleanup I/O.
    private val admitted = registration != null && ports?.consent != null
    private var installationId: String? = null // stable for this owner/process; never auto-restored
    private val remoteObligations = mutableSetOf<Any>() // nonsecret correlation, not persistent retention
    private var activeFamilyObligation: Any? = null
    private var generation = initialLocalGeneration
    private var exhausted = initialLocalGeneration == Long.MAX_VALUE
    private var phase = if (exhausted) AccountPhase.GENERATION_EXHAUSTED else if (available()) AccountPhase.SIGNED_OUT else AccountPhase.UNAVAILABLE
    private var operation: Any? = null
    private var pending: Pending? = null
    private var normal: VaultImage? = null
    private var erasure = LocalErasure.NOT_REQUESTED
    private var remote = RemoteRevocation.NONE
    private var revokeOnly: RevocationOnlyMemory? = null
    private var lastFence: AccountFenceEvent? = null

    private class Capture(val id: Any, val generation: Long, val registration: SyntheticRegistration)
    private class Pending(val capture: Capture, val secrets: AttemptSecrets, val scope: String, val expiresAt: Long, val expectedVault: VaultImage?)
    private class ClearCapture(val id: Any, val generation: Long)

    companion object {
        private const val MAX_REMOTE_OBLIGATIONS = 20
        fun unavailable(): AccountAuthCoordinator = AccountAuthCoordinator(null, null, 0)
        fun unavailableForSyntheticTests(ports: SyntheticAuthPorts): AccountAuthCoordinator = AccountAuthCoordinator(null, ports, 0)
        fun forSyntheticTests(channel: AndroidAuthChannel, ports: SyntheticAuthPorts, initialLocalGeneration: Long = 0): AccountAuthCoordinator {
            if (initialLocalGeneration < 0) reject(AuthRejection.GENERATION_EXHAUSTED)
            return AccountAuthCoordinator(SyntheticRegistration.android(channel), ports, initialLocalGeneration)
        }
    }

    private fun available(): Boolean = admitted && registration != null && !exhausted
    private fun now(): Long {
        val value = try { ports?.clock?.seconds() ?: reject(AuthRejection.UNAVAILABLE) }
            catch (_: Exception) { reject(AuthRejection.UNAVAILABLE) }
        if (value !in 0..AccountAuthWire.MAX_SERVER_GENERATION - 300) reject(AuthRejection.UNAVAILABLE)
        return value
    }
    private fun owns(capture: Capture): Boolean = !exhausted && generation == capture.generation &&
        operation === capture.id && registration === capture.registration
    private fun same(a: VaultImage?, b: VaultImage?): Boolean =
        (a == null && b == null) || (a != null && b != null && a.same(b))

    fun status(): AccountStatus = ownerLock.withLock {
        val record = normal?.normal
        if (record != null && phase in setOf(AccountPhase.SIGNED_IN, AccountPhase.REFRESHING)) {
            try {
                if (record.expiresAt <= now()) {
                    phase = AccountPhase.EXPIRED; normal = null; operation = null
                    if (remoteObligations.isNotEmpty()) remote = RemoteRevocation.PENDING
                }
            } catch (_: Exception) {
                phase = AccountPhase.AUTHENTICATION_UNCERTAIN; normal = null; operation = null
                if (remoteObligations.isNotEmpty()) remote = RemoteRevocation.PENDING
            }
        }
        val session = normal?.normal?.session
        AccountStatus(phase, generation, session?.namespace, session?.clientId, session?.sessionGeneration, erasure, remote, lastFence)
    }

    /** A stale row cannot attest failed-signout intent. No qualified durable fence adapter exists. */
    fun restore(): AuthAction = AuthAction.UNAVAILABLE // ZERO vault/entropy/network/consent calls

    fun begin(scope: String): AuthAction {
        val capture = ownerLock.withLock {
            if (!available()) return AuthAction.UNAVAILABLE
            if (phase != AccountPhase.SIGNED_OUT && !(phase == AccountPhase.LOCAL_SIGNED_OUT && erasure == LocalErasure.VERIFIED)) return AuthAction.REJECTED
            if (remoteObligations.size >= MAX_REMOTE_OBLIGATIONS) {
                remote = RemoteRevocation.PENDING; phase = AccountPhase.AUTHENTICATION_UNCERTAIN
                return AuthAction.UNCERTAIN // bound memory; no invented retention/expiry cleanup
            }
            Capture(Any(), generation, registration!!).also { operation = it.id; phase = AccountPhase.STARTING }
        }
        try {
            val requested = canonicalScope(scope)
            val row = try { ports!!.vault.readNormal() } catch (_: Exception) { reject(AuthRejection.VAULT_UNCERTAIN) }
            if (row != null && (row.processOwner !== processOwner || row.localGeneration != capture.generation ||
                    !row.signedOut || row.normal != null)) reject(AuthRejection.VAULT_UNCERTAIN)
            val heldInstallation = ownerLock.withLock {
                if (!owns(capture)) return AuthAction.REJECTED
                installationId
            } ?: AccountAuthPKCE.installationForSyntheticTests(ports.entropy).let { fresh ->
                ownerLock.withLock {
                    if (!owns(capture)) return AuthAction.REJECTED
                    if (installationId == null) installationId = fresh
                    installationId!!
                }
            }
            val secrets = AccountAuthPKCE.freshForSyntheticTests(ports.entropy, heldInstallation)
            val attempt = Pending(capture, secrets, requested, now() + 300, row)
            ownerLock.withLock {
                if (!owns(capture)) return AuthAction.REJECTED
                pending = attempt; phase = AccountPhase.PENDING
            }
            ports.consent!!.reviewOnly(authorizationPlan(capture.registration, requested, secrets))
            return ownerLock.withLock { if (owns(capture) && pending === attempt) AuthAction.STARTED else AuthAction.REJECTED }
        } catch (error: Exception) {
            return fail(capture, error is AuthSourceException && error.rejection == AuthRejection.VAULT_UNCERTAIN)
        }
    }

    fun cancelAttempt(): AuthAction = ownerLock.withLock {
        if (!available()) return AuthAction.UNAVAILABLE
        if (phase !in setOf(AccountPhase.STARTING, AccountPhase.PENDING, AccountPhase.EXCHANGING)) return AuthAction.REJECTED
        if (phase == AccountPhase.EXCHANGING) remote = RemoteRevocation.PENDING
        pending = null; operation = null; phase = AccountPhase.SIGNED_OUT
        lastFence = AccountFenceEvent(generation, FenceReason.CANCEL)
        AuthAction.CANCELLED
    }

    fun acceptCallback(raw: ByteArray): AuthAction {
        val attempt: Pending
        val callback: CallbackResult
        ownerLock.withLock {
            if (!available()) return AuthAction.UNAVAILABLE
            attempt = pending ?: return AuthAction.REJECTED
            if (phase != AccountPhase.PENDING || !owns(attempt.capture)) return AuthAction.REJECTED
            try {
                if (now() >= attempt.expiresAt) {
                    pending = null; operation = null; phase = AccountPhase.SIGNED_OUT
                    lastFence = AccountFenceEvent(generation, FenceReason.TIMEOUT)
                    return AuthAction.REJECTED
                }
                callback = AccountAuthCallback.decode(raw, attempt.capture.registration, attempt.secrets.state)
            } catch (_: Exception) { return AuthAction.REJECTED }
            pending = null // consume exactly once before any transport call
            if (callback == CallbackResult.Denied) { operation = null; phase = AccountPhase.SIGNED_OUT; return AuthAction.DENIED }
            phase = AccountPhase.EXCHANGING
        }
        try {
            val code = (callback as CallbackResult.Code).code
            val plan = AuthRequestPlan.code(attempt.capture.registration, code, attempt.secrets)
            val context = WireContext.forSyntheticTests(attempt.capture.registration.clientId, attempt.secrets.installationId, attempt.scope)
            ownerLock.withLock {
                if (!owns(attempt.capture)) return AuthAction.REJECTED
                // Consumable code dispatch can create a family even if its reply/custody is lost.
                if (remoteObligations.isEmpty()) remote = RemoteRevocation.NONE
                remoteObligations.add(attempt.capture.id)
                activeFamilyObligation = attempt.capture.id
            }
            return when (val reply = tokenReply(ports!!.transport, plan, context)) {
                is TokenReply.Failure -> fail(attempt.capture, true)
                is TokenReply.Session -> {
                    AccountAuthWire.requireInitial(reply.value)
                    install(attempt.capture, attempt.expectedVault, reply.value, false)
                }
            }
        } catch (_: Exception) { return fail(attempt.capture, true) }
    }

    private fun fail(capture: Capture, uncertain: Boolean): AuthAction = ownerLock.withLock {
        if (!owns(capture)) return AuthAction.REJECTED
        pending = null; operation = null; normal = null
        phase = if (uncertain) AccountPhase.AUTHENTICATION_UNCERTAIN else AccountPhase.SIGNED_OUT
        if (uncertain) {
            remote = RemoteRevocation.PENDING
            // An unreadable/stale boot row may belong to an unknown remote family. A later fresh
            // family's acknowledgement cannot erase that uncertainty, even after local erasure.
            if (remoteObligations.isEmpty()) remoteObligations.add(Any())
        }
        if (uncertain) AuthAction.UNCERTAIN else AuthAction.REJECTED
    }

    private fun install(capture: Capture, expected: VaultImage?, session: NativeSession, refresh: Boolean): AuthAction {
        val candidate = VaultImage(processOwner, capture.generation, false,
            VaultSession(session, capture.generation, now() + session.expiresIn, session.installationId), Any())
        val gate = AccountCommitGate { atomicInstall ->
            ownerLock.withLock {
                if (!owns(capture) || phase !in setOf(AccountPhase.EXCHANGING, AccountPhase.REFRESHING)) reject(AuthRejection.LOCAL_FENCE)
                if (candidate.normal!!.expiresAt <= now()) reject(AuthRejection.LOCAL_FENCE)
                atomicInstall()
            }
        }
        try {
            ports!!.vault.transact(gate) { current ->
                if (!same(current, expected)) reject(AuthRejection.VAULT_UNCERTAIN)
                candidate
            }
        } catch (_: Exception) { /* Lost replies/no-op success are NOT evidence. Fresh readback below. */ }
        val readback = try { ports!!.vault.readNormal() } catch (_: Exception) { return fail(capture, true) }
        return ownerLock.withLock {
            if (!owns(capture)) return AuthAction.REJECTED
            if (!same(candidate, readback) || candidate.normal!!.expiresAt <= now()) return fail(capture, true)
            normal = candidate; operation = null; phase = AccountPhase.SIGNED_IN; erasure = LocalErasure.NOT_REQUESTED
            if (refresh) AuthAction.REFRESHED else AuthAction.INSTALLED
        }
    }

    fun refresh(): AuthAction {
        // Capture the caller's epoch BEFORE waiting: overlapping callers coalesce, not rotate a child again.
        val arrival = ownerLock.withLock {
            if (!available()) return AuthAction.UNAVAILABLE
            if (phase !in setOf(AccountPhase.SIGNED_IN, AccountPhase.REFRESHING)) return AuthAction.REJECTED
            normal ?: return AuthAction.REJECTED
        }
        return refreshLock.withLock {
            val capture: Capture
            val expected: VaultImage
            val previous: NativeSession
            ownerLock.withLock {
                if (!available() || generation != arrival.localGeneration) return AuthAction.REJECTED
                expected = normal ?: return AuthAction.REJECTED
                previous = expected.normal?.session ?: return AuthAction.REJECTED
                if (!expected.same(arrival)) return if (phase == AccountPhase.SIGNED_IN) AuthAction.COALESCED else AuthAction.REJECTED
                if (phase != AccountPhase.SIGNED_IN) return AuthAction.REJECTED
                val time = try { now() } catch (_: Exception) {
                    normal = null; operation = null; phase = AccountPhase.AUTHENTICATION_UNCERTAIN
                    if (remoteObligations.isNotEmpty()) remote = RemoteRevocation.PENDING
                    return AuthAction.UNCERTAIN
                }
                if (expected.normal.expiresAt <= time || previous.sessionGeneration == AccountAuthWire.MAX_SERVER_GENERATION) {
                    normal = null; phase = AccountPhase.AUTHENTICATION_UNCERTAIN
                    if (remoteObligations.isNotEmpty()) remote = RemoteRevocation.PENDING
                    return AuthAction.UNCERTAIN
                }
                capture = Capture(Any(), generation, registration!!)
                operation = capture.id; phase = AccountPhase.REFRESHING
            }
            try {
                val loaded = ports!!.vault.readNormal()
                if (!same(expected, loaded)) reject(AuthRejection.VAULT_UNCERTAIN)
                val plan = AuthRequestPlan.refresh(capture.registration, previous)
                val context = WireContext.forSyntheticTests(previous.clientId, previous.installationId, previous.scope)
                when (val reply = tokenReply(ports.transport, plan, context)) {
                    is TokenReply.Failure -> fail(capture, true)
                    is TokenReply.Session -> {
                        AccountAuthWire.requireRefresh(previous, reply.value)
                        install(capture, expected, reply.value, true)
                    }
                }
            } catch (_: Exception) { fail(capture, true) } // Never replay or resurrect a spent parent.
        }
    }

    fun signOut(): AuthAction = fenceAndClear(FenceReason.SIGNOUT, null, false)
    /** null means unavailable registration, never an inferred live environment or caller URL. */
    fun switchTo(channel: AndroidAuthChannel?): AuthAction = fenceAndClear(FenceReason.SWITCH, channel, true)

    private fun fenceAndClear(reason: FenceReason, channel: AndroidAuthChannel?, switching: Boolean): AuthAction {
        val capture = ownerLock.withLock {
            if (!admitted) return AuthAction.UNAVAILABLE
            val previous = normal?.normal
            val previousRegistration = registration
            val obligation = activeFamilyObligation
            if (generation < Long.MAX_VALUE) generation++
            if (generation == Long.MAX_VALUE) exhausted = true
            revokeOnly = if (!switching && !exhausted && previous != null && previousRegistration != null && obligation != null) {
                RevocationOnlyMemory.capture(previousRegistration, previous, generation, obligation)
            } else null
            pending = null; normal = null; activeFamilyObligation = null
            if (remoteObligations.isNotEmpty()) remote = RemoteRevocation.PENDING
            if (switching) registration = channel?.let { SyntheticRegistration.android(it) }
            phase = if (exhausted) AccountPhase.GENERATION_EXHAUSTED else if (registration == null) AccountPhase.UNAVAILABLE else AccountPhase.LOCAL_SIGNED_OUT
            erasure = LocalErasure.PENDING
            lastFence = AccountFenceEvent(generation, if (exhausted) FenceReason.EXHAUSTION else reason)
            ClearCapture(Any(), generation).also { operation = it.id }
        }
        // Normal operations are already fenced, even while this erase is deferred, offline or failing.
        val erased = VaultImage(processOwner, capture.generation, true, null, Any())
        val gate = AccountCommitGate { atomicInstall ->
            ownerLock.withLock {
                if (generation != capture.generation || operation !== capture.id) reject(AuthRejection.LOCAL_FENCE)
                atomicInstall()
            }
        }
        try { ports!!.vault.transact(gate) { erased } } catch (_: Exception) { /* verify, do not assume */ }
        val readback = try { ports!!.vault.readNormal() } catch (_: Exception) { null }
        return ownerLock.withLock {
            if (generation != capture.generation || operation !== capture.id) return AuthAction.REJECTED
            erasure = if (same(erased, readback)) LocalErasure.VERIFIED else LocalErasure.UNVERIFIED
            operation = null
            if (erasure == LocalErasure.VERIFIED) AuthAction.FENCED else AuthAction.UNCERTAIN
        }
    }

    /** Explicit synthetic retry, separate from refresh; proof never appears in normal vault/status. */
    fun revokeRemote(): AuthAction = revokeLock.withLock {
        val proof = ownerLock.withLock {
            if (!admitted) return AuthAction.UNAVAILABLE
            val held = revokeOnly ?: return if (remote == RemoteRevocation.CONFIRMED) AuthAction.REVOKED else AuthAction.REJECTED
            val time = try { now() } catch (_: Exception) { return AuthAction.UNCERTAIN }
            if (held.generation != generation || held.expiresAt <= time) { revokeOnly = null; return AuthAction.REJECTED }
            held
        }
        try {
            val request = proof.request()
            val reply = ports!!.transport.sendOnce(request)
            reply.correlate(request)
            if (reply.status != 200) {
                val failure = AccountAuthWire.decodeFailure(reply.bytes())
                if (failure.httpStatus != reply.status) reject(AuthRejection.TRANSPORT_UNCERTAIN)
                return AuthAction.UNCERTAIN
            }
            AccountAuthWire.requireRevoked(reply.bytes()) // A 2xx response alone cannot acknowledge revocation.
            ownerLock.withLock {
                if (generation != proof.generation || revokeOnly !== proof || proof.expiresAt <= now()) return AuthAction.REJECTED
                remoteObligations.remove(proof.obligation)
                remote = if (remoteObligations.isEmpty()) RemoteRevocation.CONFIRMED else RemoteRevocation.PENDING
                revokeOnly = null
                AuthAction.REVOKED
            }
        } catch (_: Exception) { AuthAction.UNCERTAIN }
    }
}
