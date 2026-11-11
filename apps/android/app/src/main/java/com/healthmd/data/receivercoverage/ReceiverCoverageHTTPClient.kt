package com.healthmd.data.receivercoverage

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Authenticator
import okhttp3.Call
import okhttp3.Callback
import okhttp3.CookieJar
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/** Dedicated read-only preflight; never reuse an upload client's redirects/interceptors/credentials. */
class ReceiverCoverageHTTPClient internal constructor(
    private val calls: Call.Factory = isolatedClient(),
    private val deadlineMillis: Long = ReceiverCoveragePreflight.DEADLINE_SECONDS * 1000L,
) {
    init { require(deadlineMillis in 1..ReceiverCoveragePreflight.DEADLINE_SECONDS * 1000L) }

    suspend fun query(request: ReceiverCoverageRequest): ReceiverCoverageOutcome {
        currentCoroutineContext().ensureActive()
        val started = System.nanoTime()
        val outcome = try {
            withTimeoutOrNull(deadlineMillis) {
                val wire = Request.Builder().url(request.url.toASCIIString())
                    .post(request.body().toRequestBody("application/json".toMediaType()))
                    .apply { request.headers().forEach { (name, value) -> header(name, value) } }
                    .build()
                val bytes = exchange(wire)
                currentCoroutineContext().ensureActive()
                val evidence = ReceiverCoverageEvidence.parse(bytes, request)
                currentCoroutineContext().ensureActive()
                if (System.nanoTime() - started >= TimeUnit.MILLISECONDS.toNanos(deadlineMillis)) {
                    ReceiverCoverageOutcome.FallbackFull
                } else ReceiverCoverageOutcome.Valid(evidence)
            } ?: ReceiverCoverageOutcome.FallbackFull
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            ReceiverCoverageOutcome.FallbackFull
        }
        // An external cancellation racing timeout/EOF/invalid JSON must never trigger an upload.
        currentCoroutineContext().ensureActive()
        return outcome
    }

    private suspend fun exchange(request: Request): ByteArray = suspendCancellableCoroutine { continuation ->
        val call = calls.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        if (!continuation.isActive) return@suspendCancellableCoroutine
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                // Do not propagate native errors containing URLs/credentials/server body text.
                continuation.resumeWithException(ReceiverCoveragePreflight.BoundaryException())
            }
            override fun onResponse(call: Call, response: Response) {
                try {
                    val bytes = response.use {
                        if (it.request.url != request.url || it.priorResponse != null) {
                            throw ReceiverCoveragePreflight.BoundaryException()
                        }
                        val buffer = ReceiverCoverageResponseBuffer(it.code, it.header("Content-Type"))
                        val body = it.body ?: throw ReceiverCoveragePreflight.BoundaryException()
                        if (body.contentLength() > ReceiverCoveragePreflight.MAXIMUM_RESPONSE_BYTES) {
                            throw ReceiverCoveragePreflight.BoundaryException()
                        }
                        body.byteStream().use { stream ->
                            val chunk = ByteArray(4096)
                            while (true) {
                                if (!continuation.isActive) throw ReceiverCoveragePreflight.BoundaryException()
                                val count = stream.read(chunk)
                                if (count < 0) break
                                buffer.append(chunk.copyOf(count))
                            }
                        }
                        buffer.finish()
                    }
                    continuation.resume(bytes)
                } catch (_: Exception) {
                    // Cancel remaining stream immediately on cap/metadata/read failure. No retries.
                    call.cancel()
                    continuation.resumeWithException(ReceiverCoveragePreflight.BoundaryException())
                }
            }
        })
    }

    companion object {
        internal fun isolatedClient(): OkHttpClient = OkHttpClient.Builder()
            .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false)
            .authenticator(Authenticator.NONE).proxyAuthenticator(Authenticator.NONE)
            .cookieJar(CookieJar.NO_COOKIES).cache(null)
            .callTimeout(ReceiverCoveragePreflight.DEADLINE_SECONDS.toLong(), TimeUnit.SECONDS)
            .build()
    }
}
