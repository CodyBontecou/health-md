package com.healthmd.accountauth

import java.util.concurrent.atomic.AtomicBoolean

/** The process-local owner/receipt identity is synthetic, NOT a durable restoration attestation. */
class VaultSession internal constructor(
    internal val session: NativeSession?,
    internal val localGeneration: Long,
    internal val expiresAt: Long,
    internal val installationBinding: String,
) {
    internal fun same(other: VaultSession): Boolean = localGeneration == other.localGeneration &&
        expiresAt == other.expiresAt && installationBinding == other.installationBinding &&
        session != null && other.session != null && session.same(other.session)
    override fun toString(): String = "VaultSession(<redacted>)"
}

/** Normal compartment only; revocation-only proof is never part of this image or read API. */
class VaultImage internal constructor(
    internal val processOwner: Any,
    internal val localGeneration: Long,
    internal val signedOut: Boolean,
    internal val normal: VaultSession?,
    internal val receipt: Any,
) {
    internal fun same(other: VaultImage): Boolean = processOwner === other.processOwner &&
        receipt === other.receipt && localGeneration == other.localGeneration && signedOut == other.signedOut &&
        ((normal == null && other.normal == null) || (normal != null && other.normal != null && normal.same(other.normal)))
    override fun toString(): String = "VaultImage(<redacted>)"
}

/**
 * One-use SOURCE-owned generation check spanning the authoritative transaction's linearization.
 * The adapter prepares first, then invokes commit exactly once around CAS/change/atomic installation.
 * Returning a success/change count is never proof. This gate is not an OS durability guarantee.
 */
class AccountCommitGate internal constructor(private val ownerCheck: (() -> Unit) -> Unit) {
    private val used = AtomicBoolean(false)
    fun commit(atomicInstall: () -> Unit) {
        if (!used.compareAndSet(false, true)) reject(AuthRejection.LOCAL_FENCE)
        ownerCheck(atomicInstall)
    }
    override fun toString(): String = "AccountCommitGate(source-owned, one-use)"
}

/**
 * Fake-only vault seam. read is fresh/authoritative; transact must not retry the change or gate.
 * Under one exclusive transaction, gate.commit must enclose change AND atomic installation, or roll
 * back all changes. A lost reply may throw after installation; the owner always verifies readback.
 * Preparation may be deferred outside the gate so signout can fence it. No real storage adapter,
 * serialization/retention policy, Keystore, backup exclusion or durable fence is qualified here.
 */
interface SyntheticAccountVault {
    fun readNormal(): VaultImage?
    fun transact(gate: AccountCommitGate, change: (VaultImage?) -> VaultImage)
}

/** Inaccessible-to-refresh/config, in-memory synthetic-only compartment; never restored or exported. */
internal class RevocationOnlyMemory private constructor(
    private val registration: SyntheticRegistration,
    private val refresh: RefreshToken,
    private val installation: String,
    val generation: Long,
    val expiresAt: Long,
    val obligation: Any,
) {
    fun request(): AuthRequestPlan = AuthRequestPlan.revoke(registration, refresh, installation)
    override fun toString(): String = "RevocationOnlyMemory(<redacted>, memory-only)"
    companion object {
        fun capture(registration: SyntheticRegistration, record: VaultSession, generation: Long, obligation: Any): RevocationOnlyMemory {
            val session = record.session ?: reject(AuthRejection.VAULT_UNCERTAIN)
            // Deliberately no persistent retention promise; synthetic proof expires with held access TTL.
            return RevocationOnlyMemory(registration, session.refreshToken, session.installationId, generation, record.expiresAt, obligation)
        }
    }
}
