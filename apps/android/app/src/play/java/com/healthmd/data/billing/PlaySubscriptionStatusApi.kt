package com.healthmd.data.billing

import com.healthmd.domain.billing.PlaySubscriptionVerifier
import com.healthmd.domain.billing.VerifiedPlaySubscription
import java.io.IOException
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import timber.log.Timber

/**
 * Reads one Health.md subscription's paid-period end from myself.md, which asks Google Play
 * (`purchases.subscriptionsv2.get`) with the owner's service account. Only the purchase token is
 * sent; it is never logged. Any failure returns null and the screen keeps "Shown in Google Play".
 */
class PlaySubscriptionStatusApi(
    client: OkHttpClient = OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).build(),
    private val origin: HttpUrl = "https://myself.md/".toHttpUrl(),
) : PlaySubscriptionVerifier {
    private val http = client.newBuilder().followRedirects(false).followSslRedirects(false).build()

    init {
        require(origin.isHttps && origin.encodedPath == "/" && origin.query == null && origin.fragment == null)
    }

    override suspend fun verify(purchaseToken: String): VerifiedPlaySubscription? {
        if (purchaseToken.isBlank() || purchaseToken.length > MAX_TOKEN) return null
        return try {
            withContext(Dispatchers.IO) { request(purchaseToken) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            Timber.w("Subscription date unavailable: %s", error.javaClass.simpleName)
            null
        }
    }

    private suspend fun request(purchaseToken: String): VerifiedPlaySubscription? {
        val payload = buildJsonObject { put("purchaseToken", purchaseToken) }
        val request = Request.Builder().url(origin.resolve(PATH)!!)
            .post(payload.toString().toRequestBody("application/json".toMediaType())).build()
        val call = http.newCall(request)
        val response = suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }
                override fun onResponse(call: Call, response: Response) {
                    continuation.resume(response) { _, value, _ -> value.close() }
                }
            })
        }
        return response.use {
            if (it.request.url != request.url || it.code != 200) return@use null
            val source = it.body?.source() ?: return@use null
            source.request(MAX_RESPONSE + 1L)
            if (source.buffer.size > MAX_RESPONSE) return@use null
            parse(source.readUtf8())
        }
    }

    internal fun parse(body: String): VerifiedPlaySubscription? {
        val json = runCatching { Json.parseToJsonElement(body).jsonObject }.getOrNull() ?: return null
        val productId = (json["productId"] as? JsonPrimitive)?.contentOrNull ?: return null
        val state = (json["state"] as? JsonPrimitive)?.contentOrNull ?: return null
        val expires = (json["expiresAt"] as? JsonPrimitive)?.contentOrNull
            ?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
        val autoRenewing = (json["autoRenewing"] as? JsonPrimitive)?.booleanOrNull ?: false
        return VerifiedPlaySubscription(productId, state, expires, autoRenewing)
    }

    private companion object {
        const val PATH = "api/health-md/play-subscription"
        const val MAX_TOKEN = 30_000
        const val MAX_RESPONSE = 4_000
    }
}
