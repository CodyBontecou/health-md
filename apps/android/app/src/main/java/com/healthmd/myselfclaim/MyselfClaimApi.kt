package com.healthmd.myselfclaim

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
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
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException

/** Fixed production origin. Alternate HTTPS origins exist only for injected test clients. */
class MyselfClaimApi(
    client: OkHttpClient = OkHttpClient.Builder()
        .followRedirects(false).followSslRedirects(false)
        .callTimeout(30, TimeUnit.SECONDS).build(),
    private val origin: HttpUrl = "https://myself.md/".toHttpUrl(),
) : MyselfClaimVerifier {
    private val http = client.newBuilder().followRedirects(false).followSslRedirects(false).build()

    init {
        require(origin.isHttps && origin.encodedPath == "/" && origin.query == null &&
            origin.fragment == null && origin.username.isEmpty() && origin.password.isEmpty())
    }

    override suspend fun verify(purchaseToken: String): String = withContext(Dispatchers.IO) {
        if (purchaseToken.isBlank() || purchaseToken.length > 30_000) fail()
        val payload = buildJsonObject {
            put("app", "health.md")
            put("store", "android")
            put("kind", "iap")
            put("proof", purchaseToken)
        }
        val request = Request.Builder().url(origin.resolve("api/migration/proof")!!)
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
        response.use {
            // Never follow redirects, even if an injected client enables them.
            if (it.request.url != request.url || it.code != 200) fail()
            val source = it.body?.source() ?: fail()
            source.request(40_001)
            if (source.buffer.size > 40_000) fail()
            val result = Json.parseToJsonElement(source.readUtf8()).jsonObject
            val raw = result["claimUrl"]?.jsonPrimitive?.content ?: fail()
            validateClaimUrl(raw)
        }
    }

    internal fun validateClaimUrl(raw: String): String {
        val url = runCatching { raw.toHttpUrl() }.getOrElse { fail() }
        if (url.scheme != origin.scheme || url.host != origin.host || url.port != origin.port ||
            url.username.isNotEmpty() || url.password.isNotEmpty() ||
            url.encodedPath != "/claim" || url.query != null ||
            url.encodedFragment?.matches(Regex("[A-Za-z0-9_-]{43}")) != true) fail()
        return url.toString()
    }

    private fun fail(): Nothing = throw MyselfClaimException(MyselfClaimFailure.VERIFICATION_FAILED)
}
