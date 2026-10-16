package com.healthmd.effecthostcandidate

import android.content.Context
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import androidx.work.Data
import androidx.concurrent.futures.CallbackToFutureAdapter
import com.google.common.util.concurrent.ListenableFuture

/** WorkManager alone invokes startWork; a cancelled Future is never cleanup acknowledgment. */
class ColdProbeWorker(context: Context, parameters: WorkerParameters) : ListenableWorker(context, parameters) {
    override fun startWork(): ListenableFuture<Result> = CallbackToFutureAdapter.getFuture { completer ->
        if (isStopped) ColdRegistry.stop(id.toString())
        ColdRegistry.start(id.toString(), inputData) { raw, ready ->
            val output = if (raw == null) Data.EMPTY else Data.Builder().putString("result_payload", raw).build()
            completer.set(if (ready) Result.success(output) else Result.failure(output))
        }
        "healthmd-private-cold-worker"
    }
    override fun onStopped() {
        // Lightweight signal only; separate native journal completion happens after release ACK.
        ColdRegistry.stop(id.toString())
    }
}
