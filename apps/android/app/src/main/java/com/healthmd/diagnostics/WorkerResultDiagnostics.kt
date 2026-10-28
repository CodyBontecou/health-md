package com.healthmd.diagnostics

import androidx.work.ListenableWorker

/** Public factory equality preserves outcomes even when output data is present.
 * The data is compared only; it is never included in diagnostic fields.
 */
internal fun ListenableWorker.Result.diagnosticOutcome(): String = when (this) {
    ListenableWorker.Result.success(outputData) -> "success"
    ListenableWorker.Result.failure(outputData) -> "failure"
    ListenableWorker.Result.retry() -> "retry"
    else -> "unknown"
}
