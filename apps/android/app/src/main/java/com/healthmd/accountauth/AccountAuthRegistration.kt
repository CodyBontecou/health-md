package com.healthmd.accountauth

/** No arbitrary endpoint/environment constructor and no live registration in this source slice. */
class SyntheticRegistration private constructor(val clientId: String, val callback: String) {
    val issuer: String get() = ISSUER
    val environment: String get() = "synthetic"
    val audience: String get() = AUDIENCE
    internal val tokenEndpoint: String get() = "$issuer/api/account-auth/v1/token"
    internal val revokeEndpoint: String get() = "$issuer/api/account-auth/v1/revoke"

    companion object {
        const val ISSUER = "https://account-auth.synthetic.example"
        const val AUDIENCE = "urn:healthmd:account-config:synthetic:v1"
        private val names = setOf("apple-ios", "apple-ipados", "apple-macos", "android-play", "android-fdroid")

        /** All five pinned contexts are admitted to the raw decoder/corpus, not the Android owner. */
        fun forWireTests(clientId: String): SyntheticRegistration {
            val name = clientId.removePrefix("synthetic-")
            if (name !in names || clientId != "synthetic-$name") reject(AuthRejection.UNAVAILABLE)
            return SyntheticRegistration(clientId, "https://callbacks.account-sync.example/$name/return")
        }

        internal fun android(channel: AndroidAuthChannel): SyntheticRegistration = forWireTests(channel.clientId)
    }
    override fun toString(): String = "SyntheticRegistration(disabled synthetic context)"
}

enum class AndroidAuthChannel(internal val clientId: String) {
    PLAY("synthetic-android-play"), FDROID("synthetic-android-fdroid"),
}

class WireContext private constructor(
    val registration: SyntheticRegistration,
    val installationId: String,
    val scope: String,
) {
    companion object {
        fun forSyntheticTests(clientId: String, installationId: String, scope: String): WireContext {
            if (!AccountAuthPKCE.isReference(installationId)) reject(AuthRejection.BINDING_MISMATCH)
            return WireContext(SyntheticRegistration.forWireTests(clientId), installationId, canonicalScope(scope))
        }
    }
    override fun toString(): String = "WireContext(<redacted capture>)"
}

internal fun canonicalScope(scope: String): String {
    val allowed = setOf("account:sessions:read", "account:sessions:revoke:self", "config:profiles:read", "config:profiles:write")
    val parts = scope.split(' ')
    if (parts.isEmpty() || parts.any { it !in allowed } || parts.distinct().sorted().joinToString(" ") != scope ||
        ("config:profiles:write" in parts && "config:profiles:read" !in parts)) {
        reject(AuthRejection.BINDING_MISMATCH)
    }
    return scope
}
