package com.healthmd.sharedsetup

import android.net.Uri
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Singleton
class SharedSetupCoordinator internal constructor(
    private val documentStore: SharedSetupDocumentStore,
    /**
     * Dispatcher used to publish import results. A StateFlow resumes suspended
     * collectors undispatched on the publishing thread, so publishing must land
     * on the main dispatcher in production to keep collector bodies — navigation
     * and SavedStateHandle writes — on the main thread. Tests inject an
     * immediate dispatcher through this constructor.
     */
    private val publishDispatcher: CoroutineDispatcher,
) {
    @Inject
    constructor(documentStore: SharedSetupDocumentStore) : this(
        documentStore,
        Dispatchers.Main.immediate,
    )
    private val ids = AtomicLong()
    private val mutableImport = MutableStateFlow<PendingSharedSetupImport?>(null)
    private val externalReadScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val externalLock = Any()
    private var externalRequestID: Long = 0
    private var activeExternalRead: Job? = null
    private var latestExternalBytes: ByteArray? = null
    private var externalImportFinished = false
    val imports = mutableImport.asStateFlow()
    val processInstanceID: String = UUID.randomUUID().toString()

    /**
     * Owns external provider IO for the process rather than an Activity lifecycle. Rotation can
     * therefore skip replaying the retained launch intent without cancelling the accepted read.
     */
    fun acceptExternalUriAsync(uri: Uri) {
        lateinit var requestJob: Job
        val requestID = synchronized(externalLock) {
            externalRequestID += 1
            val id = externalRequestID
            latestExternalBytes = null
            externalImportFinished = false
            requestJob = externalReadScope.launch(start = CoroutineStart.LAZY) {
                try {
                    // ContentResolver reads are blocking and may ignore coroutine cancellation.
                    // The newest request gets its own IO job; only its generation may publish.
                    val result = readExternal(uri)
                    // Publish on the main dispatcher. A StateFlow resumes suspended collectors
                    // undispatched on the publishing thread, so publishing from this IO worker
                    // would run collector bodies — navigation and SavedStateHandle writes —
                    // on the IO thread. NavController mutation from a background thread
                    // half-applies a back-stack entry and later crashes activity destroy with
                    // "State must be at least CREATED to move to DESTROYED". Main-thread
                    // publication keeps every consumer on the main thread.
                    withContext(publishDispatcher) {
                        result
                            .onSuccess { bytes -> publishExternalBytes(id, bytes) }
                            .onFailure { error -> publishExternalFailure(id, error) }
                    }
                } finally {
                    synchronized(externalLock) {
                        if (activeExternalRead === requestJob) activeExternalRead = null
                    }
                }
            }
            activeExternalRead?.cancel()
            activeExternalRead = requestJob
            id
        }
        check(requestID > 0)
        requestJob.start()
    }

    /** Copies an untrusted content URI immediately; no persisted URI grant is assumed or kept. */
    fun acceptExternalUri(uri: Uri): Result<Unit> {
        val requestID = synchronized(externalLock) {
            externalRequestID += 1
            activeExternalRead?.cancel()
            activeExternalRead = null
            latestExternalBytes = null
            externalImportFinished = false
            externalRequestID
        }
        val result = readExternal(uri)
        result.onSuccess { bytes -> publishExternalBytes(requestID, bytes) }
            .onFailure { error -> publishExternalFailure(requestID, error) }
        return result.map { }
    }

    fun restoreExternalBytes(bytes: ByteArray) {
        require(bytes.size <= SHARED_SETUP_MAX_BYTES)
        synchronized(externalLock) {
            externalRequestID += 1
            activeExternalRead?.cancel()
            activeExternalRead = null
            latestExternalBytes = bytes.copyOf()
            externalImportFinished = false
            mutableImport.value = PendingSharedSetupImport(
                ids.incrementAndGet(),
                bytes = bytes.copyOf(),
            )
        }
    }

    fun restorableExternalBytes(): ByteArray? = synchronized(externalLock) {
        latestExternalBytes?.copyOf()
    }

    fun isExternalImportFinished(): Boolean = synchronized(externalLock) {
        externalImportFinished
    }

    fun finishExternalImport() {
        synchronized(externalLock) {
            externalRequestID += 1
            activeExternalRead?.cancel()
            activeExternalRead = null
            latestExternalBytes = null
            externalImportFinished = true
            mutableImport.value = null
        }
    }

    private fun readExternal(uri: Uri): Result<ByteArray> = runCatching {
        require(documentStore.isSharedSetupDocument(uri)) {
            "Choose a .$SHARED_SETUP_EXTENSION Health.md setup document."
        }
        documentStore.read(uri)
    }

    private fun publishExternalBytes(requestID: Long, bytes: ByteArray) {
        require(bytes.size <= SHARED_SETUP_MAX_BYTES)
        synchronized(externalLock) {
            if (externalRequestID != requestID) return
            latestExternalBytes = bytes.copyOf()
            externalImportFinished = false
            mutableImport.value = PendingSharedSetupImport(
                ids.incrementAndGet(),
                bytes = bytes.copyOf(),
            )
        }
    }

    private fun publishExternalFailure(requestID: Long, error: Throwable) {
        synchronized(externalLock) {
            if (externalRequestID != requestID) return
            mutableImport.value = PendingSharedSetupImport(
                id = ids.incrementAndGet(),
                errorMessage = error.message?.take(300)
                    ?: "The shared setup document could not be opened.",
            )
        }
    }

    fun acceptBytes(bytes: ByteArray) {
        restoreExternalBytes(bytes)
    }

}
