package com.healthmd.direct

import android.content.Context
import android.os.UserManager
import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeException
import com.healthmd.direct.protocol.AgentBridgePeer
import com.healthmd.direct.protocol.AgentBridgePlatform
import com.healthmd.direct.protocol.DirectSecureChannel
import com.healthmd.direct.protocol.NativeAuthenticatedDirectSession

/** Closed ephemeral lease; not a caller-supplied active flag, wire token, health or approval right. */
internal sealed interface AgentBridgeExportServingEpoch {
    fun requireCurrent(coordinator: DirectCliCoordinator)
}

/** Exact native FGS event seam. The production Service reports successful startForeground FIRST,
 * then ONLY its explicit local ACTION_CONNECT branch opens an operation. Tests may represent those
 * SDK events here without creating/launching a Service. No getter can issue/admit/restart an epoch. */
internal class AgentBridgeExportServingLifecycle(private val coordinator: DirectCliCoordinator) {
    private var admitted = false
    private var stopped = false
    @Volatile private var current: Lease? = null

    @Synchronized fun foregroundAdmitted() {
        check(!stopped && !admitted)
        admitted = true
    }
    @Synchronized fun beginConnectOperation(): AgentBridgeExportServingEpoch? {
        if (!admitted || stopped) return null
        current?.revoke()
        return Lease().also { current = it }
    }
    @Synchronized fun operationEnded(epoch: AgentBridgeExportServingEpoch) {
        if (current === epoch) revokeOperation()
    }
    @Synchronized fun revokeOperation() {
        current?.revoke()
        current = null
    }
    @Synchronized fun stopped() {
        stopped = true
        admitted = false
        revokeOperation()
    }
    private inner class Lease : AgentBridgeExportServingEpoch {
        @Volatile private var revoked = false
        fun revoke() { revoked = true }
        override fun requireCurrent(coordinator: DirectCliCoordinator) {
            if (revoked || current !== this || coordinator !== this@AgentBridgeExportServingLifecycle.coordinator)
                throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        }
        override fun toString() = "AgentBridgeExportServingEpoch(redacted)"
    }
}

/** Only the real coordinator's private accepted base2 owning-channel implementation supplies this.
 * Native role/identity admission, original owning coroutine and serving epoch are distinct from
 * handshake identity. Neither interface can be decoded or persisted. */
internal sealed interface AgentBridgeExportNativeSessionOwner {
    val channel: DirectSecureChannel
    val sourceInstallationId: String
    val hostInstallationId: String
    fun requireCurrent()
}

/** Native identity/liveness ONLY. No extension4 routes, consent, health, entitlement or output rights. */
internal class AgentBridgeExportNativeSession private constructor(private val current: Current) : AgentBridgeExportAuthenticatedPeer() {
    override fun requireCurrent(): AgentBridgePeer = current.requireCurrent()
    fun copy(): AgentBridgeExportNativeSession = AgentBridgeExportNativeSession(current) // SAME revocable checker.
    override fun toString() = "AgentBridgeExportNativeSession(redacted)"

    private class Current(private val context: Context, private val users: UserManager,
        private val owner: AgentBridgeExportNativeSessionOwner, private val proof: NativeAuthenticatedDirectSession,
        private val trust: AgentBridgeExportNativeTrust, private val original: AgentBridgeExportNativeTrust.Snapshot) {
        private var revoked = false
        private val peer = AgentBridgePeer(owner.hostInstallationId, AgentBridgePlatform.ANDROID, owner.sourceInstallationId)

        @Synchronized fun requireCurrent(): AgentBridgePeer {
            try {
                demand(!revoked)
                sample()
                requireOriginalTrust()
                sample() // Native SDK/key/filesystem callbacks may delay/change backing trust too.
                requireOriginalTrust() // Fence that SDK sample with an ORIGINAL-record reread.
                requireLocal() // No further native SDK callback before the local return.
                // Bounded samples are NOT a global SDK/store/socket/time transaction, immediate
                // remote-close detector, privileged snapshot antirollback or already-read recall.
                return peer
            } catch (_: Exception) {
                revoked = true // Observed failure cannot revive through restoration/new same-ID epoch.
                fail()
            }
        }
        private fun requireOriginalTrust() {
            val secret = original.copyReconnectSecret()
            try {
                // Hold ORIGINAL full raw-record/observations/ciphertext snapshot forever.
                // Never load a replacement snapshot to renew/rebind this accepted context.
                trust.requireCurrent(original, owner.sourceInstallationId, owner.hostInstallationId, secret)
            } finally { secret.fill(0) }
        }
        private fun sample() {
            owner.requireCurrent()
            demand(owner.channel.nativeAuthenticatedSession() === proof)
            demand(!context.isDeviceProtectedStorage)
            val latest = context.getSystemService(UserManager::class.java) ?: fail()
            demand(latest === users && latest.isUserUnlocked && users.isUserUnlocked) // BFU, NOT ordinary screen lock.
            requireLocal() // Fresh owner/provenance check AFTER delaying SDK expressions.
        }
        private fun requireLocal() {
            owner.requireCurrent()
            val secret = original.copyReconnectSecret()
            try { demand(proof.matches(owner.channel, owner.sourceInstallationId, owner.hostInstallationId, secret)) }
            finally { secret.fill(0) }
            owner.requireCurrent()
            demand(owner.channel.nativeAuthenticatedSession() === proof)
        }
    }
    companion object {
        internal fun capture(context: Context, owner: AgentBridgeExportNativeSessionOwner): AgentBridgeExportNativeSession = try {
            owner.requireCurrent()
            val proof = owner.channel.nativeAuthenticatedSession() ?: fail() // Before ANY private trust/SDK lookup.
            demand(!context.isDeviceProtectedStorage)
            val users = context.getSystemService(UserManager::class.java) ?: fail()
            demand(users.isUserUnlocked)
            owner.requireCurrent()
            demand(owner.channel.nativeAuthenticatedSession() === proof)
            val trust = AgentBridgeExportNativeTrust(context) // Never construct/call the creating legacy store.
            val original = trust.loadExisting() ?: fail()
            demand(original.sourceInstallationId == owner.sourceInstallationId && original.hostInstallationId == owner.hostInstallationId)
            val secret = original.copyReconnectSecret()
            try { demand(proof.matches(owner.channel, original.sourceInstallationId, original.hostInstallationId, secret)) }
            finally { secret.fill(0) }
            AgentBridgeExportNativeSession(Current(context, users, owner, proof, trust, original)).also { it.requireCurrent() }
        } catch (_: Exception) { fail() } // Fixed sanitized permission_required; no parser/native causes.
        private fun demand(value: Boolean) { if (!value) fail() }
        private fun fail(): Nothing = throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
    }
}
