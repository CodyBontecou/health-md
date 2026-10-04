package com.healthmd.accountauth

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

sealed interface CallbackResult {
    class Code internal constructor(val code: AuthorizationCode) : CallbackResult {
        override fun toString(): String = "CallbackResult.Code(<redacted>)"
    }
    data object Denied : CallbackResult
}

/** Pure raw receiver. Pending/current-generation ownership is separately enforced by the coordinator. */
object AccountAuthCallback {
    const val URI_BYTES = 4096

    fun decode(raw: ByteArray, registration: SyntheticRegistration, expectedState: String): CallbackResult {
        fun bad(): Nothing = reject(AuthRejection.INVALID_CALLBACK)
        if (raw.isEmpty() || raw.size > URI_BYTES || !AccountAuthPKCE.isReference(expectedState)) bad()
        val text = try {
            StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(raw)).toString()
        } catch (_: CharacterCodingException) { bad() }
        // Exact ASCII literal base BEFORE URI/URL normalization. No percent aliases or decoding at all.
        if (text.any { it.code !in 0x21..0x7e || it == '%' || it == '#' }) bad()
        val parts = text.split('?')
        if (parts.size != 2 || parts[0] != registration.callback) bad()
        val values = LinkedHashMap<String, String>()
        for (pair in parts[1].split('&')) {
            val fields = pair.split('=')
            if (fields.size != 2 || fields[0] !in setOf("code", "error", "state", "iss") ||
                values.containsKey(fields[0])) bad()
            values[fields[0]] = fields[1]
        }
        if (values["state"] != expectedState || values["iss"] != registration.issuer) bad()
        if (values.keys == setOf("error", "state", "iss") && values["error"] == "access_denied") return CallbackResult.Denied
        if (values.keys != setOf("code", "state", "iss")) bad()
        val code = values["code"] ?: bad()
        if (!AccountAuthPKCE.isToken(code, "hmd_acode_")) bad()
        return CallbackResult.Code(AuthorizationCode(code))
    }
}
