package com.healthmd.accountauth

/** Disabled source seam only. No value in this package is health or profile authority. */
enum class AuthRejection {
    UNAVAILABLE, MALFORMED_WIRE, BINDING_MISMATCH, INVALID_CALLBACK, INVALID_TRANSITION,
    ENTROPY_UNAVAILABLE, TRANSPORT_UNCERTAIN, VAULT_UNCERTAIN, LOCAL_FENCE, GENERATION_EXHAUSTED,
    CLOCK_ROLLBACK, REQUEST_EXPIRED, LEASE_EXHAUSTED,
}

class AuthSourceException(val rejection: AuthRejection) :
    Exception("Account authorization source rejected: ${rejection.name}")

internal fun reject(reason: AuthRejection): Nothing = throw AuthSourceException(reason)

/** The actual AS02 AuthFailure union; no message or unknown error reflection. */
enum class AuthFailure(val wireName: String, val httpStatus: Int) {
    UNAVAILABLE("unavailable", 503), INVALID_REQUEST("invalid_request", 400),
    INVALID_GRANT("invalid_grant", 400), UNAUTHORIZED("unauthorized", 401),
    FORBIDDEN("forbidden", 403), NOT_FOUND("not_found", 404), RATE_LIMITED("rate_limited", 429),
    VERIFICATION_PENDING("verification_pending", 503), REUSE_FAMILY_REVOKED("reuse_family_revoked", 400),
}

class AuthorizationCode internal constructor(internal val wire: String) {
    override fun toString(): String = "AuthorizationCode(<redacted>)"
}
class AccessToken internal constructor(internal val wire: String) {
    override fun toString(): String = "AccessToken(<redacted>)"
}
class RefreshToken internal constructor(internal val wire: String) {
    override fun toString(): String = "RefreshToken(<redacted>)"
}

/** Partition reference, NOT authority. Deliberately excludes family/client/install identifiers. */
class AccountNamespace internal constructor(
    val issuer: String,
    val environment: String,
    val accountId: String,
) {
    internal fun same(other: AccountNamespace): Boolean =
        issuer == other.issuer && environment == other.environment && accountId == other.accountId
    override fun toString(): String = "AccountNamespace(<redacted metadata>)"
}

/** Immutable parsed DTO. Parsing does not establish transport, attempt, custody or authority. */
class NativeSession internal constructor(
    val tokenType: String,
    val accessToken: AccessToken,
    val expiresIn: Long,
    val refreshToken: RefreshToken,
    val sessionId: String,
    val scope: String,
    val namespace: AccountNamespace,
    val audience: String,
    val clientId: String,
    val installationId: String,
    val sessionGeneration: Long,
) {
    internal fun same(other: NativeSession): Boolean =
        tokenType == other.tokenType && accessToken.wire == other.accessToken.wire &&
            expiresIn == other.expiresIn && refreshToken.wire == other.refreshToken.wire &&
            sessionId == other.sessionId && scope == other.scope && namespace.same(other.namespace) &&
            audience == other.audience && clientId == other.clientId &&
            installationId == other.installationId && sessionGeneration == other.sessionGeneration
    override fun toString(): String = "NativeSession(<redacted>)"
}

enum class AccountPhase {
    UNAVAILABLE, SIGNED_OUT, STARTING, PENDING, EXCHANGING, SIGNED_IN, REFRESHING,
    EXPIRED, AUTHENTICATION_UNCERTAIN, LOCAL_SIGNED_OUT, GENERATION_EXHAUSTED,
}
enum class LocalErasure { NOT_REQUESTED, PENDING, VERIFIED, UNVERIFIED }
enum class RemoteRevocation { NONE, PENDING, CONFIRMED }
enum class AuthAction { UNAVAILABLE, STARTED, INSTALLED, REFRESHED, COALESCED, DENIED, CANCELLED, REJECTED, UNCERTAIN, FENCED, REVOKED }
enum class FenceReason { CANCEL, TIMEOUT, SIGNOUT, SWITCH, EXHAUSTION }

data class AccountFenceEvent(val localGeneration: Long, val reason: FenceReason)

/** Honest nonsecret state only. This does not enable sync or expose any credential. */
class AccountStatus internal constructor(
    val phase: AccountPhase,
    val localGeneration: Long,
    val namespace: AccountNamespace?,
    val clientId: String?,
    val sessionGeneration: Long?,
    val localErasure: LocalErasure,
    val remoteRevocation: RemoteRevocation,
    val lastFence: AccountFenceEvent?,
) {
    val accountOperationsAllowed: Boolean get() = phase == AccountPhase.SIGNED_IN
    override fun toString(): String =
        "AccountStatus(phase=$phase, localErasure=$localErasure, remoteRevocation=$remoteRevocation)"
}
