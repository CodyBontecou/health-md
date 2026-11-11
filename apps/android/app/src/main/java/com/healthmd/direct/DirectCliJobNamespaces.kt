package com.healthmd.direct

import com.healthmd.core.HEALTHMD_SLEEP_REGISTRY_SHA256
import com.healthmd.core.HealthMdCoreService
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import java.io.File
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Private placement; never encoded into a journal, protocol pin, or packet. */
internal enum class DirectJobNamespace(val directoryName: String) {
    HISTORICAL("jobs"),
    WAKE_DATE("jobs-sleep-attribution-v6");

    companion object {
        fun forPin(pin: ExportEnginePin?): DirectJobNamespace {
            if (pin?.profile != AndroidExportProfile.android_sleep_v6) return HISTORICAL
            require(ExportEnginePinCodec.isStructurallyValid(pin) &&
                pin.registrySha256 == HEALTHMD_SLEEP_REGISTRY_SHA256 &&
                pin.semanticProfileRevision == ExportEnginePin.EXPECTED_SEMANTIC_PROFILE_REVISION &&
                pin.renderProfileRevision == HealthMdCoreService.EXPECTED_RENDER_PROFILE_REVISION) {
                "The successor Direct CLI authority is unavailable."
            }
            return WAKE_DATE
        }
    }
}

/** Routes immutable operations to sibling stores under one purge-independent lock. */
@Singleton
class DirectCliJobStore private constructor(trustStore: DirectCliTrustStore, directorySync: (File) -> Boolean) {
    @Inject
    constructor(trustStore: DirectCliTrustStore) : this(trustStore, {
        DirectCliNamespaceJobStore.syncDirectoryOnAndroid(it)
    })

    internal constructor(trustStore: DirectCliTrustStore, @Suppress("UNUSED_PARAMETER") testOnly: Unit,
        directorySync: (File) -> Boolean) : this(trustStore, directorySync)

    private val stores = DirectJobNamespace.entries.associateWith {
        DirectCliNamespaceJobStore(File(trustStore.rootDirectory(), it.directoryName), it, directorySync)
    }
    private val historical = stores.getValue(DirectJobNamespace.HISTORICAL)

    private fun canonicalId(jobId: String): String {
        require(UUID.fromString(jobId).toString() == jobId) { "Invalid Direct CLI job identity." }
        return jobId
    }

    private fun find(jobId: String): DirectCliNamespaceJobStore? {
        canonicalId(jobId)
        val candidates = stores.values.filter { it.contains(jobId) }
        check(candidates.size <= 1) { "The Direct CLI job has ambiguous storage authority." }
        return candidates.singleOrNull()?.also { it.validatePlacement(jobId) }
    }

    private fun <T> inspect(jobId: String, missing: () -> T, action: (DirectCliNamespaceJobStore) -> T): T {
        canonicalId(jobId)
        if (stores.values.none { it.contains(jobId) }) return missing()
        return historical.transaction { find(jobId)?.let(action) ?: missing() }
    }

    private fun <T> select(jobId: String, pin: ExportEnginePin?, action: (DirectCliNamespaceJobStore) -> T): T =
        historical.transaction {
            canonicalId(jobId)
            val selected = stores.getValue(DirectJobNamespace.forPin(pin))
            val existing = find(jobId)
            check(existing == null || existing === selected) { "The Direct CLI job namespace changed." }
            action(selected)
        }

    private fun <T> owned(lease: DirectPreparationLease, action: (DirectCliNamespaceJobStore) -> T): T {
        canonicalId(lease.jobId)
        val selected = stores.getValue(lease.namespace)
        check(selected.contains(lease.jobId)) { "The Direct CLI operation is unavailable." }
        return historical.transaction {
            check(selected.contains(lease.jobId) && stores.values.none { it !== selected && it.contains(lease.jobId) }) {
                "The Direct CLI operation has ambiguous storage authority."
            }
            // Each fixed store validates the retained token/image. Frames need not
            // re-decode an entire transfer plan merely to select their namespace.
            action(selected)
        }
    }

    private fun sweepLocked(now: Instant) {
        val duplicates = stores.values.flatMap { it.jobIds() }.groupingBy { it }.eachCount()
            .filterValues { it > 1 }.keys
        stores.values.forEach { it.sweepExpired(now, duplicates) }
    }

    fun load(jobId: String, requestFingerprint: String): DirectJobJournal? = inspect(jobId, { null }) {
        sweepLocked(Instant.now())
        it.load(jobId, requestFingerprint)
    }

    fun hasIncompletePreparation(jobId: String, requestFingerprint: String): Boolean = inspect(jobId, { false }) {
        sweepLocked(Instant.now())
        it.hasIncompletePreparation(jobId, requestFingerprint)
    }

    fun beginPreparation(jobId: String, requestFingerprint: String, expiresAt: String,
        enginePin: ExportEnginePin? = null, protocolPin: AndroidDirectProtocolPin? = null): DirectPreparationLease =
        select(jobId, enginePin) { it.beginPreparation(jobId, requestFingerprint, expiresAt, enginePin, protocolPin) }

    fun savePrepared(journal: DirectJobJournal, lease: DirectPreparationLease) = owned(lease) {
        check(DirectJobNamespace.forPin(journal.enginePin) == lease.namespace) { "The Direct CLI renderer namespace changed." }
        it.savePrepared(journal, lease)
    }

    fun save(journal: DirectJobJournal) = select(journal.transfer.accepted.jobId, journal.enginePin) {
        check(it.namespace == DirectJobNamespace.HISTORICAL || it.contains(journal.transfer.accepted.jobId)) {
            "A successor Direct CLI job requires accepted preparation ownership."
        }
        it.save(journal)
    }

    fun acquireAcceptedLease(expected: DirectJobJournal): DirectAcceptedLease =
        inspect(expected.transfer.accepted.jobId, { error("The Direct CLI operation is unavailable.") }) {
            check(it.namespace == DirectJobNamespace.forPin(expected.enginePin)) { "The Direct CLI renderer namespace changed." }
            it.acquireAcceptedLease(expected)
        }

    fun validatePreparationLease(lease: DirectPreparationLease) = owned(lease) { it.validatePreparationLease(lease) }
    fun validateAcceptedLease(lease: DirectAcceptedLease) = owned(lease.owner) { it.validateAcceptedLease(lease) }
    fun <T> withAcceptedOwnership(lease: DirectAcceptedLease, action: () -> T): T =
        owned(lease.owner) { it.withAcceptedOwnership(lease, action) }
    fun <T> withPreparationOwnership(lease: DirectPreparationLease, action: () -> T): T =
        owned(lease) { it.withPreparationOwnership(lease, action) }
    fun directory(lease: DirectPreparationLease): File = owned(lease) { it.directory(lease) }

    fun cancelPreparation(lease: DirectPreparationLease): Boolean = inspect(lease.jobId, { false }) {
        if (it.namespace != lease.namespace) false else it.cancelPreparation(lease)
    }
    fun cancelAccepted(lease: DirectAcceptedLease): Boolean = inspect(lease.owner.jobId, { false }) {
        if (it.namespace != lease.owner.namespace) false else it.cancelAccepted(lease)
    }
    fun markAccounted(lease: DirectAcceptedLease, account: () -> Unit = {}): Boolean =
        owned(lease.owner) { it.markAccounted(lease, account) }
    fun markCompleted(lease: DirectAcceptedLease, complete: () -> Unit = {}): Boolean =
        owned(lease.owner) { it.markCompleted(lease, complete) }

    fun packetSendAuthorization(lease: DirectAcceptedLease) =
        com.healthmd.direct.protocol.DirectPacketSendAuthorization { enqueue ->
            owned(lease.owner) { it.packetSendAuthorization(lease).authorizeEnqueue(enqueue) }
        }
    fun cancelAcceptedPacketSendAuthorization(lease: DirectAcceptedLease, onRevoked: () -> Unit = {}) =
        com.healthmd.direct.protocol.DirectPacketSendAuthorization { enqueue ->
            owned(lease.owner) { it.cancelAcceptedPacketSendAuthorization(lease, onRevoked).authorizeEnqueue(enqueue) }
        }
    fun preparationPacketSendAuthorization(lease: DirectPreparationLease, cancelBeforeEnqueue: Boolean = false,
        onRevoked: () -> Unit = {}) = com.healthmd.direct.protocol.DirectPacketSendAuthorization { enqueue ->
            owned(lease) { it.preparationPacketSendAuthorization(lease, cancelBeforeEnqueue, onRevoked).authorizeEnqueue(enqueue) }
        }

    fun cancel(jobId: String) = inspect(jobId, { Unit }) { it.cancel(jobId) }
    fun purgeAll() = historical.transaction { stores.values.forEach { it.purgeAll() } }
    fun sweepExpired(now: Instant = Instant.now()) {
        if (stores.values.none { it.storageExists() }) return
        historical.transaction { sweepLocked(now) }
    }
}
