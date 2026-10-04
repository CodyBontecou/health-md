package com.healthmd.accountauth

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/** Closed raw UTF-8 response grammar, not a JSON.parse/map prepass or a trusted transport. */
object AccountAuthWire {
    const val BODY_BYTES = 8192
    const val MAX_SERVER_GENERATION = 9007199254740991L
    private val successKeys = setOf("token_type", "access_token", "expires_in", "refresh_token", "session_id", "scope",
        "issuer", "environment", "audience", "client_id", "installation_id", "account_id", "session_generation")
    private val accountShape = Regex("(?:[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}|synthetic-account-[a-z0-9]{1,32})")

    fun decodeSession(bytes: ByteArray, context: WireContext): NativeSession {
        val v = ClosedObject(bytes, successKeys).parse()
        fun text(key: String): String = (v[key] as? Scalar.Text)?.value ?: reject(AuthRejection.MALFORMED_WIRE)
        fun number(key: String): Long = (v[key] as? Scalar.Integer)?.value ?: reject(AuthRejection.MALFORMED_WIRE)
        val registration = context.registration
        val access = text("access_token")
        val refresh = text("refresh_token")
        val ttl = number("expires_in")
        val family = text("session_id")
        val account = text("account_id")
        val generation = number("session_generation")
        if (text("token_type") != "Bearer" || !AccountAuthPKCE.isToken(access, "hmd_nac_") ||
            !AccountAuthPKCE.isToken(refresh, "hmd_nrf_") || !AccountAuthPKCE.isReference(family) ||
            !accountShape.matches(account) || ttl !in 1L..300L) reject(AuthRejection.BINDING_MISMATCH)
        if (text("issuer") != registration.issuer || text("environment") != registration.environment ||
            text("audience") != registration.audience || text("client_id") != registration.clientId ||
            text("installation_id") != context.installationId || text("scope") != context.scope ||
            canonicalScope(text("scope")) != context.scope) reject(AuthRejection.BINDING_MISMATCH)
        return NativeSession("Bearer", AccessToken(access), ttl, RefreshToken(refresh), family, context.scope,
            AccountNamespace(registration.issuer, registration.environment, account), registration.audience,
            registration.clientId, context.installationId, generation)
    }

    fun decodeFailure(bytes: ByteArray): AuthFailure {
        val value = (ClosedObject(bytes, setOf("error")).parse()["error"] as? Scalar.Text)?.value
            ?: reject(AuthRejection.MALFORMED_WIRE)
        return AuthFailure.entries.firstOrNull { it.wireName == value } ?: reject(AuthRejection.MALFORMED_WIRE)
    }

    internal fun requireRevoked(bytes: ByteArray) {
        if ((ClosedObject(bytes, setOf("revoked")).parse()["revoked"] as? Scalar.Truth)?.value != true) {
            reject(AuthRejection.MALFORMED_WIRE)
        }
    }

    internal fun requireInitial(session: NativeSession) {
        if (session.sessionGeneration != 0L) reject(AuthRejection.INVALID_TRANSITION)
    }

    internal fun requireRefresh(previous: NativeSession, replacement: NativeSession) {
        if (previous.sessionGeneration == MAX_SERVER_GENERATION) reject(AuthRejection.GENERATION_EXHAUSTED)
        if (!previous.namespace.same(replacement.namespace) || previous.audience != replacement.audience ||
            previous.clientId != replacement.clientId || previous.installationId != replacement.installationId ||
            previous.sessionId != replacement.sessionId || previous.scope != replacement.scope ||
            replacement.sessionGeneration != previous.sessionGeneration + 1 ||
            previous.refreshToken.wire == replacement.refreshToken.wire || previous.accessToken.wire == replacement.accessToken.wire) {
            reject(AuthRejection.INVALID_TRANSITION)
        }
    }

    private sealed interface Scalar {
        class Text(val value: String) : Scalar
        class Integer(val value: Long) : Scalar
        class Truth(val value: Boolean) : Scalar
    }

    private class ClosedObject(bytes: ByteArray, private val keys: Set<String>) {
        private val text: String
        private var pos = 0
        init {
            if (bytes.isEmpty() || bytes.size > BODY_BYTES) bad()
            text = try {
                StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
            } catch (_: CharacterCodingException) { bad() }
            if (text.startsWith('\uFEFF')) bad()
        }
        private fun bad(): Nothing = reject(AuthRejection.MALFORMED_WIRE)
        private fun peek(): Char? = text.getOrNull(pos)
        private fun take(wanted: Char) { if (peek() != wanted) bad(); pos++ }
        private fun spaces() { while (peek() in listOf(' ', '\t', '\r', '\n')) pos++ }

        fun parse(): Map<String, Scalar> {
            spaces(); take('{'); spaces()
            val result = LinkedHashMap<String, Scalar>()
            if (peek() != '}') {
                while (true) {
                    val key = string()
                    // Compare DECODED keys before map insertion; escaped aliases cannot overwrite.
                    if (key !in keys || result.containsKey(key) || result.size >= keys.size) bad()
                    spaces(); take(':'); spaces()
                    val value = when (peek()) {
                        '"' -> Scalar.Text(string())
                        in '0'..'9' -> Scalar.Integer(integer())
                        't' -> { literal("true"); Scalar.Truth(true) }
                        'f' -> { literal("false"); Scalar.Truth(false) }
                        else -> bad() // no null, nested object/array, sign, fraction or exponent
                    }
                    result[key] = value
                    spaces()
                    if (peek() == '}') break
                    take(','); spaces()
                }
            }
            take('}'); spaces()
            if (pos != text.length || result.keys != keys) bad()
            return result
        }

        private fun literal(value: String) {
            if (!text.startsWith(value, pos)) bad()
            pos += value.length
        }
        private fun integer(): Long {
            val start = pos
            if (peek() == '0') pos++ else while (peek() in '0'..'9') pos++
            val value = text.substring(start, pos).toLongOrNull() ?: bad()
            if (value !in 0..MAX_SERVER_GENERATION) bad()
            return value // delimiters checked by parse; 00, 0.0, 0e0, +0 and -0 all deny
        }
        private fun hexUnit(): Char {
            if (pos + 4 > text.length) bad()
            val digits = text.substring(pos, pos + 4)
            if (digits.any { it !in '0'..'9' && it !in 'a'..'f' && it !in 'A'..'F' }) bad()
            pos += 4
            return digits.toInt(16).toChar()
        }
        private fun string(): String {
            take('"')
            val result = StringBuilder()
            while (true) {
                val ch = peek() ?: bad()
                pos++
                if (ch == '"') return result.toString()
                val decoded = if (ch == '\\') {
                    val escaped = peek() ?: bad()
                    pos++
                    when (escaped) {
                        '"', '\\', '/' -> escaped
                        'b' -> '\b'; 'f' -> '\u000C'; 'n' -> '\n'; 'r' -> '\r'; 't' -> '\t'
                        'u' -> hexUnit()
                        else -> bad()
                    }
                } else ch
                if (decoded.code <= 0x1f || decoded.code in 0x7f..0x9f) bad()
                if (decoded.isHighSurrogate()) {
                    val low = if (ch == '\\') { take('\\'); take('u'); hexUnit() } else {
                        val next = peek() ?: bad(); pos++; next
                    }
                    if (!low.isLowSurrogate()) bad()
                    result.append(decoded).append(low)
                } else {
                    if (decoded.isLowSurrogate()) bad()
                    result.append(decoded)
                }
                if (result.length > 4096) bad()
            }
        }
    }
}
