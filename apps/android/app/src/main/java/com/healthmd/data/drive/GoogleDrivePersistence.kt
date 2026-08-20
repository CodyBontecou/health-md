package com.healthmd.data.drive

import android.content.Context
import android.content.SharedPreferences
import android.util.AtomicFile
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import com.healthmd.domain.exportengine.sha256Hex
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

interface GoogleDriveAccountAuthorityStore {
    suspend fun save(referenceId: String, accountName: String)
    suspend fun accountName(referenceId: String): String?
    suspend fun remove(referenceId: String)
}

@Singleton
class EncryptedGoogleDriveAccountAuthorityStore @Inject constructor(
    @ApplicationContext context: Context,
) : GoogleDriveAccountAuthorityStore {
    private val preferences: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "health_md_google_drive_account_authority",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override suspend fun save(referenceId: String, accountName: String) = withContext(Dispatchers.IO) {
        require(referenceId.isSafeOpaqueId() && accountName.isNotBlank())
        check(preferences.edit().putString("account:$referenceId", accountName).commit())
    }

    override suspend fun accountName(referenceId: String): String? = withContext(Dispatchers.IO) {
        preferences.getString("account:$referenceId", null)
    }

    override suspend fun remove(referenceId: String) = withContext(Dispatchers.IO) {
        check(preferences.edit().remove("account:$referenceId").commit())
    }
}

@Serializable
private data class DriveDestinationEnvelope(
    val version: Int = 1,
    val records: List<JsonElement> = emptyList(),
)

/** Per-record tolerant persistence: unknown kinds/versions survive every known-record mutation. */
@Singleton
class GoogleDriveDestinationStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
    private val accountStore: GoogleDriveAccountAuthorityStore,
) {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }
    private val key = stringPreferencesKey("export_destinations_v1")

    suspend fun all(): List<GoogleDriveDestination> = rawRecords().mapNotNull(::decodeKnown)

    suspend fun find(id: String): GoogleDriveDestination? = all().firstOrNull { it.id == id }

    suspend fun save(destination: GoogleDriveDestination, accountName: String) {
        accountStore.save(destination.accountReferenceId, accountName)
        dataStore.edit { prefs ->
            val records = decodeEnvelope(prefs[key]).toMutableList()
            val index = records.indexOfFirst { recordId(it) == destination.id }
            val encoded = json.encodeToJsonElement(GoogleDriveDestination.serializer(), destination)
            if (index >= 0) records[index] = encoded else records += encoded
            prefs[key] = json.encodeToString(
                DriveDestinationEnvelope.serializer(),
                DriveDestinationEnvelope(records = records),
            )
        }
    }

    suspend fun remove(id: String) {
        val destination = find(id)
        dataStore.edit { prefs ->
            val kept = decodeEnvelope(prefs[key]).filterNot { recordId(it) == id }
            prefs[key] = json.encodeToString(
                DriveDestinationEnvelope.serializer(),
                DriveDestinationEnvelope(records = kept),
            )
        }
        destination?.let { accountStore.remove(it.accountReferenceId) }
    }

    suspend fun accountName(destination: GoogleDriveDestination): String? =
        accountStore.accountName(destination.accountReferenceId)

    suspend fun hasOpaqueRecords(): Boolean = rawRecords().any { decodeKnown(it) == null }

    private suspend fun rawRecords(): List<JsonElement> =
        decodeEnvelope(dataStore.data.first()[key])

    private fun decodeEnvelope(raw: String?): List<JsonElement> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val root = json.parseToJsonElement(raw)
            when (root) {
                is JsonArray -> root.toList() // additive migration from a pre-envelope prototype
                is JsonObject -> root["records"]?.let { it as? JsonArray }?.toList().orEmpty()
                else -> emptyList()
            }
        }.getOrDefault(emptyList())
    }

    private fun decodeKnown(element: JsonElement): GoogleDriveDestination? = runCatching {
        val objectValue = element.jsonObject
        if (objectValue["kind"]?.jsonPrimitive?.content != GoogleDriveDestination.KIND) return null
        val version = objectValue["version"]?.jsonPrimitive?.intOrNull ?: 1
        if (version !in 1..GoogleDriveDestination.CURRENT_VERSION) return null
        json.decodeFromJsonElement(GoogleDriveDestination.serializer(), element)
    }.getOrNull()

    private fun recordId(element: JsonElement): String? = runCatching {
        element.jsonObject["id"]?.jsonPrimitive?.content
    }.getOrNull()
}

@Serializable
private data class ManagedObjectEnvelope(
    val version: Int = 1,
    val records: List<JsonElement> = emptyList(),
)

sealed interface GoogleDriveManagedObjectLookup {
    data object Missing : GoogleDriveManagedObjectLookup
    /** Malformed, unknown-version, opaque, or duplicate state is never treated as absence. */
    data object Corrupt : GoogleDriveManagedObjectLookup
    data class Found(val binding: GoogleDriveManagedObject) : GoogleDriveManagedObjectLookup
}

@Singleton
class GoogleDriveManagedObjectStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }
    private val key = stringPreferencesKey("google_drive_managed_objects_v1")

    suspend fun lookup(destinationId: String, pathHash: String): GoogleDriveManagedObjectLookup =
        when (val loaded = load(dataStore.data.first()[key])) {
            ManagedObjectRecords.Corrupt -> GoogleDriveManagedObjectLookup.Corrupt
            is ManagedObjectRecords.Valid -> loaded.bindings
                .singleOrNull { it.destinationId == destinationId && it.relativePathHash == pathHash }
                ?.let(GoogleDriveManagedObjectLookup::Found)
                ?: GoogleDriveManagedObjectLookup.Missing
        }

    suspend fun isMutationSafe(): Boolean =
        load(dataStore.data.first()[key]) is ManagedObjectRecords.Valid

    suspend fun put(binding: GoogleDriveManagedObject) {
        dataStore.edit { prefs ->
            val loaded = load(prefs[key])
            check(loaded is ManagedObjectRecords.Valid) { "managed object store is corrupt" }
            val records = loaded.bindings.toMutableList()
            val index = records.indexOfFirst {
                it.destinationId == binding.destinationId && it.relativePathHash == binding.relativePathHash
            }
            if (index >= 0) records[index] = binding else records += binding
            prefs[key] = encode(records)
        }
    }

    suspend fun removeDestination(destinationId: String) {
        dataStore.edit { prefs ->
            val loaded = load(prefs[key])
            check(loaded is ManagedObjectRecords.Valid) { "managed object store is corrupt" }
            prefs[key] = encode(loaded.bindings.filterNot { it.destinationId == destinationId })
        }
    }

    private fun encode(bindings: List<GoogleDriveManagedObject>): String = json.encodeToString(
        ManagedObjectEnvelope.serializer(),
        ManagedObjectEnvelope(
            records = bindings.map {
                json.encodeToJsonElement(GoogleDriveManagedObject.serializer(), it)
            },
        ),
    )

    private fun load(raw: String?): ManagedObjectRecords {
        if (raw.isNullOrBlank()) return ManagedObjectRecords.Valid(emptyList())
        return runCatching {
            val root = json.parseToJsonElement(raw) as? JsonObject ?: error("invalid envelope")
            val version = root["version"]?.jsonPrimitive?.intOrNull ?: 1
            if (version != 1) error("unknown envelope")
            val elements = root["records"] as? JsonArray ?: error("missing records")
            val bindings = elements.map { element ->
                val objectValue = element as? JsonObject ?: error("opaque record")
                val recordVersion = objectValue["version"]?.jsonPrimitive?.intOrNull ?: 1
                if (recordVersion != 1) error("unknown record")
                json.decodeFromJsonElement(GoogleDriveManagedObject.serializer(), element).also {
                    if (!it.destinationId.isSafeOpaqueId() ||
                        !it.relativePathHash.matches(Regex("[0-9a-f]{64}")) ||
                        it.objectId.isBlank() || it.parentId.isBlank() || it.expectedName.isBlank() ||
                        it.mimeType.isBlank()
                    ) error("invalid record")
                }
            }
            if (bindings.distinctBy { it.destinationId to it.relativePathHash }.size != bindings.size) {
                error("duplicate binding")
            }
            ManagedObjectRecords.Valid(bindings)
        }.getOrElse { ManagedObjectRecords.Corrupt }
    }

    private sealed interface ManagedObjectRecords {
        data object Corrupt : ManagedObjectRecords
        data class Valid(val bindings: List<GoogleDriveManagedObject>) : ManagedObjectRecords
    }
}

@Serializable
enum class GoogleDriveArtifactPhase {
    PREPARED,
    BASELINE_STAGED,
    FINAL_BYTES_STAGED,
    ID_RESERVED,
    SESSION_STARTED,
    UPLOADING,
    COMMITTED,
    VERIFIED,
    HISTORY_ACKNOWLEDGED,
}

@Serializable
data class GoogleDriveJournalArtifact(
    val artifactId: String,
    val relativePathHash: String,
    val relativePath: String,
    val mediaType: String,
    val writeIntent: GeneratedArtifactWriteIntent,
    val spoolFile: String,
    val byteCount: Long,
    val sha256: String,
    val missingPrefixFile: String? = null,
    val createIfMissing: Boolean = true,
    val phase: GoogleDriveArtifactPhase = GoogleDriveArtifactPhase.PREPARED,
    val objectId: String? = null,
    val parentId: String? = null,
    val objectResourceKey: String? = null,
    val baselineVersion: String? = null,
    val baselineSize: Long? = null,
    val baselineMd5: String? = null,
    val baselineSha256: String? = null,
    val resumableSessionUri: String? = null,
    val acknowledgedOffset: Long = 0,
)

@Serializable
data class GoogleDriveOperationJournal(
    val version: Int = CURRENT_VERSION,
    val operationId: String,
    val profileId: String? = null,
    val source: String,
    val ownerDates: List<String>,
    val destinationId: String,
    val destinationFingerprint: String,
    val bundleDigest: String,
    val settingsSnapshotSha256: String,
    val rendererPin: String,
    val artifacts: List<GoogleDriveJournalArtifact>,
    /** Generated IDs are persisted before folder/file create so ambiguous responses reconcile. */
    val reservedObjectIds: Map<String, String> = emptyMap(),
    val completedArtifactCount: Int = 0,
    val historyAcknowledged: Boolean = false,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
) {
    companion object { const val CURRENT_VERSION = 1 }
}

sealed interface GoogleDriveJournalLoad {
    data object Missing : GoogleDriveJournalLoad
    data object Corrupt : GoogleDriveJournalLoad
    data class Found(val journal: GoogleDriveOperationJournal) : GoogleDriveJournalLoad
}

/** Private no-backup atomic journal and spool. AtomicFile plus fsync covers file durability. */
@Singleton
class GoogleDriveJournalStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val root = File(context.noBackupFilesDir, "google-drive-operations")
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    suspend fun create(
        bundle: GeneratedExportBundle,
        destination: GoogleDriveDestination,
    ): GoogleDriveOperationJournal = withContext(Dispatchers.IO) {
        require(root.mkdirs() || root.isDirectory)
        val directory = operationDirectory(bundle.operationId)
        if (directory.exists()) error("operation already exists")
        require(directory.mkdirs())
        syncDirectory(root)
        val artifacts = bundle.artifacts.mapIndexed { index, artifact ->
            val spoolName = "artifact-${index.toString().padStart(4, '0')}.bin"
            writeAtomic(File(directory, spoolName), artifact.bytes)
            val prefixName = artifact.missingPrefix?.let { bytes ->
                "artifact-${index.toString().padStart(4, '0')}.prefix".also { name ->
                    writeAtomic(File(directory, name), bytes)
                }
            }
            GoogleDriveJournalArtifact(
                artifactId = artifact.artifactId,
                relativePathHash = relativePathHash(destination.id, artifact.relativePath),
                relativePath = artifact.relativePath,
                mediaType = artifact.mediaType,
                writeIntent = artifact.writeIntent,
                spoolFile = spoolName,
                byteCount = artifact.byteCount,
                sha256 = artifact.sha256,
                missingPrefixFile = prefixName,
                createIfMissing = artifact.createIfMissing,
            )
        }
        val now = System.currentTimeMillis()
        val journal = GoogleDriveOperationJournal(
            operationId = bundle.operationId,
            profileId = bundle.profileId,
            source = bundle.source,
            ownerDates = bundle.dates.map(LocalDate::toString),
            destinationId = destination.id,
            destinationFingerprint = destination.fingerprint,
            bundleDigest = bundle.digest,
            settingsSnapshotSha256 = bundle.settingsSnapshotSha256,
            rendererPin = bundle.rendererPin,
            artifacts = artifacts,
            createdAtEpochMillis = now,
            updatedAtEpochMillis = now,
        )
        save(journal)
        journal
    }

    suspend fun load(operationId: String): GoogleDriveJournalLoad = withContext(Dispatchers.IO) {
        if (!operationId.isSafeOpaqueId()) return@withContext GoogleDriveJournalLoad.Corrupt
        val directory = operationDirectory(operationId)
        val file = File(directory, JOURNAL_FILE)
        if (!file.exists()) return@withContext GoogleDriveJournalLoad.Missing
        val journal = runCatching {
            val bytes = AtomicFile(file).readFully()
            if (bytes.size > MAX_JOURNAL_BYTES) error("oversize")
            json.decodeFromString(GoogleDriveOperationJournal.serializer(), bytes.toString(StandardCharsets.UTF_8))
        }.getOrNull() ?: return@withContext GoogleDriveJournalLoad.Corrupt
        if (!validate(journal, directory)) GoogleDriveJournalLoad.Corrupt else GoogleDriveJournalLoad.Found(journal)
    }

    suspend fun save(journal: GoogleDriveOperationJournal) = withContext(Dispatchers.IO) {
        require(validate(journal, operationDirectory(journal.operationId), requireJournalFile = false))
        val updated = journal.copy(updatedAtEpochMillis = System.currentTimeMillis())
        writeAtomic(
            File(operationDirectory(journal.operationId), JOURNAL_FILE),
            json.encodeToString(GoogleDriveOperationJournal.serializer(), updated).encodeToByteArray(),
        )
    }

    suspend fun readArtifact(operationId: String, artifact: GoogleDriveJournalArtifact): ByteArray? =
        withContext(Dispatchers.IO) {
            readChecked(operationDirectory(operationId), artifact.spoolFile, artifact.byteCount, artifact.sha256)
        }

    suspend fun readMissingPrefix(operationId: String, artifact: GoogleDriveJournalArtifact): ByteArray? =
        withContext(Dispatchers.IO) {
            artifact.missingPrefixFile?.let { name ->
                runCatching { File(operationDirectory(operationId), name).readBytes() }.getOrNull()
            }
        }

    suspend fun replaceFinalBytes(
        journal: GoogleDriveOperationJournal,
        artifactIndex: Int,
        bytes: ByteArray,
        phase: GoogleDriveArtifactPhase = GoogleDriveArtifactPhase.FINAL_BYTES_STAGED,
    ): GoogleDriveOperationJournal = withContext(Dispatchers.IO) {
        val artifact = journal.artifacts[artifactIndex]
        val digest = sha256Hex(bytes)
        val spoolName = "artifact-${artifactIndex.toString().padStart(4, '0')}-final-$digest.bin"
        val directory = operationDirectory(journal.operationId)
        // Never overwrite the currently referenced spool. A crash before save leaves it intact;
        // save atomically switches the journal to the newly durable immutable name.
        if (artifact.spoolFile != spoolName) writeAtomic(File(directory, spoolName), bytes)
        val updatedArtifact = artifact.copy(
            spoolFile = spoolName,
            byteCount = bytes.size.toLong(),
            sha256 = digest,
            phase = phase,
        )
        journal.copy(artifacts = journal.artifacts.replacing(artifactIndex, updatedArtifact)).also {
            save(it)
            if (artifact.spoolFile != spoolName) File(directory, artifact.spoolFile).delete()
        }
    }

    suspend fun discard(operationId: String) = withContext(Dispatchers.IO) {
        operationDirectory(operationId).deleteRecursively()
        syncDirectory(root)
    }

    suspend fun pruneAcknowledged(keep: Int = 20) = withContext(Dispatchers.IO) {
        val acknowledged = root.listFiles().orEmpty()
            .filter(File::isDirectory)
            .mapNotNull { directory ->
                val operationId = directory.name.takeIf(String::isSafeOpaqueId) ?: return@mapNotNull null
                val found = load(operationId) as? GoogleDriveJournalLoad.Found ?: return@mapNotNull null
                found.journal.takeIf { journal ->
                    journal.historyAcknowledged && journal.artifacts.all {
                        it.phase == GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED
                    }
                }?.let { directory }
            }
            .sortedByDescending(File::lastModified)
        acknowledged.drop(keep.coerceAtLeast(0)).forEach(File::deleteRecursively)
        syncDirectory(root)
    }

    private fun validate(
        journal: GoogleDriveOperationJournal,
        directory: File,
        requireJournalFile: Boolean = true,
    ): Boolean {
        if (journal.version !in 1..GoogleDriveOperationJournal.CURRENT_VERSION ||
            !journal.operationId.isSafeOpaqueId() ||
            journal.artifacts.isEmpty() ||
            journal.artifacts.map { it.relativePathHash }.distinct().size != journal.artifacts.size ||
            (requireJournalFile && !File(directory, JOURNAL_FILE).exists())
        ) return false
        return journal.artifacts.all { artifact ->
            artifact.artifactId.isSafeOpaqueId() &&
                normalizeDriveRelativePath(artifact.relativePath) == artifact.relativePath &&
                artifact.spoolFile.matches(
                    Regex("artifact-[0-9]{4}(?:-final-[0-9a-f]{64})?\\.bin"),
                ) &&
                artifact.byteCount >= 0 &&
                artifact.sha256.matches(Regex("[0-9a-f]{64}")) &&
                File(directory, artifact.spoolFile).let { it.isFile && it.length() == artifact.byteCount }
        }
    }

    private fun readChecked(directory: File, name: String, size: Long, sha256: String): ByteArray? = runCatching {
        val file = File(directory, name)
        if (!file.isFile || file.length() != size || file.length() > MAX_SPOOL_BYTES) return null
        file.readBytes().takeIf { sha256Hex(it) == sha256 }
    }.getOrNull()

    private fun operationDirectory(operationId: String): File {
        require(operationId.isSafeOpaqueId())
        return File(root, operationId)
    }

    private fun writeAtomic(file: File, bytes: ByteArray) {
        require(bytes.size <= MAX_SPOOL_BYTES)
        file.parentFile?.let { require(it.mkdirs() || it.isDirectory) }
        val atomic = AtomicFile(file)
        val output = atomic.startWrite()
        try {
            output.write(bytes)
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
            file.parentFile?.let(::syncDirectory)
        } catch (error: Throwable) {
            atomic.failWrite(output)
            throw error
        }
    }

    private fun syncDirectory(directory: File) {
        runCatching { FileOutputStream(directory).use { it.fd.sync() } }
    }

    private fun <T> List<T>.replacing(index: Int, value: T): List<T> =
        toMutableList().apply { set(index, value) }

    companion object {
        private const val JOURNAL_FILE = "journal.json"
        private const val MAX_JOURNAL_BYTES = 2 * 1024 * 1024
        private const val MAX_SPOOL_BYTES = 256 * 1024 * 1024
    }
}
