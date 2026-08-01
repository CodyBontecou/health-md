package com.healthmd.util

import kotlinx.coroutines.CancellationException

/** Like [runCatching], but never converts structured-concurrency cancellation into a failure. */
inline fun <T> runCatchingCancellable(block: () -> T): Result<T> = try {
    Result.success(block())
} catch (error: CancellationException) {
    throw error
} catch (error: Throwable) {
    Result.failure(error)
}
