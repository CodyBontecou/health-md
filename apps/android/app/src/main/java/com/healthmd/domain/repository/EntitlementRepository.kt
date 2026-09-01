package com.healthmd.domain.repository

import kotlinx.coroutines.flow.StateFlow

/** Channel-neutral full-access entitlement used by exports, scheduling, automation, and Direct CLI. */
interface EntitlementRepository {
    val isUnlocked: StateFlow<Boolean>

    /** Refreshes channel-backed entitlement state when one exists; a no-op for included access. */
    fun refresh()

    /** Debug-only entitlement override. Implementations must ignore this in non-debug builds. */
    fun debugSetUnlocked(unlocked: Boolean)

    /** Debug-only reset of channel entitlement state. */
    fun debugReset()
}
