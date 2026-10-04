package com.healthmd.accountauth

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Collections
import java.util.Locale

/** Synthetic plans are not a system-browser consent implementation. AS02 GET is JSON review metadata. */
class AuthorizationPlan internal constructor(internal val rawUrl: String) {
    override fun toString(): String = "AuthorizationPlan(<redacted>)"
}
fun interface SyntheticConsentPort { fun reviewOnly(plan: AuthorizationPlan) }

internal fun authorizationPlan(registration: SyntheticRegistration, scope: String, secrets: AttemptSecrets): AuthorizationPlan {
    fun escape(value: String): String = URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")
    val fields = linkedMapOf("client_id" to registration.clientId, "redirect_uri" to registration.callback,
        "response_type" to "code", "scope" to canonicalScope(scope), "state" to secrets.state,
        "code_challenge" to secrets.challenge, "code_challenge_method" to "S256", "audience" to registration.audience)
    val url = "${registration.issuer}/account/authorize?" + fields.entries.joinToString("&") { "${it.key}=${escape(it.value)}" }
    if (url.toByteArray(StandardCharsets.UTF_8).size > AccountAuthCallback.URI_BYTES) reject(AuthRejection.INVALID_TRANSITION)
    return AuthorizationPlan(url)
}

enum class AuthRequestKind { CODE, REFRESH, REVOKE }

/** Only pinned TLS JSON POSTs. There is no arbitrary URL/body/header constructor. */
class AuthRequestPlan private constructor(
    val kind: AuthRequestKind,
    val url: String,
    private val body: ByteArray,
) {
    val method: String get() = "POST"
    val headers: Map<String, String> = Collections.unmodifiableMap(linkedMapOf("Content-Type" to "application/json", "Accept" to "application/json"))
    val allowRedirects: Boolean get() = false
    val allowCookies: Boolean get() = false
    val transparentRetries: Int get() = 0
    val responseByteLimit: Int get() = AccountAuthWire.BODY_BYTES
    fun bodyBytes(): ByteArray = body.copyOf()
    override fun toString(): String = "AuthRequestPlan(kind=$kind, body=<redacted>)"

    companion object {
        private fun create(kind: AuthRequestKind, registration: SyntheticRegistration, fields: Map<String, String>): AuthRequestPlan {
            // All outbound fields use this finite ASCII subset; no caller JSON, override, cookie or bearer.
            if (fields.values.any { value -> value.any { it.code !in 0x20..0x7e || it == '"' || it == '\\' } }) {
                reject(AuthRejection.INVALID_TRANSITION)
            }
            val bytes = fields.entries.joinToString(",", "{", "}") { "\"${it.key}\":\"${it.value}\"" }.toByteArray(StandardCharsets.UTF_8)
            if (bytes.size > AccountAuthWire.BODY_BYTES) reject(AuthRejection.INVALID_TRANSITION)
            return AuthRequestPlan(kind, if (kind == AuthRequestKind.REVOKE) registration.revokeEndpoint else registration.tokenEndpoint, bytes)
        }
        internal fun code(registration: SyntheticRegistration, code: AuthorizationCode, secrets: AttemptSecrets): AuthRequestPlan {
            if (!AccountAuthPKCE.isToken(code.wire, "hmd_acode_") || !AccountAuthPKCE.isReference(secrets.installationId)) reject(AuthRejection.INVALID_TRANSITION)
            AccountAuthPKCE.s256(secrets.verifier)
            return create(AuthRequestKind.CODE, registration, linkedMapOf("grant_type" to "authorization_code",
                "client_id" to registration.clientId, "redirect_uri" to registration.callback, "code" to code.wire,
                "code_verifier" to secrets.verifier, "installation_id" to secrets.installationId))
        }
        internal fun refresh(registration: SyntheticRegistration, session: NativeSession): AuthRequestPlan {
            if (session.clientId != registration.clientId || !AccountAuthPKCE.isToken(session.refreshToken.wire, "hmd_nrf_") ||
                !AccountAuthPKCE.isReference(session.installationId)) reject(AuthRejection.INVALID_TRANSITION)
            return create(AuthRequestKind.REFRESH, registration, linkedMapOf("grant_type" to "refresh_token",
                "client_id" to registration.clientId, "installation_id" to session.installationId, "refresh_token" to session.refreshToken.wire))
        }
        internal fun revoke(registration: SyntheticRegistration, refresh: RefreshToken, installationId: String): AuthRequestPlan {
            if (!AccountAuthPKCE.isToken(refresh.wire, "hmd_nrf_") || !AccountAuthPKCE.isReference(installationId)) reject(AuthRejection.INVALID_TRANSITION)
            return create(AuthRequestKind.REVOKE, registration, linkedMapOf("refresh_token" to refresh.wire,
                "client_id" to registration.clientId, "installation_id" to installationId))
        }
    }
}

/** Fake-only transport observation, explicitly NOT real TLS provenance or a flag decoded from JSON. */
class SyntheticReply(
    internal val request: AuthRequestPlan,
    internal val finalUrl: String,
    internal val status: Int,
    bytes: ByteArray,
    headers: List<Pair<String, String>> = sourceJsonHeaders(),
    internal val redirectHops: Int = 0,
) {
    private val body = bytes.copyOf()
    private val receivedHeaders = headers.toList() // preserve duplicates until checked, not a lossy map
    internal fun bytes(): ByteArray = body.copyOf()
    internal fun correlate(plan: AuthRequestPlan) {
        if (request !== plan || finalUrl != plan.url || redirectHops != 0 || body.isEmpty() ||
            body.size > plan.responseByteLimit) reject(AuthRejection.TRANSPORT_UNCERTAIN)
        if (receivedHeaders.size > 16 || receivedHeaders.sumOf { it.first.length + it.second.length } > 4096) reject(AuthRejection.TRANSPORT_UNCERTAIN)
        val values = LinkedHashMap<String, String>()
        for ((key, value) in receivedHeaders) {
            if (!Regex("[A-Za-z0-9-]{1,64}").matches(key) || value.length > 1024 || value.any { it.code !in 0x20..0x7e }) reject(AuthRejection.TRANSPORT_UNCERTAIN)
            val name = key.lowercase(Locale.ROOT)
            if (name in values || name in setOf("cookie", "set-cookie", "authorization", "proxy-authorization")) reject(AuthRejection.TRANSPORT_UNCERTAIN)
            values[name] = value
        }
        // Pinned to own committed Cloud JSON_HEADERS, plus explicit bare JSON source-test form.
        if (values["content-type"] !in setOf("application/json", "application/json; charset=utf-8") ||
            values["cache-control"] != "no-store" || values["referrer-policy"] != "no-referrer") reject(AuthRejection.TRANSPORT_UNCERTAIN)
    }
    companion object {
        internal fun sourceJsonHeaders(): List<Pair<String, String>> = listOf(
            "Content-Type" to "application/json; charset=utf-8", "Cache-Control" to "no-store",
            "Referrer-Policy" to "no-referrer", "X-Content-Type-Options" to "nosniff")
    }
    override fun toString(): String = "SyntheticReply(<redacted>, not qualified transport)"
}

/** Must send exactly once, with no cookies/authenticator/logging/redirect/replay. Only test fakes admitted. */
fun interface SyntheticAuthTransport { fun sendOnce(plan: AuthRequestPlan): SyntheticReply }

internal sealed interface TokenReply {
    class Session(val value: NativeSession) : TokenReply
    class Failure(val value: AuthFailure) : TokenReply
}
internal fun tokenReply(transport: SyntheticAuthTransport, plan: AuthRequestPlan, context: WireContext): TokenReply {
    val reply = transport.sendOnce(plan)
    reply.correlate(plan)
    if (reply.status == 200) return TokenReply.Session(AccountAuthWire.decodeSession(reply.bytes(), context))
    val failure = AccountAuthWire.decodeFailure(reply.bytes())
    if (reply.status != failure.httpStatus) reject(AuthRejection.TRANSPORT_UNCERTAIN)
    return TokenReply.Failure(failure)
}
