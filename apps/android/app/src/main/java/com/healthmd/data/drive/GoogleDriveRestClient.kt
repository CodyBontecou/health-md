package com.healthmd.data.drive

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.Headers
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

sealed interface DriveApiResult<out T> {
    data class Success<T>(val value: T) : DriveApiResult<T>
    data class Failure(val error: GoogleDriveErrorId, val retryable: Boolean = false) : DriveApiResult<Nothing>
}

data class GoogleDriveAbout(val permissionId: String)
data class GoogleDriveUploadSession(val uri: String)
data class GoogleDriveUploadStatus(val acknowledgedBytes: Long, val complete: Boolean, val metadata: GoogleDriveRemoteMetadata? = null)

interface GoogleDriveApi {
    suspend fun about(accessToken: String): DriveApiResult<GoogleDriveAbout>
    suspend fun getMetadata(accessToken: String, fileId: String, resourceKeys: Map<String, String> = emptyMap()): DriveApiResult<GoogleDriveRemoteMetadata>
    suspend fun findChildren(accessToken: String, parentId: String, name: String, resourceKeys: Map<String, String> = emptyMap()): DriveApiResult<List<GoogleDriveRemoteMetadata>>
    suspend fun generateId(accessToken: String): DriveApiResult<String>
    suspend fun createFolder(accessToken: String, id: String, parentId: String, name: String, resourceKeys: Map<String, String> = emptyMap()): DriveApiResult<GoogleDriveRemoteMetadata>
    suspend fun download(accessToken: String, fileId: String, resourceKeys: Map<String, String> = emptyMap()): DriveApiResult<ByteArray>
    suspend fun startResumableCreate(accessToken: String, id: String, parentId: String, name: String, mediaType: String, size: Long, appProperties: Map<String, String>, resourceKeys: Map<String, String> = emptyMap()): DriveApiResult<GoogleDriveUploadSession>
    suspend fun startResumableUpdate(accessToken: String, fileId: String, mediaType: String, size: Long, appProperties: Map<String, String>, resourceKeys: Map<String, String> = emptyMap()): DriveApiResult<GoogleDriveUploadSession>
    suspend fun queryUpload(accessToken: String, sessionUri: String, totalSize: Long): DriveApiResult<GoogleDriveUploadStatus>
    suspend fun upload(accessToken: String, sessionUri: String, bytes: ByteArray, offset: Long): DriveApiResult<GoogleDriveUploadStatus>
}

/** Direct Drive v3 transport. No Health.md endpoint, token broker, or logging interceptor is used. */
class OkHttpGoogleDriveApi(
    private val client: OkHttpClient,
    private val apiBaseUrl: String = "https://www.googleapis.com/drive/v3",
    private val uploadBaseUrl: String = "https://www.googleapis.com/upload/drive/v3",
) : GoogleDriveApi {
    private val json = Json { ignoreUnknownKeys = true }
    private val metadataFields = "id,name,mimeType,parents,driveId,resourceKey,version,size,md5Checksum,sha256Checksum,trashed,capabilities(canAddChildren,canEdit)"

    override suspend fun about(accessToken: String): DriveApiResult<GoogleDriveAbout> = execute(
        request("$apiBaseUrl/about?fields=user(permissionId)", accessToken),
    ) { response ->
        val permissionId = parseObject(response)["user"]?.jsonObject
            ?.get("permissionId")?.jsonPrimitive?.contentOrNull
            ?: throw InvalidDriveResponse()
        GoogleDriveAbout(permissionId)
    }

    override suspend fun getMetadata(
        accessToken: String,
        fileId: String,
        resourceKeys: Map<String, String>,
    ): DriveApiResult<GoogleDriveRemoteMetadata> = execute(
        request("$apiBaseUrl/files/${encodePath(fileId)}?supportsAllDrives=true&fields=${encode(metadataFields)}", accessToken, resourceKeys),
    ) { parseMetadata(parseObject(it)) }

    override suspend fun findChildren(
        accessToken: String,
        parentId: String,
        name: String,
        resourceKeys: Map<String, String>,
    ): DriveApiResult<List<GoogleDriveRemoteMetadata>> {
        val query = "'${escapeQuery(parentId)}' in parents and name = '${escapeQuery(name)}' and trashed = false"
        val url = "$apiBaseUrl/files?supportsAllDrives=true&includeItemsFromAllDrives=true&pageSize=100&q=${encode(query)}&fields=${encode("files($metadataFields),nextPageToken")}" 
        return execute(request(url, accessToken, resourceKeys)) { response ->
            val root = parseObject(response)
            if (root["nextPageToken"] != null) throw InvalidDriveResponse() // bounded/fail closed
            root["files"]?.jsonArray?.map { parseMetadata(it.jsonObject) }.orEmpty()
        }
    }

    override suspend fun generateId(accessToken: String): DriveApiResult<String> = execute(
        request("$apiBaseUrl/files/generateIds?count=1&space=drive", accessToken),
    ) { response ->
        parseObject(response)["ids"]?.jsonArray?.singleOrNull()?.jsonPrimitive?.contentOrNull
            ?: throw InvalidDriveResponse()
    }

    override suspend fun createFolder(
        accessToken: String,
        id: String,
        parentId: String,
        name: String,
        resourceKeys: Map<String, String>,
    ): DriveApiResult<GoogleDriveRemoteMetadata> {
        val body = JsonObject(mapOf(
            "id" to JsonPrimitive(id),
            "name" to JsonPrimitive(name),
            "mimeType" to JsonPrimitive(GOOGLE_DRIVE_FOLDER_MIME_TYPE),
            "parents" to JsonArray(listOf(JsonPrimitive(parentId))),
            "appProperties" to JsonObject(mapOf("healthmd" to JsonPrimitive("managed-v1"))),
        )).toString().toRequestBody(JSON_MEDIA_TYPE)
        return execute(
            request("$apiBaseUrl/files?supportsAllDrives=true&fields=${encode(metadataFields)}", accessToken, resourceKeys, "POST", body),
        ) { parseMetadata(parseObject(it)) }
    }

    override suspend fun download(
        accessToken: String,
        fileId: String,
        resourceKeys: Map<String, String>,
    ): DriveApiResult<ByteArray> = executeBytes(
        request("$apiBaseUrl/files/${encodePath(fileId)}?alt=media&supportsAllDrives=true", accessToken, resourceKeys),
    )

    override suspend fun startResumableCreate(
        accessToken: String,
        id: String,
        parentId: String,
        name: String,
        mediaType: String,
        size: Long,
        appProperties: Map<String, String>,
        resourceKeys: Map<String, String>,
    ): DriveApiResult<GoogleDriveUploadSession> {
        val body = metadataBody(id, parentId, name, appProperties).toRequestBody(JSON_MEDIA_TYPE)
        return startSession(
            request(
                "$uploadBaseUrl/files?uploadType=resumable&supportsAllDrives=true&fields=${encode(metadataFields)}",
                accessToken,
                resourceKeys,
                "POST",
                body,
                Headers.headersOf(
                    "X-Upload-Content-Type", mediaType,
                    "X-Upload-Content-Length", size.toString(),
                ),
            ),
        )
    }

    override suspend fun startResumableUpdate(
        accessToken: String,
        fileId: String,
        mediaType: String,
        size: Long,
        appProperties: Map<String, String>,
        resourceKeys: Map<String, String>,
    ): DriveApiResult<GoogleDriveUploadSession> {
        val body = JsonObject(mapOf(
            "appProperties" to JsonObject(appProperties.mapValues { JsonPrimitive(it.value) }),
        )).toString().toRequestBody(JSON_MEDIA_TYPE)
        return startSession(
            request(
                "$uploadBaseUrl/files/${encodePath(fileId)}?uploadType=resumable&supportsAllDrives=true&fields=${encode(metadataFields)}",
                accessToken,
                resourceKeys,
                "PATCH",
                body,
                Headers.headersOf(
                    "X-Upload-Content-Type", mediaType,
                    "X-Upload-Content-Length", size.toString(),
                ),
            ),
        )
    }

    override suspend fun queryUpload(
        accessToken: String,
        sessionUri: String,
        totalSize: Long,
    ): DriveApiResult<GoogleDriveUploadStatus> {
        if (!isGoogleSessionUri(sessionUri)) return DriveApiResult.Failure(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
        val empty = ByteArray(0).toRequestBody("application/octet-stream".toMediaType())
        val request = Request.Builder().url(sessionUri)
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Length", "0")
            .header("Content-Range", "bytes */$totalSize")
            .put(empty)
            .build()
        return executeUpload(request, totalSize)
    }

    override suspend fun upload(
        accessToken: String,
        sessionUri: String,
        bytes: ByteArray,
        offset: Long,
    ): DriveApiResult<GoogleDriveUploadStatus> {
        if (!isGoogleSessionUri(sessionUri) || offset !in 0..bytes.size.toLong()) {
            return DriveApiResult.Failure(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
        }
        val remaining = bytes.copyOfRange(offset.toInt(), bytes.size)
        val end = if (remaining.isEmpty()) offset else offset + remaining.size - 1
        val request = Request.Builder().url(sessionUri)
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Length", remaining.size.toString())
            .header("Content-Range", "bytes $offset-$end/${bytes.size}")
            .put(remaining.toRequestBody("application/octet-stream".toMediaType()))
            .build()
        return executeUpload(request, bytes.size.toLong())
    }

    private suspend fun startSession(request: Request): DriveApiResult<GoogleDriveUploadSession> =
        execute(request) { response ->
            val location = response.header("Location") ?: throw InvalidDriveResponse()
            if (!isGoogleSessionUri(location)) throw InvalidDriveResponse()
            GoogleDriveUploadSession(location)
        }

    private suspend fun executeUpload(request: Request, totalSize: Long): DriveApiResult<GoogleDriveUploadStatus> =
        withContext(Dispatchers.IO) {
            try {
                client.newCall(request).execute().use { response ->
                    if (response.code == 308) {
                        val acknowledged = response.header("Range")
                            ?.substringAfterLast('-')?.toLongOrNull()?.plus(1) ?: 0L
                        if (acknowledged !in 0..totalSize) throw InvalidDriveResponse()
                        return@use DriveApiResult.Success(GoogleDriveUploadStatus(acknowledged, false))
                    }
                    if (!response.isSuccessful) return@use mapFailure(response)
                    val metadata = parseMetadata(parseObject(response))
                    DriveApiResult.Success(GoogleDriveUploadStatus(totalSize, true, metadata))
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: IOException) {
                DriveApiResult.Failure(GoogleDriveErrorId.AMBIGUOUS_COMMIT, retryable = true)
            } catch (_: InvalidDriveResponse) {
                DriveApiResult.Failure(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
            }
        }

    private suspend fun <T> execute(request: Request, transform: (Response) -> T): DriveApiResult<T> =
        withContext(Dispatchers.IO) {
            try {
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@use mapFailure(response)
                    DriveApiResult.Success(transform(response))
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: IOException) {
                DriveApiResult.Failure(GoogleDriveErrorId.RATE_LIMITED, retryable = true)
            } catch (_: InvalidDriveResponse) {
                DriveApiResult.Failure(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
            }
        }

    private suspend fun executeBytes(request: Request): DriveApiResult<ByteArray> = withContext(Dispatchers.IO) {
        try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@use mapFailure(response)
                val body = response.body ?: throw InvalidDriveResponse()
                val contentLength = body.contentLength()
                if (contentLength > MAX_DOWNLOAD_BYTES) throw InvalidDriveResponse()
                val bytes = body.bytes()
                if (bytes.size > MAX_DOWNLOAD_BYTES) throw InvalidDriveResponse()
                DriveApiResult.Success(bytes)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: IOException) {
            DriveApiResult.Failure(GoogleDriveErrorId.RATE_LIMITED, retryable = true)
        } catch (_: InvalidDriveResponse) {
            DriveApiResult.Failure(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
        }
    }

    private fun mapFailure(response: Response): DriveApiResult.Failure {
        // Bodies can contain account/file/path details and are intentionally never read or logged.
        val error = when (response.code) {
            HttpURLConnection.HTTP_UNAUTHORIZED -> GoogleDriveErrorId.REAUTHORIZATION_REQUIRED
            HttpURLConnection.HTTP_FORBIDDEN -> GoogleDriveErrorId.PERMISSION_DENIED
            HttpURLConnection.HTTP_NOT_FOUND, HttpURLConnection.HTTP_GONE -> GoogleDriveErrorId.FOLDER_UNAVAILABLE
            409, 412 -> GoogleDriveErrorId.REMOTE_CONFLICT
            429 -> GoogleDriveErrorId.RATE_LIMITED
            507 -> GoogleDriveErrorId.QUOTA_EXCEEDED
            in 500..599 -> GoogleDriveErrorId.RATE_LIMITED
            else -> GoogleDriveErrorId.PERMISSION_DENIED
        }
        return DriveApiResult.Failure(error, response.code == 429 || response.code in 500..599)
    }

    private fun request(
        url: String,
        token: String,
        resourceKeys: Map<String, String> = emptyMap(),
        method: String = "GET",
        body: okhttp3.RequestBody? = null,
        extraHeaders: Headers = Headers.headersOf(),
    ): Request {
        val builder = Request.Builder().url(url)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
        if (resourceKeys.isNotEmpty()) {
            builder.header(
                "X-Goog-Drive-Resource-Keys",
                resourceKeys.entries.sortedBy { it.key }.joinToString(",") { "${it.key}/${it.value}" },
            )
        }
        extraHeaders.forEach { builder.header(it.first, it.second) }
        builder.method(method, body)
        return builder.build()
    }

    private fun metadataBody(
        id: String,
        parentId: String,
        name: String,
        appProperties: Map<String, String>,
    ): String = JsonObject(mapOf(
        "id" to JsonPrimitive(id),
        "name" to JsonPrimitive(name),
        "parents" to JsonArray(listOf(JsonPrimitive(parentId))),
        "appProperties" to JsonObject(appProperties.mapValues { JsonPrimitive(it.value) }),
    )).toString()

    private fun parseObject(response: Response): JsonObject {
        val body = response.body ?: throw InvalidDriveResponse()
        if (body.contentLength() > MAX_METADATA_BYTES) throw InvalidDriveResponse()
        val text = body.string()
        if (text.toByteArray().size > MAX_METADATA_BYTES) throw InvalidDriveResponse()
        return json.parseToJsonElement(text).jsonObject
    }

    private fun parseMetadata(value: JsonObject): GoogleDriveRemoteMetadata = GoogleDriveRemoteMetadata(
        id = value.requiredString("id"),
        name = value.requiredString("name"),
        mimeType = value.requiredString("mimeType"),
        parents = (value["parents"] as? JsonArray)?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty(),
        driveId = value.optionalString("driveId"),
        resourceKey = value.optionalString("resourceKey"),
        version = value.optionalString("version"),
        size = value["size"]?.jsonPrimitive?.longOrNull,
        md5Checksum = value.optionalString("md5Checksum"),
        sha256Checksum = value.optionalString("sha256Checksum"),
        trashed = value["trashed"]?.jsonPrimitive?.booleanOrNull ?: false,
        capabilities = value["capabilities"]?.jsonObject?.let {
            GoogleDriveFolderCapabilities(
                canAddChildren = it["canAddChildren"]?.jsonPrimitive?.booleanOrNull ?: false,
                canEdit = it["canEdit"]?.jsonPrimitive?.booleanOrNull ?: false,
            )
        } ?: GoogleDriveFolderCapabilities(),
    )

    private fun JsonObject.requiredString(key: String): String =
        optionalString(key)?.takeIf(String::isNotBlank) ?: throw InvalidDriveResponse()
    private fun JsonObject.optionalString(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull
    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")
    private fun encodePath(value: String): String = encode(value)
    private fun escapeQuery(value: String): String = value.replace("\\", "\\\\").replace("'", "\\'")
    private fun isGoogleSessionUri(value: String): Boolean = runCatching {
        val url = value.toHttpUrlOrNull() ?: return@runCatching false
        url.isHttps && (url.host == "www.googleapis.com" || url.host.endsWith(".googleapis.com"))
    }.getOrDefault(false)

    private class InvalidDriveResponse : RuntimeException()

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private const val MAX_METADATA_BYTES = 2 * 1024 * 1024L
        private const val MAX_DOWNLOAD_BYTES = 256 * 1024 * 1024L
    }
}

internal fun md5Hex(bytes: ByteArray): String =
    MessageDigest.getInstance("MD5").digest(bytes).joinToString("") { "%02x".format(it) }
