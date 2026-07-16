package com.healthmd.rawexport

import java.io.File
import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import okio.source

fun interface RawSnapshotArtifactResolver {
    fun resolve(result: RawExportResult): CompletedRawSnapshot
}

data class CompletedRawSnapshot(
    val format: RawExportFormat,
    val contentLength: Long? = null,
    val openStream: () -> InputStream,
) {
    companion object {
        fun file(file: File, format: RawExportFormat) = CompletedRawSnapshot(format, file.length(), file::inputStream)
    }
}

data class RawApiHeader(val name: String, val value: String)
data class RawApiUploadResult(val statusCode: Int, val responseBodyPreview: String?)

class RawSnapshotApiException(
    val retryable: Boolean,
    val statusCode: Int? = null,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

class RawSnapshotApiClient(private val client: OkHttpClient) {
    suspend fun upload(
        endpointUrl: String,
        artifact: CompletedRawSnapshot,
        authorizationHeader: String? = null,
        headers: List<RawApiHeader> = emptyList(),
    ): RawApiUploadResult = withContext(Dispatchers.IO) {
        val url = endpointUrl.trim().toHttpUrlOrNull()
            ?: throw RawSnapshotApiException(false, message = "Invalid raw snapshot API endpoint.")
        if (!url.isHttps) throw RawSnapshotApiException(false, message = "Raw snapshot API endpoints must use HTTPS.")
        val validatedHeaders = validateHeaders(headers)
        require(authorizationHeader?.let { !it.contains('\r') && !it.contains('\n') } != false) {
            "Invalid Authorization header."
        }
        val contentType = contentType(artifact.format)
        val body = object : RequestBody() {
            override fun contentType(): MediaType = contentType
            override fun contentLength(): Long = artifact.contentLength ?: -1L
            override fun writeTo(sink: BufferedSink) {
                artifact.openStream().use { input -> sink.writeAll(input.source()) }
            }
        }
        val request = Request.Builder()
            .url(url)
            .post(body)
            .header("Accept", "application/json")
            .header("User-Agent", "Health.md Android Raw Snapshot/1")
            .apply {
                authorizationHeader?.takeIf(String::isNotBlank)?.let { header("Authorization", it) }
                validatedHeaders.forEach { header(it.name, it.value) }
            }
            .build()
        val response = try {
            // Raw uploads never follow redirects. A redirect can otherwise replay the health-data
            // body, Authorization, and custom headers to a different or plaintext origin.
            client.newBuilder()
                .followRedirects(false)
                .followSslRedirects(false)
                .build()
                .newCall(request)
                .execute()
        } catch (error: IOException) {
            throw RawSnapshotApiException(true, message = "Could not reach the raw snapshot endpoint.", cause = error)
        }
        response.use {
            val preview = it.body?.charStream()?.let { reader ->
                val chars = CharArray(501)
                val count = reader.read(chars)
                if (count <= 0) null else String(chars, 0, count.coerceAtMost(500)).trim().takeIf(String::isNotEmpty)
            }
            if (!it.isSuccessful) {
                throw RawSnapshotApiException(
                    retryable = it.code == 408 || it.code == 429 || it.code >= 500,
                    statusCode = it.code,
                    message = "Raw snapshot endpoint returned HTTP ${it.code}.",
                )
            }
            RawApiUploadResult(it.code, preview)
        }
    }

    private fun validateHeaders(headers: List<RawApiHeader>): List<RawApiHeader> {
        val managedCount = headers.count { it.name.trim().lowercase() in RAW_CONTRACT_HEADER_NAMES }
        val userCount = headers.size - managedCount
        require(userCount <= MAX_USER_HEADERS) { "At most $MAX_USER_HEADERS user raw snapshot request headers are supported." }
        require(managedCount <= MAX_MANAGED_HEADERS) { "At most $MAX_MANAGED_HEADERS managed raw snapshot request headers are supported." }
        val forbidden = setOf("content-type", "content-length", "host", "transfer-encoding")
        return headers.map { header ->
            val name = header.name.trim()
            require(name.matches(Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+"))) { "Invalid API header name." }
            require(name.lowercase() !in forbidden) { "Header '$name' is managed by the raw API client." }
            require(!header.value.contains('\r') && !header.value.contains('\n')) { "Invalid API header value." }
            RawApiHeader(name, header.value.trim())
        }
    }

    companion object {
        private const val MAX_USER_HEADERS = 20
        private const val MAX_MANAGED_HEADERS = 6
        private val RAW_CONTRACT_HEADER_NAMES = setOf(
            "x-healthmd-schema",
            "x-healthmd-export-id",
            "x-healthmd-checksum-sha256",
            "x-healthmd-artifact-checksum-sha256",
            "x-healthmd-calendar-zone",
            "x-healthmd-provider",
        )
        const val JSON_CONTENT_TYPE = "application/vnd.healthmd.raw-snapshot+json; version=1; charset=utf-8"
        const val NDJSON_CONTENT_TYPE = "application/x-ndjson; charset=utf-8"
        fun contentType(format: RawExportFormat): MediaType =
            (if (format == RawExportFormat.JSON) JSON_CONTENT_TYPE else NDJSON_CONTENT_TYPE).toMediaType()
    }
}

class RawSnapshotApiEndpointExportRunner(
    private val orchestrator: RawSnapshotExportOrchestrator,
    private val apiClient: RawSnapshotApiClient,
    private val artifactResolver: RawSnapshotArtifactResolver,
) {
    suspend fun exportAndUpload(
        request: RawSnapshotRequest,
        endpointUrl: String,
        authorizationHeader: String? = null,
        headers: List<RawApiHeader> = emptyList(),
    ): Pair<RawExportResult, RawApiUploadResult> {
        val result = orchestrator.export(request)
        val upload = apiClient.upload(endpointUrl, artifactResolver.resolve(result), authorizationHeader, headers)
        return result to upload
    }
}
