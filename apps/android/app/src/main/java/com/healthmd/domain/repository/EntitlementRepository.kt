package com.healthmd.domain.repository

import kotlinx.coroutines.flow.StateFlow

/** Channel-neutral full-access entitlement used by exports, scheduling, automation, and Direct CLI. */
interface EntitlementRepository {
    val isUnlocked: StateFlow<Boolean>

    /** Only permanent access may be persisted as the legacy isPurchased flag. */
    val isPermanentlyUnlocked: StateFlow<Boolean> get() = isUnlocked

    /** Fresh admission check for headless work; subscriptions are never cached forever. */
    suspend fun verifyAccess(): Boolean = isUnlocked.value

    /** Refreshes channel-backed entitlement state when one exists; a no-op for included access. */
    fun refresh()

    /** Debug-only entitlement override. Implementations must ignore this in non-debug builds. */
    fun debugSetUnlocked(unlocked: Boolean)

    /** Debug-only reset of channel entitlement state. */
    fun debugReset()
}
