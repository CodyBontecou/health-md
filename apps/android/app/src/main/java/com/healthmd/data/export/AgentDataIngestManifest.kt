package com.healthmd.data.export

import com.healthmd.domain.model.AgentDataArtifactOutcome
import java.security.MessageDigest
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * `healthmd.agent_data_ingest` v1 manifest describing exactly one uploaded artifact.
 *
 * The phone uploads one artifact per request: a `\n`-terminated JSON manifest line followed
 * immediately by exactly `byteCount` artifact bytes. `recordCount` is deliberately OMITTED
 * per the Android client decision: the phone does not declare the informational count.
 * Completeness is always `complete` for raw kinds (required by the contract) and `complete`
 * for the per-day daily artifacts the folder-parity path renders; the phone only uploads
 * finalized artifacts and never emits `finalized: false`.
 */
@Serializable
data class AgentDataIngestManifest(
    @SerialName("schema") val schema: String = SCHEMA,
    @SerialName("schema_version") val schemaVersion: Int = SCHEMA_VERSION,
    @SerialName("artifact_kind") val artifactKind: String,
    @SerialName("platform") val platform: String = PLATFORM_ANDROID,
    @SerialName("artifact_schema") val artifactSchema: String,
    @SerialName("artifact_schema_version") val artifactSchemaVersion: Int,
    @SerialName("owner_date") val ownerDate: String,
    @SerialName("physical_format") val physicalFormat: String,
    @SerialName("media_type") val mediaType: String,
    @SerialName("byte_count") val byteCount: Long,
    @SerialName("sha256") val sha256: String,
    @SerialName("completeness") val completeness: AgentDataCompleteness,
) {
    init {
        require(schema == SCHEMA) { "manifest schema is fixed" }
        require(schemaVersion == SCHEMA_VERSION) { "manifest schema version is fixed" }
        require(artifactKind in ArtifactKind.WIRE_NAMES) { "unsupported artifact kind" }
        require(platform == PLATFORM_ANDROID) { "manifest platform is fixed to android" }
        require(artifactSchema.isNotEmpty() && artifactSchema.length <= MAX_SCHEMA_IDENTITY_LENGTH) {
            "artifact schema identity out of bounds"
        }
        require(artifactSchemaVersion >= 1) { "artifact schema version must be positive" }
        require(ownerDate.length == ISO_DATE_LENGTH && runCatching { LocalDate.parse(ownerDate) }.isSuccess) {
            "owner date must be an ISO-8601 calendar date"
        }
        require(physicalFormat in setOf(PHYSICAL_FORMAT_JSON, PHYSICAL_FORMAT_NDJSON)) {
            "physical format must be json or ndjson"
        }
        require(mediaType.isNotEmpty() && mediaType.length <= MAX_MEDIA_TYPE_LENGTH) {
            "media type out of bounds"
        }
        require(byteCount in 1..MAX_ARTIFACT_BYTES) { "artifact byte count out of bounds" }
        require(sha256.length == SHA256_HEX_LENGTH && sha256.all { it in '0'..'9' || it in 'a'..'f' }) {
            "sha256 must be lowercase hex"
        }
        if (artifactKind == ArtifactKind.RAW_SNAPSHOT || artifactKind == ArtifactKind.RAW_CHANGES) {
            require(completeness.type == AgentDataCompleteness.TYPE_COMPLETE) {
                "raw artifacts must be uploaded complete"
            }
        }
    }

    /** Canonical one-line JSON encoding of the manifest (`\n` terminator added by the client). */
    fun encodeJsonLine(): String = json.encodeToString(serializer(), this)

    companion object {
        const val SCHEMA = "healthmd.agent_data_ingest"
        const val SCHEMA_VERSION = 1
        const val PLATFORM_ANDROID = "android"
        const val PHYSICAL_FORMAT_JSON = "json"
        const val PHYSICAL_FORMAT_NDJSON = "ndjson"
        const val MAX_ARTIFACT_BYTES: Long = 67_108_864L
        private const val MAX_SCHEMA_IDENTITY_LENGTH = 128
        private const val MAX_MEDIA_TYPE_LENGTH = 128
        private const val SHA256_HEX_LENGTH = 64
        private const val ISO_DATE_LENGTH = 10
        private val json = Json { encodeDefaults = true; explicitNulls = false; prettyPrint = false }
    }
}

/** `completeness` object grammar: `complete`, or a finalized partial with covered owner dates. */
@Serializable
data class AgentDataCompleteness(
    @SerialName("type") val type: String,
    @SerialName("finalized") val finalized: Boolean? = null,
    @SerialName("covered_owner_dates") val coveredOwnerDates: List<String>? = null,
) {
    init {
        when (type) {
            TYPE_COMPLETE -> require(finalized == null && coveredOwnerDates == null) {
                "complete artifacts carry no finalization or coverage fields"
            }
            TYPE_PARTIAL -> {
                // The phone only uploads finalized partials; the schema pins finalized to true.
                require(finalized == true) { "partial uploads must be finalized" }
                val dates = requireNotNull(coveredOwnerDates) { "partial uploads declare covered owner dates" }
                require(dates.isNotEmpty() && dates.size <= MAX_COVERED_DATES) {
                    "covered owner dates out of bounds"
                }
                require(dates.distinct().size == dates.size) { "covered owner dates must be unique" }
                require(dates.all { runCatching { LocalDate.parse(it) }.isSuccess }) {
                    "covered owner dates must be ISO-8601 calendar dates"
                }
            }
            else -> throw IllegalArgumentException("unknown completeness type")
        }
    }

    companion object {
        const val TYPE_COMPLETE = "complete"
        const val TYPE_PARTIAL = "partial"
        const val MAX_COVERED_DATES = 400

        fun complete(): AgentDataCompleteness = AgentDataCompleteness(TYPE_COMPLETE)

        /** The only partial shape the phone emits: finalized with its covered owner dates. */
        fun finalizedPartial(coveredOwnerDates: List<LocalDate>): AgentDataCompleteness {
            val dates = coveredOwnerDates.distinct().sorted()
            require(dates.isNotEmpty()) { "covered owner dates must not be empty" }
            return AgentDataCompleteness(
                type = TYPE_PARTIAL,
                finalized = true,
                coveredOwnerDates = dates.map { it.format(DateTimeFormatter.ISO_LOCAL_DATE) },
            )
        }
    }
}

/** The four standalone artifact kinds Agent Data ingestion v1 recognizes. */
object ArtifactKind {
    const val HEALTH_DATA_DAILY = "health_data_daily"
    const val EXTERNAL_PROVIDER_DAILY = "external_provider_daily"
    const val RAW_SNAPSHOT = "raw_snapshot"
    const val RAW_CHANGES = "raw_changes"

    val WIRE_NAMES: Set<String> = setOf(
        HEALTH_DATA_DAILY,
        EXTERNAL_PROVIDER_DAILY,
        RAW_SNAPSHOT,
        RAW_CHANGES,
    )
}

/** One artifact prepared for upload: exact bytes plus their protocol manifest. */
data class AgentDataPreparedArtifact(
    val manifest: AgentDataIngestManifest,
    val bytes: ByteArray,
    /** Local-only provenance for the per-artifact outcome surface; never uploaded. */
    val outcome: AgentDataArtifactOutcome,
) {
    override fun equals(other: Any?): Boolean =
        other is AgentDataPreparedArtifact && manifest == other.manifest && bytes.contentEquals(other.bytes)
    override fun hashCode(): Int = manifest.hashCode() * 31 + bytes.contentHashCode()
}

/**
 * Builds ingestion manifests from the export engine's own artifact metadata, mirroring what
 * the folder destination writes: the daily JSON artifact's schema identity is parsed from the
 * rendered document itself (never assumed), and raw artifacts carry their structural identity.
 */
object AgentDataIngestManifestBuilder {

    /** Manifest for one per-day daily health-data JSON artifact. */
    fun dailyHealthData(
        ownerDate: LocalDate,
        artifactBytes: ByteArray,
        mediaType: String = MEDIA_TYPE_JSON,
    ): AgentDataIngestManifest {
        require(mediaType.isNotEmpty()) { "media type is required" }
        val root = runCatching {
            Json.parseToJsonElement(artifactBytes.decodeToString()).jsonObject
        }.getOrNull() ?: throw IllegalArgumentException("daily artifact is not a JSON object")
        // The artifact's own schema identity, exactly as the folder destination writes it:
        // rust-planned frozen-v4 documents carry snake_case `schema`/`schema_version`, the
        // analytical profile carries camelCase `schemaVersion`, and a legacy compatibility
        // document with neither is implicitly the frozen v4 daily record.
        val artifactSchema: String
        val artifactSchemaVersion: Int
        val explicitSchema = root["schema"]?.jsonPrimitive?.contentOrNull
        if (explicitSchema != null) {
            artifactSchema = explicitSchema
            artifactSchemaVersion = root.getValue("schema_version").jsonPrimitive.int
        } else {
            artifactSchema = HealthMdExportSchema.IDENTIFIER
            artifactSchemaVersion = root["schemaVersion"]?.jsonPrimitive?.intOrNull
                ?: HealthMdExportSchema.VERSION
        }
        return manifest(
            artifactKind = ArtifactKind.HEALTH_DATA_DAILY,
            artifactSchema = artifactSchema,
            artifactSchemaVersion = artifactSchemaVersion,
            ownerDate = ownerDate,
            physicalFormat = AgentDataIngestManifest.PHYSICAL_FORMAT_JSON,
            mediaType = mediaType,
            bytes = artifactBytes,
            completeness = AgentDataCompleteness.complete(),
        )
    }

    /** Manifest for one complete raw snapshot artifact (JSON or NDJSON). */
    fun rawSnapshot(
        captureDay: LocalDate,
        physicalFormat: String,
        bytes: ByteArray,
        mediaType: String,
    ): AgentDataIngestManifest = manifest(
        artifactKind = ArtifactKind.RAW_SNAPSHOT,
        artifactSchema = RAW_SNAPSHOT_SCHEMA,
        artifactSchemaVersion = RAW_SNAPSHOT_SCHEMA_VERSION,
        ownerDate = captureDay,
        physicalFormat = physicalFormat,
        mediaType = mediaType,
        bytes = bytes,
        completeness = AgentDataCompleteness.complete(),
    )

    private fun manifest(
        artifactKind: String,
        artifactSchema: String,
        artifactSchemaVersion: Int,
        ownerDate: LocalDate,
        physicalFormat: String,
        mediaType: String,
        bytes: ByteArray,
        completeness: AgentDataCompleteness,
    ): AgentDataIngestManifest {
        val byteCount = bytes.size.toLong()
        if (byteCount > AgentDataIngestManifest.MAX_ARTIFACT_BYTES) {
            throw IllegalArgumentException("artifact exceeds the 64 MiB ingestion bound")
        }
        return AgentDataIngestManifest(
            artifactKind = artifactKind,
            artifactSchema = artifactSchema,
            artifactSchemaVersion = artifactSchemaVersion,
            ownerDate = ownerDate.format(DateTimeFormatter.ISO_LOCAL_DATE),
            physicalFormat = physicalFormat,
            mediaType = mediaType,
            byteCount = byteCount,
            sha256 = sha256Hex(bytes),
            completeness = completeness,
        )
    }

    const val MEDIA_TYPE_JSON = "application/json"
    const val MEDIA_TYPE_NDJSON = "application/x-ndjson"
    const val RAW_SNAPSHOT_SCHEMA = "healthmd.raw-snapshot"
    const val RAW_SNAPSHOT_SCHEMA_VERSION = 1

    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { byte ->
            "%02x".format(byte)
        }
}
