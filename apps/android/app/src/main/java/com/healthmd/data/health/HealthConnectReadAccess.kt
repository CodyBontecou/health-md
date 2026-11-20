package com.healthmd.data.health

/** How much of the requested Health Connect read access the user has granted. */
enum class HealthConnectReadAccessState {
    /** Every requested read permission is granted. */
    ALL,

    /** Some, but not all, requested read permissions are granted. */
    PARTIAL,

    /** No requested read permission is granted. */
    NONE,
}

/**
 * The granted share of the read permissions this app requests from the installed provider.
 * Exports only need one grant ([HealthConnectManager.hasAnyReadPermission]); this is the
 * stricter view the Settings status uses, so "Allowed" means every requested type is readable.
 */
data class HealthConnectReadAccess(
    val requested: Set<String>,
    val granted: Set<String>,
) {
    val grantedCount: Int get() = requested.count { it in granted }

    /** Requested permissions still missing; requesting them grants the rest. */
    val missing: Set<String> get() = requested - granted

    val state: HealthConnectReadAccessState
        get() = when {
            requested.isEmpty() || grantedCount == 0 -> HealthConnectReadAccessState.NONE
            grantedCount == requested.size -> HealthConnectReadAccessState.ALL
            else -> HealthConnectReadAccessState.PARTIAL
        }

    companion object {
        val NONE = HealthConnectReadAccess(emptySet(), emptySet())
    }
}
