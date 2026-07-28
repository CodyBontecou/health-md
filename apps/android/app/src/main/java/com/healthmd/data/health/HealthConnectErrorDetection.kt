package com.healthmd.data.health

internal fun Throwable.isLikelyHealthConnectRateLimit(): Boolean =
    generateSequence(this) { it.cause }.any { throwable ->
        val className = throwable::class.java.name.lowercase()
        val message = throwable.message.orEmpty().lowercase()

        className.contains("ratelimit") ||
            className.contains("rate_limit") ||
            message.contains("rate limit") ||
            message.contains("ratelimit") ||
            message.contains("rate_limit") ||
            message.contains("quota") ||
            message.contains("too many requests")
    }
