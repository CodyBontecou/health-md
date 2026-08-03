package com.healthmd.widget.data

import android.content.Context
import com.healthmd.widget.model.HealthWidgetSnapshot
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import javax.inject.Inject

interface HealthWidgetSnapshotStore {
    suspend fun load(): HealthWidgetSnapshot?
    suspend fun save(snapshot: HealthWidgetSnapshot)
    suspend fun delete()
}

/** Atomic credential-protected storage that is excluded from backup and device transfer. */
class NoBackupHealthWidgetSnapshotStore internal constructor(
    private val root: File,
    private val ioDispatcher: CoroutineDispatcher,
    private val json: Json,
) : HealthWidgetSnapshotStore {
    @Inject
    constructor(
        @ApplicationContext context: Context,
    ) : this(
        root = File(context.noBackupFilesDir, DIRECTORY_NAME),
        ioDispatcher = Dispatchers.IO,
        json = defaultJson(),
    )

    private val lock = Mutex()
    private val snapshotFile: File get() = File(root, SNAPSHOT_FILE_NAME)

    override suspend fun load(): HealthWidgetSnapshot? = withContext(ioDispatcher) {
        lock.withLock {
            val file = snapshotFile
            if (!file.isFile || file.length() <= 0L || file.length() > MAX_SNAPSHOT_BYTES) {
                return@withLock null
            }
            val decoded = runCatching {
                json.decodeFromString(HealthWidgetSnapshot.serializer(), file.readText(Charsets.UTF_8))
            }.getOrNull()
            decoded?.takeIf(HealthWidgetSnapshot::isValid)
        }
    }

    override suspend fun save(snapshot: HealthWidgetSnapshot) = withContext(ioDispatcher) {
        require(snapshot.isValid()) { "Refusing to persist an invalid health widget snapshot." }
        val bytes = json.encodeToString(HealthWidgetSnapshot.serializer(), snapshot)
            .toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_SNAPSHOT_BYTES) { "Health widget snapshot exceeds its storage limit." }

        lock.withLock {
            check(root.exists() || root.mkdirs()) { "Unable to create health widget storage." }
            durableReplace(snapshotFile, bytes)
        }
    }

    override suspend fun delete() = withContext(ioDispatcher) {
        lock.withLock {
            if (root.exists()) {
                check(root.deleteRecursively()) { "Unable to delete health widget storage." }
            }
        }
    }

    private fun durableReplace(file: File, bytes: ByteArray) {
        val temporary = File(file.parentFile, ".${file.name}.${System.nanoTime()}.tmp")
        try {
            FileOutputStream(temporary).use { stream ->
                stream.write(bytes)
                stream.flush()
                stream.fd.sync()
            }
            moveAtomically(temporary, file)
            syncDirectory(requireNotNull(file.parentFile))
        } finally {
            temporary.delete()
        }
    }

    private fun moveAtomically(source: File, target: File) {
        try {
            Files.move(
                source.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun syncDirectory(directory: File) {
        runCatching { FileOutputStream(directory).use { it.fd.sync() } }
    }

    companion object {
        private const val DIRECTORY_NAME = "health-widgets"
        private const val SNAPSHOT_FILE_NAME = "health-widget-snapshot-v1.json"
        private const val MAX_SNAPSHOT_BYTES = 256 * 1024L

        private fun defaultJson(): Json = Json {
            encodeDefaults = true
            ignoreUnknownKeys = true
            explicitNulls = false
        }
    }
}
