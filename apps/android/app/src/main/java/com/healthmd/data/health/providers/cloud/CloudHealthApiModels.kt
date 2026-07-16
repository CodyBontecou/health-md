package com.healthmd.data.health.providers.cloud

import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

/** Fidelity vocabulary shared by cloud capture and raw-manifest integrations. */
@Serializable
enum class CloudProviderFidelity {
    /** Exact successful provider API response bytes are available. */
    @SerialName("native_api_payload")
    NATIVE_API_PAYLOAD,

    /** Only Health.md's normalized projection is available; native records must not be invented. */
    @SerialName("normalized_only")
    NORMALIZED_ONLY,

    /** The provider cannot supply the requested source representation. */
    @SerialName("unsupported")
    UNSUPPORTED,

    /** Health Connect exposes an API projection, not an original cloud payload. */
    @SerialName("health_connect_api_projected")
    HEALTH_CONNECT_API_PROJECTED,
}

/** Serializable declaration that can be embedded additively in a raw export manifest. */
@Serializable
data class CloudProviderFidelityDeclaration(
    val providerId: String,
    val fidelity: CloudProviderFidelity,
)

/**
 * One exact, successful cloud API page. Response bytes are defensively copied so an observer
 * cannot mutate the value subsequently returned to another consumer.
 */
class CloudHealthRawResponse internal constructor(
    val providerId: String,
    val endpointIdentifier: String,
    val queryMetadata: Map<String, String>,
    val fetchedAt: Instant,
    val httpStatus: Int,
    val contentType: String?,
    val charset: String,
    val pageOrdinal: Int,
    val responseHeaders: Map<String, String>,
    responseBytes: ByteArray,
    val responseText: String?,
    val json: JsonElement,
    val jsonValid: Boolean,
) {
    private val capturedBytes = responseBytes.copyOf()

    /** Exact bytes received from the successful response, returned as an independent copy. */
    val responseBytes: ByteArray
        get() = capturedBytes.copyOf()
}

/**
 * A back-pressured response observer. The request does not complete until this callback returns,
 * and the client keeps no response history, so observing successive pages requires no unbounded
 * in-memory collection.
 */
fun interface CloudRawResponseObserver {
    suspend fun onResponse(response: CloudHealthRawResponse)
}

class CloudHealthRequestException internal constructor(
    providerId: String,
    val httpStatus: Int? = null,
) : IllegalStateException(
    if (httpStatus == null) "$providerId cloud request failed" else "$providerId cloud request failed ($httpStatus)",
)

class CloudHealthPayloadException internal constructor(providerId: String) :
    IllegalStateException("$providerId cloud response was not valid JSON")
