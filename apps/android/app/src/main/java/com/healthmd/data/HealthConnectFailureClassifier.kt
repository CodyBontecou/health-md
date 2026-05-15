package com.healthmd.data

internal fun Throwable.isHealthConnectRateLimit(): Boolean {
    var current: Throwable? = this
    var depth = 0
    while (current != null && depth < 8) {
        if (current.isPlatformHealthConnectRateLimit()) return true
        val text = listOfNotNull(
            current.message,
            current.localizedMessage,
            current::class.java.name,
        ).joinToString(separator = " ")
        if (
            text.contains("rate", ignoreCase = true) &&
            text.contains("limit", ignoreCase = true)
        ) {
            return true
        }
        current = current.cause
        depth++
    }
    return false
}

private fun Throwable.isPlatformHealthConnectRateLimit(): Boolean {
    if (this::class.java.name != "android.health.connect.HealthConnectException") return false
    val errorCode = runCatching {
        this::class.java.getMethod("getErrorCode").invoke(this) as? Int
    }.getOrNull()
    return errorCode == 7
}
