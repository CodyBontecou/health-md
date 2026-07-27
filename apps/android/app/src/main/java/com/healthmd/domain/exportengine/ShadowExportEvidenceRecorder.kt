package com.healthmd.domain.exportengine

import android.content.Context
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Persisted evidence has counters only; its type cannot represent health or operation data. */
@Serializable
internal data class AndroidShadowExportEvidenceSnapshot(
    val schema: String = SCHEMA,
    val version: Int = VERSION,
    val profiles: List<AndroidShadowExportProfileEvidence> = emptyList(),
) {
    companion object {
        const val SCHEMA = "healthmd.android_shadow_export_evidence"
        const val VERSION = 1
        val EMPTY = AndroidShadowExportEvidenceSnapshot()
    }
}

@Serializable
internal data class AndroidShadowExportProfileEvidence(
    val profile: String,
    val semanticProfileRevision: UInt,
    val renderProfileRevision: UInt,
    val comparisonCount: Long = 0,
    val exactMatchCount: Long = 0,
    val mismatchOperationCount: Long = 0,
    val reportedMismatchCount: Long = 0,
    val rustFailureCount: Long = 0,
    val mismatchDimensions: Map<String, Long> = emptyMap(),
    val rustFailureCodes: Map<String, Long> = emptyMap(),
)

internal sealed interface AndroidShadowEvidenceEvent {
    val profile: AndroidExportProfile
    val semanticProfileRevision: UInt
    val renderProfileRevision: UInt

    data class Comparison(
        override val profile: AndroidExportProfile,
        override val semanticProfileRevision: UInt,
        override val renderProfileRevision: UInt,
        val matches: Boolean,
        val mismatchCount: Int,
        val dimensions: Set<ExportArtifactMismatchDimension>,
    ) : AndroidShadowEvidenceEvent

    data class RustFailure(
        override val profile: AndroidExportProfile,
        override val semanticProfileRevision: UInt,
        override val renderProfileRevision: UInt,
        val code: ShadowRustFailureCode,
    ) : AndroidShadowEvidenceEvent

    companion object {
        fun from(diagnostic: ShadowExportDiagnostic): AndroidShadowEvidenceEvent = when (diagnostic) {
            is ShadowComparisonDiagnostic -> Comparison(
                profile = diagnostic.profile,
                semanticProfileRevision = diagnostic.semanticProfileRevision,
                renderProfileRevision = diagnostic.renderProfileRevision,
                matches = diagnostic.comparison.matches,
                mismatchCount = diagnostic.comparison.mismatches.size,
                dimensions = diagnostic.comparison.dimensions,
            )
            is ShadowRustFailureDiagnostic -> RustFailure(
                profile = diagnostic.profile,
                semanticProfileRevision = diagnostic.semanticProfileRevision,
                renderProfileRevision = diagnostic.renderProfileRevision,
                code = diagnostic.code,
            )
        }
    }
}

/**
 * App-private, no-backup aggregate store. Corruption resets evidence instead of affecting exports.
 * Writes are atomic and all counters saturate rather than wrapping.
 */
internal class FileAndroidShadowExportEvidenceStore(
    private val file: File,
) {
    private val lock = Any()
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = false
    }

    fun record(event: AndroidShadowEvidenceEvent) = synchronized(lock) {
        if (event.semanticProfileRevision == 0u || event.renderProfileRevision == 0u) return@synchronized
        val snapshot = loadLocked()
        val profiles = snapshot.profiles.toMutableList()
        val index = profiles.indexOfFirst {
            it.profile == event.profile.name &&
                it.semanticProfileRevision == event.semanticProfileRevision &&
                it.renderProfileRevision == event.renderProfileRevision
        }
        var profile = profiles.getOrNull(index) ?: AndroidShadowExportProfileEvidence(
            profile = event.profile.name,
            semanticProfileRevision = event.semanticProfileRevision,
            renderProfileRevision = event.renderProfileRevision,
        )
        profile = when (event) {
            is AndroidShadowEvidenceEvent.Comparison -> profile.copy(
                comparisonCount = saturatedAdd(profile.comparisonCount),
                exactMatchCount = if (event.matches) saturatedAdd(profile.exactMatchCount)
                else profile.exactMatchCount,
                mismatchOperationCount = if (event.matches) profile.mismatchOperationCount
                else saturatedAdd(profile.mismatchOperationCount),
                reportedMismatchCount = saturatedAdd(
                    profile.reportedMismatchCount,
                    event.mismatchCount.toLong(),
                ),
                mismatchDimensions = profile.mismatchDimensions.incremented(
                    event.dimensions.map(ExportArtifactMismatchDimension::name),
                ),
            )
            is AndroidShadowEvidenceEvent.RustFailure -> profile.copy(
                rustFailureCount = saturatedAdd(profile.rustFailureCount),
                rustFailureCodes = profile.rustFailureCodes.incremented(listOf(event.code.name)),
            )
        }
        if (index >= 0) profiles[index] = profile else profiles += profile
        persist(
            AndroidShadowExportEvidenceSnapshot(
                profiles = profiles.sortedWith(
                    compareBy<AndroidShadowExportProfileEvidence>(
                        { it.profile },
                        { it.semanticProfileRevision },
                        { it.renderProfileRevision },
                    ),
                ),
            ),
        )
    }

    fun snapshot(): AndroidShadowExportEvidenceSnapshot = synchronized(lock) { loadLocked() }

    fun reset() = synchronized(lock) {
        if (file.exists()) check(file.delete())
    }

    private fun loadLocked(): AndroidShadowExportEvidenceSnapshot {
        if (!file.exists()) return AndroidShadowExportEvidenceSnapshot.EMPTY
        return runCatching {
            require(file.isFile && file.length() in 1..MAX_PERSISTED_BYTES.toLong())
            val bytes = file.readBytes()
            val text = bytes.decodeToString()
            require(text.encodeToByteArray().contentEquals(bytes))
            json.decodeFromString<AndroidShadowExportEvidenceSnapshot>(text).also(::validate)
        }.getOrElse { AndroidShadowExportEvidenceSnapshot.EMPTY }
    }

    private fun validate(snapshot: AndroidShadowExportEvidenceSnapshot) {
        require(snapshot.schema == AndroidShadowExportEvidenceSnapshot.SCHEMA)
        require(snapshot.version == AndroidShadowExportEvidenceSnapshot.VERSION)
        require(snapshot.profiles.size <= MAX_PROFILES)
        snapshot.profiles.forEach { profile ->
            require(AndroidExportProfile.entries.any { it.name == profile.profile })
            require(profile.semanticProfileRevision > 0u && profile.renderProfileRevision > 0u)
            require(
                listOf(
                    profile.comparisonCount,
                    profile.exactMatchCount,
                    profile.mismatchOperationCount,
                    profile.reportedMismatchCount,
                    profile.rustFailureCount,
                ).all { it >= 0 },
            )
            require(profile.mismatchDimensions.all { (key, value) ->
                ExportArtifactMismatchDimension.entries.any { it.name == key } && value >= 0
            })
            require(profile.rustFailureCodes.all { (key, value) ->
                ShadowRustFailureCode.entries.any { it.name == key } && value >= 0
            })
        }
    }

    private fun persist(snapshot: AndroidShadowExportEvidenceSnapshot) {
        val bytes = json.encodeToString(snapshot).encodeToByteArray()
        require(bytes.size <= MAX_PERSISTED_BYTES)
        val parent = requireNotNull(file.parentFile)
        check(parent.mkdirs() || parent.isDirectory)
        val temporary = File(parent, ".${file.name}.${System.nanoTime()}.tmp")
        try {
            FileOutputStream(temporary).use { stream ->
                stream.write(bytes)
                stream.flush()
                stream.fd.sync()
            }
            try {
                Files.move(
                    temporary.toPath(),
                    file.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
                Files.move(
                    temporary.toPath(),
                    file.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                )
            }
        } finally {
            temporary.delete()
        }
    }

    private fun Map<String, Long>.incremented(keys: Collection<String>): Map<String, Long> {
        if (keys.isEmpty()) return this
        val next = toMutableMap()
        keys.forEach { key -> next[key] = saturatedAdd(next[key] ?: 0) }
        return next.toSortedMap()
    }

    private fun saturatedAdd(value: Long, amount: Long = 1): Long = when {
        amount <= 0 -> value
        value >= Long.MAX_VALUE - amount -> Long.MAX_VALUE
        else -> value + amount
    }

    private companion object {
        const val MAX_PERSISTED_BYTES = 64 * 1_024
        const val MAX_PROFILES = 16
    }
}

/** Production sink: reduce synchronously to a closed event, then persist off the caller thread. */
@Singleton
class AndroidShadowExportEvidenceRecorder @Inject constructor(
    @ApplicationContext context: Context,
) : ShadowExportDiagnosticSink {
    private val store = FileAndroidShadowExportEvidenceStore(
        File(context.noBackupFilesDir, "shared-core-shadow-evidence-v1.json"),
    )
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun emit(diagnostic: ShadowExportDiagnostic) {
        val event = AndroidShadowEvidenceEvent.from(diagnostic)
        when (event) {
            is AndroidShadowEvidenceEvent.Comparison -> {
                val outcome = if (event.matches) "exact_match" else "mismatch"
                val dimensions = event.dimensions
                    .map(ExportArtifactMismatchDimension::name)
                    .sorted()
                    .joinToString(",")
                Log.i(
                    TAG,
                    "profile=${event.profile.name} semantic=${event.semanticProfileRevision} " +
                        "render=${event.renderProfileRevision} outcome=$outcome " +
                        "mismatch_count=${event.mismatchCount} dimensions=$dimensions",
                )
            }
            is AndroidShadowEvidenceEvent.RustFailure -> Log.i(
                TAG,
                "profile=${event.profile.name} semantic=${event.semanticProfileRevision} " +
                    "render=${event.renderProfileRevision} rust_failure=${event.code.name}",
            )
        }
        scope.launch { runCatching { store.record(event) } }
    }

    internal suspend fun snapshot(): AndroidShadowExportEvidenceSnapshot =
        withContext(Dispatchers.IO) { store.snapshot() }

    internal suspend fun reset() {
        withContext(Dispatchers.IO) { runCatching { store.reset() } }
    }

    private companion object {
        const val TAG = "HealthMdSharedCore"
    }
}
