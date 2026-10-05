package com.healthmd.data.export

import com.healthmd.domain.exportengine.sha256Hex
import java.io.File
import java.io.FileOutputStream
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.SimpleFileVisitor
import java.nio.file.FileVisitResult
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.BasicFileAttributes
import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Installation-private revocation, not portable authority. A bounded tombstone is committed before
 * unlink or pending-state removal. Every journal/staging mutation uses the same process-wide lock,
 * including different store instances. WorkManager cancellation is deliberately not this lock.
 * Tombstones are never evicted: at the bound, discard fails closed rather than admitting old work.
 */
internal class RecoveryDiscardFence(
    private val privateRoot: File,
    private val apiRoot: File = File(privateRoot, "scheduled-api-export-v1"),
    private val rawRoot: File = File(privateRoot, "scheduled-raw-api-v1"),
) {
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }
    private val ledger get() = File(privateRoot, "recovery-discard-v1.json")

    /** An expected local journal binding, not a grant and never exported. */
    data class Binding(val authorityJson: String?, val settingsSnapshotJson: String?)

    @Serializable
    private data class State(
        val version: Int,
        val operations: List<String>,
        val profileGenerations: List<String>,
        val defaultRequests: List<String>,
    )

    fun <T> withOperation(operationId: String, action: () -> T): T = synchronized(lock) {
        val hash = operationHash(operationId)
        val state = load()
        check(hash !in state.operations && admissionHash(operationId) !in state.defaultRequests) { "api_recovery_discarded" }
        checkRoot(apiRoot)
        checkRoot(rawRoot)
        check(!Files.isSymbolicLink(File(apiRoot, hash).toPath())) { "api_recovery_private_state_invalid" }
        check(!Files.isSymbolicLink(File(rawRoot, hash).toPath())) { "api_recovery_private_state_invalid" }
        action()
    }

    /**
     * Start the synchronous allocation segment under the mutation fence, then release at the first
     * real suspension. Scheduled raw capture pre-resolves provider metadata so native spool mkdirs
     * precedes that suspension. Later spool writes cannot recreate the unlinked parent directory.
     * Never hold a monitor across suspended provider work or wait for WorkManager teardown.
     */
    suspend fun <T> beginOperation(operationId: String, action: suspend () -> T): T =
        suspendCoroutineUninterceptedOrReturn { continuation ->
            withOperation(operationId) { action.startCoroutineUninterceptedOrReturn(continuation) }
        }

    fun isDiscarded(operationId: String): Boolean = synchronized(lock) {
        val state = load()
        operationHash(operationId) in state.operations || admissionHash(operationId) in state.defaultRequests
    }

    fun isProfileGenerationDiscarded(profileId: String, generation: Long): Boolean = synchronized(lock) {
        profileHash(profileId, generation) in load().profileGenerations
    }

    fun isDefaultRequestDiscarded(identityHash: String): Boolean = synchronized(lock) {
        require(HASH.matches(identityHash)) { "api_recovery_pending_identity_invalid" }
        identityHash in load().defaultRequests
    }

    /** Markers make the fence-before-DataStore crash window replayable without recomputing dates. */
    fun discard(operationIds: Collection<String>, profileId: String? = null, generation: Long = 0L,
        defaultRequestHashes: Collection<String> = emptyList(),
        expectedBindings: Map<String, Binding> = emptyMap()) = synchronized(lock) {
        require(defaultRequestHashes.all { HASH.matches(it) }) { "api_recovery_pending_identity_invalid" }
        val hashes = operationIds.map(::operationHash)
        val profile = profileId?.let { profileHash(it, generation) }
        val current = load()
        require(expectedBindings.keys.all { it in operationIds }) { "api_recovery_discard_binding_invalid" }
        verifyBindings(expectedBindings)
        val next = current.copy(
            operations = (current.operations + hashes).distinct().sorted(),
            profileGenerations = (current.profileGenerations + listOfNotNull(profile)).distinct().sorted(),
            defaultRequests = (current.defaultRequests + defaultRequestHashes).distinct().sorted(),
        )
        validate(next)
        if (next != current) save(next)
        // Replay all owned unlink intents, including a crash after the durable fence but before unlink.
        cleanup(next)
    }

    fun reconcile() = synchronized(lock) {
        try { cleanup(load()) } catch (_: Exception) { error("api_recovery_discard_cleanup_unavailable") }
    }

    private fun verifyBindings(bindings: Map<String, Binding>) {
        for ((id, expected) in bindings) for (root in listOf(apiRoot, rawRoot)) {
            checkRoot(root)
            val directory = File(root, operationHash(id))
            check(!Files.isSymbolicLink(directory.toPath())) { "api_recovery_discard_binding_invalid" }
            val metadata = File(directory, "journal.json")
            check(!Files.isSymbolicLink(metadata.toPath())) { "api_recovery_discard_binding_invalid" }
            // An unpublished/missing journal may still have operation-owned staging to purge.
            if (!metadata.exists()) continue
            try {
                check(metadata.isFile && metadata.length() in 1..MAX_LEDGER_BYTES)
                val stored = json.parseToJsonElement(metadata.readText()).jsonObject
                val authorityKey = if (root == apiRoot) "apiAuthorityJson" else "authorityJson"
                check(stored["operationId"]?.jsonPrimitive?.contentOrNull == id &&
                    stored[authorityKey]?.jsonPrimitive?.contentOrNull == expected.authorityJson &&
                    stored["settingsSnapshotJson"]?.jsonPrimitive?.contentOrNull == expected.settingsSnapshotJson)
            } catch (_: Exception) {
                error("api_recovery_discard_binding_invalid")
            }
        }
    }

    private fun load(): State {
        checkRoot(privateRoot)
        check(!Files.isSymbolicLink(ledger.toPath())) { "api_recovery_discard_state_invalid" }
        if (!ledger.exists()) return State(1, emptyList(), emptyList(), emptyList())
        check(ledger.isFile && ledger.length() in 1..MAX_LEDGER_BYTES) { "api_recovery_discard_state_invalid" }
        return try {
            json.decodeFromString<State>(ledger.readText()).also(::validate)
        } catch (_: Exception) {
            error("api_recovery_discard_state_invalid")
        }
    }

    private fun validate(state: State) {
        check(state.version == 1) { "api_recovery_discard_state_invalid" }
        for (hashes in listOf(state.operations, state.profileGenerations, state.defaultRequests)) {
            check(hashes.size <= MAX_TOMBSTONES && hashes == hashes.distinct().sorted() && hashes.all { HASH.matches(it) }) {
                "api_recovery_discard_state_invalid"
            }
        }
    }

    private fun save(state: State) {
        check(privateRoot.mkdirs() || privateRoot.isDirectory) { "api_recovery_discard_storage_unavailable" }
        val bytes = json.encodeToString(state).encodeToByteArray()
        check(bytes.size <= MAX_LEDGER_BYTES) { "api_recovery_discard_state_invalid" }
        val temporary = File(privateRoot, "recovery-discard-v1.tmp")
        check(!Files.isSymbolicLink(temporary.toPath())) { "api_recovery_discard_state_invalid" }
        FileOutputStream(temporary).use { it.write(bytes); it.flush(); it.fd.sync() }
        Files.move(temporary.toPath(), ledger.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        syncDirectory(privateRoot)
    }

    private fun cleanup(state: State) {
        for (root in listOf(apiRoot, rawRoot)) {
            checkRoot(root)
            if (!root.exists()) continue
            for (hash in state.operations) {
                deleteOwned(File(root, hash))
                // Compatibility create can die before its temporary directory is promoted.
            }
            val temporaryPattern = Regex("\\.([0-9a-f]{64})\\.(-?[0-9]{1,19})\\.tmp")
            val revoked = state.operations.toSet()
            root.listFiles().orEmpty().filter {
                val spelling = temporaryPattern.matchEntire(it.name)?.groupValues
                spelling != null && spelling[1] in revoked &&
                    spelling[2].toLongOrNull()?.toString() == spelling[2]
            }.forEach(::deleteOwned)
            syncDirectory(root)
        }
    }

    private fun deleteOwned(file: File) {
        if (!Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)) return
        // Never follow symlinks, including symlinks inside an owned operation directory.
        Files.walkFileTree(file.toPath(), object : SimpleFileVisitor<Path>() {
            override fun visitFile(path: Path, attributes: BasicFileAttributes): FileVisitResult {
                Files.delete(path)
                return FileVisitResult.CONTINUE
            }
            override fun postVisitDirectory(path: Path, error: java.io.IOException?): FileVisitResult {
                if (error != null) throw error
                Files.delete(path)
                return FileVisitResult.CONTINUE
            }
        })
    }

    private fun checkRoot(root: File) {
        val valid = runCatching {
            !Files.isSymbolicLink(privateRoot.toPath()) && !Files.isSymbolicLink(root.toPath()) &&
                (root.canonicalFile == privateRoot.canonicalFile || root.canonicalFile.parentFile == privateRoot.canonicalFile)
        }.getOrDefault(false)
        check(valid) { "api_recovery_private_state_invalid" }
    }

    companion object {
        private val lock = Any()
        private val HASH = Regex("[0-9a-f]{64}")
        internal const val MAX_TOMBSTONES = 4096
        private const val MAX_LEDGER_BYTES = 1_048_576L

        internal fun operationHash(operationId: String): String {
            require(operationId.matches(Regex("[A-Za-z0-9._-]{1,128}"))) { "api_recovery_operation_invalid" }
            return sha256Hex(operationId.encodeToByteArray())
        }

        internal fun admissionHash(operationId: String): String {
            operationHash(operationId) // Validate the exact native admission spelling first.
            return sha256Hex("healthmd-default-discard-admission-v1\n$operationId".encodeToByteArray())
        }

        private fun profileHash(profileId: String, generation: Long): String {
            require(profileId.length in 1..128 && generation >= 0) { "api_recovery_profile_invalid" }
            return sha256Hex("healthmd-profile-discard-v1\n$profileId\n$generation".encodeToByteArray())
        }

        internal fun syncDirectory(directory: File) {
            FileChannel.open(directory.toPath(), StandardOpenOption.READ).use { it.force(true) }
        }
    }
}
