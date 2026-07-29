package com.healthmd.direct

import com.healthmd.direct.protocol.PreparedTransfer
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import java.io.File
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull

@Singleton
class DirectCliJobStore @Inject constructor(
    trustStore: DirectCliTrustStore,
) {
    private val root = File(trustStore.rootDirectory(), "jobs").apply {
        check(mkdirs() || isDirectory) { "Unable to create Direct CLI job storage." }
    }
    private val json = Json { encodeDefaults = true; explicitNulls = true; ignoreUnknownKeys = false }

    @Synchronized
    fun load(jobId: String, requestFingerprint: String): DirectJobJournal? {
        sweepExpired()
        val directory = jobDirectory(jobId)
        val file = File(directory, JOURNAL_NAME)
        if (!file.isFile) {
            require(directory.listFiles().isNullOrEmpty()) {
                "The durable Direct CLI spool is incomplete."
            }
            return null
        }
        val journal = runCatching { json.decodeFromString<DirectJobJournal>(file.readText()) }
            .getOrElse { throw IllegalArgumentException("The durable Direct CLI journal is corrupt.", it) }
        require(journal.requestFingerprint == requestFingerprint) {
            "The durable Direct CLI request changed."
        }
        require(Instant.parse(journal.expiresAt).isAfter(Instant.now())) {
            "The durable Direct CLI job expired."
        }
        require(journal.transfer.artifactPaths.values.all { File(it).isFile }) {
            "A resumable Direct CLI artifact is missing."
        }
        return journal
    }

    @Synchronized
    fun beginPreparation(
        jobId: String,
        requestFingerprint: String,
        expiresAt: String,
        enginePin: ExportEnginePin? = null,
        protocolPin: AndroidDirectProtocolPin? = null,
    ) {
        requireValidOptionalPin(enginePin)
        requireValidOptionalProtocolPin(protocolPin)
        val directory = jobDirectory(jobId).apply {
            check(mkdirs() || isDirectory) { "Unable to create Direct CLI job directory." }
        }
        val pending = File(directory, PENDING_NAME)
        if (pending.isFile) {
            val saved = decodePendingJob(pending.readText())
            require(saved.requestFingerprint == requestFingerprint) {
                "The pending Direct CLI request changed."
            }
            require(saved.expiresAt == expiresAt) {
                "The pending Direct CLI expiration changed."
            }
            requireDirectPinContinuity(saved.enginePin, enginePin)
            requireDirectProtocolPinContinuity(saved.protocolPin, protocolPin)
            throw IllegalStateException("A prior Direct CLI preparation did not finish.")
        }
        atomicWrite(
            pending,
            encodePendingJob(
                PendingJob(
                    version = DirectJobJournal.CURRENT_VERSION,
                    requestFingerprint = requestFingerprint,
                    expiresAt = expiresAt,
                    enginePin = enginePin,
                    protocolPin = protocolPin,
                ),
            ).toByteArray(),
        )
    }

    @Synchronized
    fun hasIncompletePreparation(jobId: String, requestFingerprint: String): Boolean {
        sweepExpired()
        val pending = File(jobDirectory(jobId), PENDING_NAME)
        if (!pending.isFile) return false
        val saved = runCatching { decodePendingJob(pending.readText()) }
            .getOrElse { return true }
        require(saved.requestFingerprint == requestFingerprint) {
            "The pending Direct CLI request changed."
        }
        return true
    }

    @Synchronized
    fun save(journal: DirectJobJournal) {
        require(UUID.fromString(journal.transfer.accepted.jobId).toString() == journal.transfer.accepted.jobId)
        val directory = jobDirectory(journal.transfer.accepted.jobId).apply {
            check(mkdirs() || isDirectory) { "Unable to create Direct CLI job directory." }
        }
        val pendingFile = File(directory, PENDING_NAME)
        if (pendingFile.isFile) {
            val pending = decodePendingJob(pendingFile.readText())
            require(pending.version == journal.version) {
                "The pending Direct CLI journal version changed."
            }
            require(pending.requestFingerprint == journal.requestFingerprint) {
                "The pending Direct CLI request changed."
            }
            require(pending.expiresAt == journal.expiresAt) {
                "The pending Direct CLI expiration changed."
            }
            requireDirectPinContinuity(pending.enginePin, journal.enginePin)
            requireDirectProtocolPinContinuity(pending.protocolPin, journal.protocolPin)
        }
        atomicWrite(File(directory, JOURNAL_NAME), json.encodeToString(journal).toByteArray())
        pendingFile.delete()
    }

    @Synchronized
    fun markAccounted(jobId: String) {
        val journal = requireNotNull(loadUnvalidated(jobId))
        if (!journal.accounted) save(journal.copy(accounted = true))
    }

    @Synchronized
    fun markCompleted(jobId: String) {
        val journal = requireNotNull(loadUnvalidated(jobId))
        // Keep exact artifacts through the bounded job lifetime so a lost completion confirmation
        // can replay idempotently without rereading a non-transactional provider.
        save(journal.copy(completed = true))
    }

    @Synchronized
    fun cancel(jobId: String) {
        jobDirectory(jobId).deleteRecursively()
    }

    @Synchronized
    fun purgeAll() {
        root.deleteRecursively()
        check(root.mkdirs() || root.isDirectory) { "Unable to recreate the Direct CLI job store." }
    }

    @Synchronized
    fun sweepExpired(now: Instant = Instant.now()) {
        root.listFiles()?.filter(File::isDirectory)?.forEach { directory ->
            val journal = runCatching {
                json.decodeFromString<DirectJobJournal>(File(directory, JOURNAL_NAME).readText())
            }.getOrNull()
            val pending = runCatching {
                decodePendingJob(File(directory, PENDING_NAME).readText())
            }.getOrNull()
            val expiresAt = journal?.expiresAt ?: pending?.expiresAt
            val expired = expiresAt?.let { runCatching { !Instant.parse(it).isAfter(now) }.getOrNull() }
            val corruptRetentionElapsed = expired == null &&
                directory.lastModified() > 0L &&
                directory.lastModified() <= now.minusSeconds(MAXIMUM_RETENTION_SECONDS).toEpochMilli()
            if (expired == true || corruptRetentionElapsed) directory.deleteRecursively()
        }
    }

    fun directory(jobId: String): File = jobDirectory(jobId).apply {
        check(mkdirs() || isDirectory) { "Unable to create Direct CLI job directory." }
    }

    private fun loadUnvalidated(jobId: String): DirectJobJournal? {
        val file = journalFile(jobId)
        return if (file.isFile) {
            runCatching { json.decodeFromString<DirectJobJournal>(file.readText()) }
                .getOrElse { throw IllegalStateException("The durable Direct CLI journal is corrupt.", it) }
        } else {
            null
        }
    }

    private fun encodePendingJob(pending: PendingJob): String = json.encodeToString(
        PendingJobWire(
            version = pending.version,
            requestFingerprint = pending.requestFingerprint,
            expiresAt = pending.expiresAt,
            enginePin = pending.enginePin?.let { json.parseToJsonElement(ExportEnginePinCodec.encodeCanonical(it)) },
            protocolPin = pending.protocolPin,
        ),
    )

    private fun decodePendingJob(raw: String): PendingJob {
        val wire = json.decodeFromString<PendingJobWire>(raw)
        val version = wire.version ?: DirectJobJournal.LEGACY_VERSION
        require(version in DirectJobJournal.SUPPORTED_VERSIONS) {
            "Unsupported pending Direct CLI journal version."
        }
        // Missing/older versions are authoritative: unexpected future pin data cannot upgrade work.
        val pin = if (version == DirectJobJournal.LEGACY_VERSION) null else decodeDurablePin(wire.enginePin)
        val protocolPin = if (version >= DirectJobJournal.PROTOCOL_PIN_VERSION) wire.protocolPin else null
        requireValidOptionalProtocolPin(protocolPin)
        return PendingJob(version, wire.requestFingerprint, wire.expiresAt, pin, protocolPin)
    }

    private fun journalFile(jobId: String): File = File(jobDirectory(jobId), JOURNAL_NAME)

    private fun jobDirectory(jobId: String): File =
        File(root, UUID.fromString(jobId).toString())

    private fun atomicWrite(file: File, bytes: ByteArray) {
        val temporary = File(file.parentFile, ".${file.name}.${UUID.randomUUID()}.tmp")
        temporary.outputStream().use { output ->
            output.write(bytes)
            output.flush()
            output.fd.sync()
        }
        check(temporary.renameTo(file)) { "Unable to persist Direct CLI job atomically." }
    }

    companion object {
        private const val JOURNAL_NAME = "job.json"
        private const val PENDING_NAME = "pending.json"
        private const val MAXIMUM_RETENTION_SECONDS = 7L * 24L * 60L * 60L
    }

    private data class PendingJob(
        val version: Int,
        val requestFingerprint: String,
        val expiresAt: String,
        val enginePin: ExportEnginePin?,
        val protocolPin: AndroidDirectProtocolPin?,
    )

    @Serializable
    private data class PendingJobWire(
        val version: Int? = null,
        val requestFingerprint: String,
        val expiresAt: String,
        val enginePin: JsonElement? = null,
        val protocolPin: AndroidDirectProtocolPin? = null,
    )
}

@Serializable(with = DirectJobJournal.Serializer::class)
data class DirectJobJournal(
    val version: Int = CURRENT_VERSION,
    val requestFingerprint: String,
    val expiresAt: String,
    val transfer: PreparedTransfer,
    val enginePin: ExportEnginePin? = null,
    val protocolPin: AndroidDirectProtocolPin? = null,
    val accounted: Boolean = false,
    val completed: Boolean = false,
) {
    init {
        require(version in SUPPORTED_VERSIONS) { "Unsupported Direct CLI journal version." }
        require(version != LEGACY_VERSION || enginePin == null) {
            "A v1 Direct CLI journal cannot contain an engine pin."
        }
        require(version >= PROTOCOL_PIN_VERSION || protocolPin == null) {
            "A pre-v3 Direct CLI journal cannot contain a protocol pin."
        }
        requireValidOptionalPin(enginePin)
        requireValidOptionalProtocolPin(protocolPin)
        require(enginePin == null || enginePin.ianaTimeZone == transfer.accepted.resolvedRange.timeZoneId) {
            "The Direct CLI resolved timezone changed after engine planning."
        }
    }

    object Serializer : KSerializer<DirectJobJournal> {
        override val descriptor: SerialDescriptor = Wire.serializer().descriptor

        override fun serialize(encoder: Encoder, value: DirectJobJournal) {
            val jsonEncoder = encoder as? JsonEncoder
                ?: throw SerializationException("DirectJobJournal supports JSON only.")
            val wire = Wire(
                version = value.version,
                requestFingerprint = value.requestFingerprint,
                expiresAt = value.expiresAt,
                transfer = value.transfer,
                enginePin = value.enginePin?.let {
                    CODEC.parseToJsonElement(ExportEnginePinCodec.encodeCanonical(it))
                },
                protocolPin = value.protocolPin,
                accounted = value.accounted,
                completed = value.completed,
            )
            jsonEncoder.encodeJsonElement(CODEC.encodeToJsonElement(Wire.serializer(), wire))
        }

        override fun deserialize(decoder: Decoder): DirectJobJournal {
            val jsonDecoder = decoder as? JsonDecoder
                ?: throw SerializationException("DirectJobJournal supports JSON only.")
            val wire = CODEC.decodeFromJsonElement(Wire.serializer(), jsonDecoder.decodeJsonElement())
            val version = wire.version ?: LEGACY_VERSION
            if (version !in SUPPORTED_VERSIONS) {
                throw SerializationException("Unsupported Direct CLI journal version.")
            }
            // Missing/older versions are authoritative: unexpected pin data cannot upgrade work.
            val pin = if (version == LEGACY_VERSION) null else decodeDurablePin(wire.enginePin)
            val protocolPin = if (version >= PROTOCOL_PIN_VERSION) wire.protocolPin else null
            return DirectJobJournal(
                version = version,
                requestFingerprint = wire.requestFingerprint,
                expiresAt = wire.expiresAt,
                transfer = wire.transfer,
                enginePin = pin,
                protocolPin = protocolPin,
                accounted = wire.accounted,
                completed = wire.completed,
            )
        }

        @Serializable
        private data class Wire(
            val version: Int? = null,
            val requestFingerprint: String,
            val expiresAt: String,
            val transfer: PreparedTransfer,
            val enginePin: JsonElement? = null,
            val protocolPin: AndroidDirectProtocolPin? = null,
            val accounted: Boolean = false,
            val completed: Boolean = false,
        )

        private val CODEC = Json {
            encodeDefaults = true
            explicitNulls = true
            ignoreUnknownKeys = false
        }
    }

    companion object {
        const val LEGACY_VERSION = 1
        const val EXPORT_PIN_VERSION = 2
        const val PROTOCOL_PIN_VERSION = 3
        const val CURRENT_VERSION = PROTOCOL_PIN_VERSION
        internal val SUPPORTED_VERSIONS = LEGACY_VERSION..CURRENT_VERSION
    }
}

internal fun requireDirectPinContinuity(
    pendingPin: ExportEnginePin?,
    journalPin: ExportEnginePin?,
) {
    require(pendingPin == journalPin) {
        "The Direct CLI engine pin changed after preparation began."
    }
}

internal fun requireDirectProtocolPinContinuity(
    pendingPin: AndroidDirectProtocolPin?,
    journalPin: AndroidDirectProtocolPin?,
) {
    require(pendingPin == journalPin) {
        "The Direct CLI protocol pin changed after preparation began."
    }
}

private fun decodeDurablePin(element: JsonElement?): ExportEnginePin? {
    if (element == null || element is JsonNull) return null
    return ExportEnginePinCodec.decodeOrNull(element.toString())
        ?: throw SerializationException("The durable Direct CLI engine pin is invalid.")
}

private fun requireValidOptionalPin(pin: ExportEnginePin?) {
    require(pin == null || pin.engine != ExportEngineMode.legacy) {
        "Legacy Direct CLI operations must omit the engine pin."
    }
    require(pin == null || ExportEnginePinCodec.isStructurallyValid(pin)) {
        "The Direct CLI engine pin is invalid."
    }
}

private fun requireValidOptionalProtocolPin(pin: AndroidDirectProtocolPin?) {
    require(pin == null || pin.engine != AndroidDirectProtocolEngineMode.legacy) {
        "Legacy Direct CLI operations must omit the protocol pin."
    }
    require(pin == null || pin.version == AndroidDirectProtocolPin.CURRENT_VERSION) {
        "The Direct CLI protocol pin is invalid."
    }
}
