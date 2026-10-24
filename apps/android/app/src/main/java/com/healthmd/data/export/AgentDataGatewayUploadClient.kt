package com.healthmd.data.export

import com.healthmd.domain.model.AgentDataGatewayEndpoint
import com.healthmd.domain.model.AgentDataRejectionCodes
import java.io.IOException
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import kotlin.coroutines.coroutineContext

/** One answered gateway upload: every validated protocol outcome is an HTTP 2xx receipt. */
sealed interface AgentDataUploadReceipt {
    /** The HTTP status that carried the receipt (always 2xx per the transport mapping). */
    val httpStatusCode: Int

    /** The gateway accepted and stored the exact artifact bytes. */
    data class Accepted(
        val revisionId: String?,
        override val httpStatusCode: Int,
    ) : AgentDataUploadReceipt

    /** The gateway rejected the upload with one of the four stable, health-free codes. */
    data class Rejected(
        val code: String,
        override val httpStatusCode: Int,
    ) : AgentDataUploadReceipt
}

/** A receipt could not be obtained after the bounded retry budget was exhausted. */
class AgentDataGatewayException(
    val retryable: Boolean,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * Client for the Agent Data ingestion protocol v1 HTTPS transport
 * (`POST {endpoint}/v1/ingest`).
 *
 * One artifact per request: the body is exactly one `\n`-terminated JSON manifest line
 * followed immediately by the exact artifact bytes, with
 * `Content-Type: application/x-healthmd-agent-data-ingest` and an exact `Content-Length`
 * (no compression, no multipart, no chunked sessions). Every validated outcome — accepted
 * or rejected — is an HTTP success response carrying a `healthmd.agent_ingest_response` v1
 * document; rejections are protocol outcomes, never HTTP errors.
 *
 * Retry posture (frozen): transport failures and `transient` receipts are retried a bounded
 * number of times with backoff; the three fix-and-re-upload codes (`truncated`,
 * `checksum_invalid`, `manifest_incomplete`) are NEVER auto-retried. All errors are
 * health-free and never include the endpoint query, artifact content, or health values.
 */
class AgentDataGatewayUploadClient(
    private val client: OkHttpClient,
    private val maxAttempts: Int = DEFAULT_MAX_ATTEMPTS,
    private val backoffMillis: suspend (attempt: Int) -> Long = { attempt ->
        (BASE_BACKOFF_MILLIS * (1L shl (attempt - 1).coerceAtMost(4))).coerceAtMost(MAX_BACKOFF_MILLIS)
    },
) {
    @Inject
    constructor(client: OkHttpClient) : this(client = client, maxAttempts = DEFAULT_MAX_ATTEMPTS)

    /**
     * Uploads one artifact with the protocol's bounded retry posture and returns the answered
     * receipt, or throws [AgentDataGatewayException] when no receipt could be obtained.
     *
     * @throws AgentDataGatewayException when transport failures or `transient` receipts
     * exhaust the retry budget, or a non-retryable transport-level failure occurs.
     */
    suspend fun upload(
        baseUrl: String,
        manifest: AgentDataIngestManifest,
        artifactBytes: ByteArray,
    ): AgentDataUploadReceipt {
        var attempt = 1
        while (true) {
            try {
                val receipt = uploadOnce(baseUrl, manifest, artifactBytes)
                if (receipt is AgentDataUploadReceipt.Rejected &&
                    receipt.code == AgentDataRejectionCodes.TRANSIENT &&
                    attempt < maxAttempts
                ) {
                    // An unfinalized or busy gateway answered transient; retry the identical
                    // bytes (a repeat upload is idempotent by SHA-256 identity).
                } else {
                    return receipt
                }
            } catch (error: AgentDataGatewayException) {
                if (!error.retryable || attempt >= maxAttempts) throw error
            }
            coroutineContext.ensureActive()
            delay(backoffMillis(attempt))
            attempt += 1
        }
    }

    private suspend fun uploadOnce(
        baseUrl: String,
        manifest: AgentDataIngestManifest,
        artifactBytes: ByteArray,
    ): AgentDataUploadReceipt = withContext(Dispatchers.IO) {
        val normalized = AgentDataGatewayEndpoint.normalizedOrNull(baseUrl)
            ?: throw AgentDataGatewayException(
                retryable = false,
                message = "Configure a valid HTTP or HTTPS gateway endpoint before exporting.",
            )
        val ingestUrl = normalized.toHttpUrlOrNull()
            ?.newBuilder()
            ?.addPathSegment("v1")
            ?.addPathSegment("ingest")
            ?.build()
            ?: throw AgentDataGatewayException(
                retryable = false,
                message = "Configure a valid HTTP or HTTPS gateway endpoint before exporting.",
            )

        if (artifactBytes.size.toLong() > AgentDataIngestManifest.MAX_ARTIFACT_BYTES) {
            throw AgentDataGatewayException(
                retryable = false,
                message = "The artifact exceeds the 64 MiB ingestion bound.",
            )
        }

        val manifestLine = manifest.encodeJsonLine().encodeToByteArray()
        val totalBytes = manifestLine.size + NEWLINE.size + artifactBytes.size
        val body = object : RequestBody() {
            override fun contentType(): MediaType = INGEST_MEDIA_TYPE
            override fun contentLength(): Long = totalBytes.toLong()
            override fun writeTo(sink: BufferedSink) {
                // One \n-terminated manifest line followed immediately by the exact bytes.
                sink.write(manifestLine)
                sink.write(NEWLINE)
                sink.write(artifactBytes)
            }
        }

        val request = Request.Builder()
            .url(ingestUrl)
            .post(body)
            .header("Accept", "application/json")
            .header("User-Agent", USER_AGENT)
            .build()

        val response = try {
            // Gateway uploads never follow redirects, mirroring the raw snapshot discipline: a
            // redirect must not replay the framed health-data body to another origin.
            client.newBuilder()
                .followRedirects(false)
                .followSslRedirects(false)
                .build()
                .newCall(request)
                .execute()
        } catch (error: IOException) {
            coroutineContext.ensureActive()
            throw AgentDataGatewayException(
                retryable = true,
                message = "Could not reach the Agent Data gateway.",
                cause = error,
            )
        }

        response.use {
            if (!it.isSuccessful) {
                // Transport-level health-free error: no receipt exists for this request.
                throw AgentDataGatewayException(
                    retryable = isRetryableStatus(it.code),
                    message = "The Agent Data gateway returned HTTP ${it.code}.",
                )
            }
            val receiptBody = it.body?.bytes()
                ?: throw AgentDataGatewayException(
                    retryable = false,
                    message = "The Agent Data gateway returned an empty receipt.",
                )
            parseReceipt(receiptBody, it.code)
        }
    }

    private fun parseReceipt(bytes: ByteArray, httpStatusCode: Int): AgentDataUploadReceipt {
        val root = runCatching {
            receiptJson.parseToJsonElement(bytes.decodeToString()).jsonObject
        }.getOrNull() ?: throw receiptProtocolViolation()

        val schema = root["schema"]?.jsonPrimitive?.contentOrNull
        val schemaVersion = root["schema_version"]?.jsonPrimitive?.intOrNull
        val outcome = root["outcome"]?.jsonPrimitive?.contentOrNull
        if (schema != RECEIPT_SCHEMA || schemaVersion != RECEIPT_SCHEMA_VERSION ||
            (outcome != OUTCOME_ACCEPTED && outcome != OUTCOME_REJECTED)
        ) {
            throw receiptProtocolViolation()
        }
        if (outcome == OUTCOME_ACCEPTED) {
            val revisionId = root["stored"]?.jsonObject?.get("revision_id")?.jsonPrimitive?.contentOrNull
            return AgentDataUploadReceipt.Accepted(revisionId = revisionId, httpStatusCode = httpStatusCode)
        }
        val code = root["rejection"]?.jsonObject?.get("code")?.jsonPrimitive?.contentOrNull
        if (code == null || code !in AgentDataRejectionCodes.ALL) {
            throw receiptProtocolViolation()
        }
        return AgentDataUploadReceipt.Rejected(code = code, httpStatusCode = httpStatusCode)
    }

    private fun receiptProtocolViolation() = AgentDataGatewayException(
        retryable = false,
        message = "The Agent Data gateway returned an invalid receipt.",
    )

    companion object {
        const val INGEST_MEDIA_TYPE_VALUE = "application/x-healthmd-agent-data-ingest"
        private val INGEST_MEDIA_TYPE = INGEST_MEDIA_TYPE_VALUE.toMediaType()
        private val NEWLINE = byteArrayOf('\n'.code.toByte())
        private val receiptJson = Json { ignoreUnknownKeys = false }
        private const val RECEIPT_SCHEMA = "healthmd.agent_ingest_response"
        private const val RECEIPT_SCHEMA_VERSION = 1
        private const val OUTCOME_ACCEPTED = "accepted"
        private const val OUTCOME_REJECTED = "rejected"
        private const val USER_AGENT = "Health.md Android Agent Data Gateway/1"
        const val DEFAULT_MAX_ATTEMPTS = 3
        const val BASE_BACKOFF_MILLIS = 500L
        const val MAX_BACKOFF_MILLIS = 8_000L

        private fun isRetryableStatus(code: Int): Boolean =
            code == 408 || code == 429 || code >= 500
    }
}
