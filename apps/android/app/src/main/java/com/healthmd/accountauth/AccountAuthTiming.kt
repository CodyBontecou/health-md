package com.healthmd.accountauth

/**
 * Closed, finite fake-request window. The source owner captures it before dispatch; it is not a
 * response claim or caller-selectable timeout. This models admission/receipt/commit time only:
 * no real network interruption, OS clock provenance, suspend behavior or durability is qualified.
 */
class AuthRequestWindow private constructor(val startedAtSeconds: Long) {
    val timeoutSeconds: Long get() = 5L
    val deadlineAtSeconds: Long = startedAtSeconds + timeoutSeconds

    internal fun requireCurrent(observedAt: Long, leaseExpiresAt: Long? = null) {
        if (observedAt < startedAtSeconds) reject(AuthRejection.CLOCK_ROLLBACK)
        if (observedAt >= deadlineAtSeconds) reject(AuthRejection.REQUEST_EXPIRED)
        if (leaseExpiresAt != null && observedAt >= leaseExpiresAt) reject(AuthRejection.LEASE_EXHAUSTED)
    }

    /** Conservative bound, NEVER arrival/commit time + returned TTL. Equality is exhausted. */
    internal fun leaseBound(expiresIn: Long, observedAt: Long): Long {
        if (expiresIn !in 1L..300L) reject(AuthRejection.BINDING_MISMATCH)
        val bound = startedAtSeconds + expiresIn
        requireCurrent(observedAt, bound)
        return bound
    }

    companion object {
        internal fun capture(startedAtSeconds: Long): AuthRequestWindow {
            if (startedAtSeconds !in 0..AccountAuthWire.MAX_SERVER_GENERATION - 300) reject(AuthRejection.UNAVAILABLE)
            return AuthRequestWindow(startedAtSeconds)
        }
    }
    override fun toString(): String = "AuthRequestWindow(finite synthetic policy, not qualified clock/transport)"
}
