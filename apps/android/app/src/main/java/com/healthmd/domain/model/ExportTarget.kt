package com.healthmd.domain.model

import kotlinx.serialization.Serializable
import java.net.URI
import java.security.MessageDigest

/** A destination that can receive a manual or scheduled Health.md export. */
@Serializable
enum class ExportTarget {
    DEVICE_FOLDER,
    API_ENDPOINT,
}

/** Validation and privacy-safe display helpers for user-configured API destinations. */
object APIExportEndpoint {
    fun normalizedOrNull(value: String): String? {
        val trimmed = value.trim()
        if (trimmed.isEmpty() || trimmed.contains('\r') || trimmed.contains('\n')) return null

        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        if (!uri.scheme.equals("https", ignoreCase = true) &&
            !uri.scheme.equals("http", ignoreCase = true)
        ) return null
        if (uri.host.isNullOrBlank()) return null
        if (uri.rawUserInfo != null || uri.rawFragment != null) return null

        return uri.normalize().toASCIIString()
    }

    fun isConfigured(value: String): Boolean = normalizedOrNull(value) != null

    fun displayName(value: String): String =
        normalizedOrNull(value)?.let { URI(it).host } ?: "Configure endpoint"

    /** Stable comparison value that never persists the endpoint or its query parameters. */
    fun fingerprint(value: String): String? = normalizedOrNull(value)?.let { normalized ->
        MessageDigest.getInstance("SHA-256")
            .digest(normalized.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    /** Removes query parameters and fragments so secrets embedded in URLs are never shown or logged. */
    fun redactedDescription(value: String): String {
        val normalized = normalizedOrNull(value) ?: return "No endpoint configured"
        val uri = URI(normalized)
        return runCatching {
            URI(uri.scheme, null, uri.host, uri.port, uri.path.ifBlank { null }, null, null).toASCIIString()
        }.getOrDefault("${uri.scheme}://${uri.host}")
    }
}

object ExportTargetReadiness {
    fun canExport(
        hasHealthPermissions: Boolean,
        historicalPermissionNeeded: Boolean,
        hasSelectedFormat: Boolean,
        target: ExportTarget,
        hasExportFolder: Boolean,
        apiEndpointConfigured: Boolean,
    ): Boolean {
        if (!hasHealthPermissions || historicalPermissionNeeded || !hasSelectedFormat) return false
        return when (target) {
            ExportTarget.DEVICE_FOLDER -> hasExportFolder
            ExportTarget.API_ENDPOINT -> apiEndpointConfigured
        }
    }
}
