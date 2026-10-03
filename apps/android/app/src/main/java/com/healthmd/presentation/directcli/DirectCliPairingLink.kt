package com.healthmd.presentation.directcli

import java.net.URI

/** A validated, in-app-only handoff from the CLI's universal pairing QR. */
data class DirectCliPairingLink(
    val host: String,
    val port: Int,
    val pairingCode: String,
) {
    companion object {
        const val MAX_PAYLOAD_BYTES = 512
        const val PAIRING_CODE_DIGITS = 20

        fun parse(scannedPayload: String): DirectCliPairingLink? {
            if (scannedPayload.length > MAX_PAYLOAD_BYTES ||
                scannedPayload.any { it.code !in 0x21..0x7e } ||
                '%' in scannedPayload
            ) {
                return null
            }
            val uri = runCatching { URI(scannedPayload) }.getOrNull() ?: return null
            if (uri.scheme != "healthmd" ||
                uri.rawAuthority != "direct-cli" ||
                uri.rawPath != "/pair" ||
                uri.rawFragment != null ||
                uri.rawQuery.isNullOrEmpty()
            ) {
                return null
            }

            val fields = mutableMapOf<String, String>()
            val parts = uri.rawQuery.split('&')
            if (parts.size != 3) return null
            for (part in parts) {
                val separator = part.indexOf('=')
                if (separator <= 0 || separator == part.lastIndex) return null
                val key = part.substring(0, separator)
                val value = part.substring(separator + 1)
                if (key !in setOf("host", "port", "code") || fields.put(key, value) != null) {
                    return null
                }
            }
            if (fields.keys != setOf("host", "port", "code")) return null

            val host = fields.getValue("host")
            val portText = fields.getValue("port")
            val code = fields.getValue("code")
            val port = portText.takeIf { value -> value.all { it in '0'..'9' } }
                ?.toIntOrNull()
                ?.takeIf { it in 1..65_535 }
                ?: return null
            if (!isAllowedPrivateIPv4(host) ||
                code.length != PAIRING_CODE_DIGITS ||
                code.any { it !in '0'..'9' }
            ) {
                return null
            }
            return DirectCliPairingLink(host = host, port = port, pairingCode = code)
        }

        private fun isAllowedPrivateIPv4(host: String): Boolean {
            val parts = host.split('.')
            if (parts.size != 4) return false
            val octets = parts.map { part ->
                if (part.isEmpty() || part.length > 3 ||
                    part.any { it !in '0'..'9' } ||
                    (part.length > 1 && part.first() == '0')
                ) {
                    return false
                }
                part.toIntOrNull()?.takeIf { it in 0..255 } ?: return false
            }
            return octets[0] == 10 ||
                (octets[0] == 172 && octets[1] in 16..31) ||
                (octets[0] == 192 && octets[1] == 168) ||
                (octets[0] == 100 && octets[1] in 64..127)
        }
    }
}
