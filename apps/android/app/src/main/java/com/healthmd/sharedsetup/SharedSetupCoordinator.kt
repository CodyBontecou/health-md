package com.healthmd.sharedsetup

import android.net.Uri
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

@Singleton
class SharedSetupCoordinator @Inject constructor(
    private val documentStore: SharedSetupDocumentStore,
) {
    private val ids = AtomicLong()
    private val externalRequestIDs = AtomicLong()
    private val mutableImport = MutableStateFlow<PendingSharedSetupImport?>(null)
    private val externalReadScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val externalReadMutex = Mutex()
    private val externalStateLock = Any()
    private var latestExternalBytes: ByteArray? = null
    private var externalImportFinished = false
    val imports = mutableImport.asStateFlow()
    val processInstanceID: String = UUID.randomUUID().toString()

    /**
     * Owns external provider IO for the process rather than an Activity lifecycle. Rotation can
     * therefore skip replaying the retained launch intent without cancelling the accepted read.
     */
    fun acceptExternalUriAsync(uri: Uri) {
        val requestID = externalRequestIDs.incrementAndGet()
        synchronized(externalStateLock) {
            latestExternalBytes = null
            externalImportFinished = false
        }
        externalReadScope.launch {
            externalReadMutex.withLock {
                val result = readExternal(uri)
                if (externalRequestIDs.get() != requestID) return@withLock
                result.onSuccess { bytes ->
                    rememberExternalBytes(bytes)
                    acceptBytes(bytes)
                }.onFailure(::publishExternalFailure)
            }
        }
    }

    /** Copies an untrusted content URI immediately; no persisted URI grant is assumed or kept. */
    fun acceptExternalUri(uri: Uri): Result<Unit> {
        externalRequestIDs.incrementAndGet()
        synchronized(externalStateLock) {
            latestExternalBytes = null
            externalImportFinished = false
        }
        val result = readExternal(uri)
        result.onSuccess { bytes ->
            rememberExternalBytes(bytes)
            acceptBytes(bytes)
        }.onFailure(::publishExternalFailure)
        return result.map { }
    }

    fun restoreExternalBytes(bytes: ByteArray) {
        externalRequestIDs.incrementAndGet()
        rememberExternalBytes(bytes)
        acceptBytes(bytes)
    }

    fun restorableExternalBytes(): ByteArray? = synchronized(externalStateLock) {
        latestExternalBytes?.copyOf()
    }

    fun isExternalImportFinished(): Boolean = synchronized(externalStateLock) {
        externalImportFinished
    }

    fun finishExternalImport() {
        externalRequestIDs.incrementAndGet()
        synchronized(externalStateLock) {
            latestExternalBytes = null
            externalImportFinished = true
        }
        mutableImport.value = null
    }

    private fun readExternal(uri: Uri): Result<ByteArray> = runCatching {
        require(documentStore.isSharedSetupDocument(uri)) {
            "Choose a .$SHARED_SETUP_EXTENSION Health.md setup document."
        }
        documentStore.read(uri)
    }

    private fun rememberExternalBytes(bytes: ByteArray) {
        synchronized(externalStateLock) {
            latestExternalBytes = bytes.copyOf()
            externalImportFinished = false
        }
    }

    private fun publishExternalFailure(error: Throwable) {
        mutableImport.value = PendingSharedSetupImport(
            id = ids.incrementAndGet(),
            errorMessage = error.message?.take(300) ?: "The shared setup document could not be opened.",
        )
    }

    fun acceptBytes(bytes: ByteArray) {
        require(bytes.size <= SHARED_SETUP_MAX_BYTES)
        mutableImport.value = PendingSharedSetupImport(ids.incrementAndGet(), bytes = bytes.copyOf())
    }

    fun consume(id: Long) {
        if (mutableImport.value?.id == id) mutableImport.value = null
    }
}
