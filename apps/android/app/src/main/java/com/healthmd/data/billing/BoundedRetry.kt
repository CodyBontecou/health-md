package com.healthmd.data.billing

internal suspend fun <T> executeBoundedRetry(
    maxAttempts: Int,
    retryDelayMillis: (failedAttempt: Int) -> Long,
    shouldRetry: (T) -> Boolean,
    sleep: suspend (delayMillis: Long) -> Unit,
    onRetry: (result: T, failedAttempt: Int, delayMillis: Long) -> Unit = { _, _, _ -> },
    operation: suspend () -> T,
): T {
    require(maxAttempts >= 1)

    var attempt = 1
    var result = operation()
    while (attempt < maxAttempts && shouldRetry(result)) {
        val delayMillis = retryDelayMillis(attempt)
        onRetry(result, attempt, delayMillis)
        sleep(delayMillis)
        attempt++
        result = operation()
    }
    return result
}
