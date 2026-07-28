package com.healthmd.rawchanges

import android.content.Context
import android.system.Os
import android.system.OsConstants
import com.healthmd.rawexport.HealthConnectRecordCatalog
import com.healthmd.rawexport.RawExportTypeCatalog
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawIssue
import com.healthmd.rawexport.RawJson
import com.healthmd.rawexport.RawProviderCapabilities
import com.healthmd.rawexport.RawTypeCount
import java.io.BufferedWriter
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.io.FilterOutputStream
import java.io.OutputStream
import java.nio.channels.FileChannel
import java.nio.file.StandardOpenOption
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.time.Instant

internal class RawChangesEventSpool(private val file: File) : Closeable {
    private val stream = FileOutputStream(file, false)
    private val writer: BufferedWriter = stream.bufferedWriter(Charsets.UTF_8)
    var count: Long = 0; private set

    fun append(event: RawChangeEvent) {
        writer.append(RawChangesCanonical.canonicalEvent(event))
        writer.newLine()
        count++
    }

    fun durableClose() {
        writer.flush()
        stream.fd.sync()
        writer.close()
    }

    fun forEach(block: (RawChangeEvent) -> Unit) {
        file.bufferedReader(Charsets.UTF_8).useLines { lines ->
            lines.filter(String::isNotBlank).forEach { line ->
                block(RawJson.codec.decodeFromString(RawChangeEvent.serializer(), line))
            }
        }
    }

    override fun close() = runCatching { writer.close() }.let { }
}

internal data class PreparedChangesArtifact(
    val partialFile: File,
    val finalFile: File,
    val logicalHash: String,
    val artifactHash: String,
    val bytesWritten: Long,
)

internal class NoBackupRawChangesDestination private constructor(
    private val root: File,
    private val directorySync: (File) -> Unit,
) {
    constructor(context: Context) : this(File(context.noBackupFilesDir, "raw-changes/archives"), ::forceDirectory)
    internal constructor(
        noBackupRoot: File,
        forTests: Boolean,
        directorySync: (File) -> Unit = ::forceDirectory,
    ) : this(File(noBackupRoot, "raw-changes/archives"), directorySync)

    init { root.mkdirs() }

    fun files(archiveId: String): Pair<File, File> =
        File(root, "$archiveId.json.partial") to File(root, "$archiveId.json")

    fun promote(prepared: PreparedChangesArtifact): File {
        prepared.partialFile.inputStream().use { require(RawJson.sha256(it) == prepared.artifactHash) { "Prepared archive checksum mismatch." } }
        if (prepared.finalFile.exists()) {
            prepared.finalFile.inputStream().use {
                require(RawJson.sha256(it) == prepared.artifactHash) { "An archive ID already exists with different content." }
            }
            require(prepared.partialFile.delete()) { "Unable to remove duplicate prepared archive." }
            makeFileAndParentDurable(prepared.finalFile)
            return prepared.finalFile
        }
        require(prepared.partialFile.renameTo(prepared.finalFile)) { "Unable to atomically promote incremental archive." }
        makeFileAndParentDurable(prepared.finalFile)
        return prepared.finalFile
    }

    fun writeSidecar(finalFile: File, artifactHash: String): File {
        val sidecar = File(finalFile.parentFile, "${finalFile.name}.sha256")
        val expected = "$artifactHash  ${finalFile.name}\n"
        makeFileAndParentDurable(finalFile)
        if (sidecar.exists()) {
            require(sidecar.readText(Charsets.UTF_8) == expected) { "Incremental archive sidecar mismatch." }
            makeFileAndParentDurable(sidecar)
            return sidecar
        }
        val parent = requireNotNull(sidecar.parentFile)
        val partial = File(parent, "${sidecar.name}.partial")
        FileOutputStream(partial, false).use { output ->
            output.write(expected.toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
        require(partial.renameTo(sidecar)) { "Unable to promote incremental checksum sidecar." }
        makeFileAndParentDurable(sidecar)
        return sidecar
    }

    fun finalFile(archiveId: String): File = File(root, "$archiveId.json")
    fun sidecarFile(archiveId: String): File = File(root, "$archiveId.json.sha256")

    fun removePartial(archiveId: String) { files(archiveId).first.delete() }

    fun makeFileAndParentDurable(file: File) {
        java.io.FileInputStream(file).use { it.fd.sync() }
        directorySync(requireNotNull(file.parentFile))
    }
}

/** Failure is propagated: a platform that cannot fsync a directory must not advance token state. */
private fun forceDirectory(directory: File) {
    if (System.getProperty("java.vm.name").equals("Dalvik", ignoreCase = true)) {
        val descriptor = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
        try {
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    } else {
        // Host-JVM unit tests and desktop tooling do not expose android.system.Os.
        FileChannel.open(directory.toPath(), StandardOpenOption.READ).use { it.force(true) }
    }
}

internal data class RawChangesAccounting(
    var eventCount: Long = 0,
    var upsertionCount: Long = 0,
    var deletionCount: Long = 0,
    var unknownDeletionCount: Long = 0,
    var pageCount: Long = 0,
    val upsertsByType: MutableMap<String, Long> = linkedMapOf(),
    val deletionsByType: MutableMap<String, Long> = linkedMapOf(),
)

internal class RawChangesArtifactWriter {
    fun write(
        header: RawChangesHeader,
        completedAt: Instant,
        spool: RawChangesEventSpool,
        issues: List<RawIssue>,
        accounting: RawChangesAccounting,
        capabilities: RawProviderCapabilities,
        partialFile: File,
        finalFile: File,
    ): PreparedChangesArtifact {
        partialFile.parentFile?.mkdirs()
        val artifactDigest = MessageDigest.getInstance("SHA-256")
        val logicalDigest = MessageDigest.getInstance("SHA-256")
        val fileStream = FileOutputStream(partialFile, false)
        val counting = CountingOutputStream(DigestOutputStream(fileStream, artifactDigest))

        fun logical(kind: String, canonical: String) {
            logicalDigest.update(kind.toByteArray(Charsets.UTF_8))
            logicalDigest.update(0)
            logicalDigest.update(canonical.toByteArray(Charsets.UTF_8))
            logicalDigest.update('\n'.code.toByte())
        }

        val headerJson = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawChangesHeader.serializer(), header))
        logical("header", headerJson)
        counting.utf8("{\"header\":$headerJson,\"events\":[")
        var first = true
        spool.forEach { event ->
            val canonical = RawChangesCanonical.canonicalEvent(event)
            if (!first) counting.utf8(",")
            first = false
            counting.utf8(canonical)
            logical("event", canonical)
        }
        counting.utf8("],\"issues\":[")
        first = true
        issues.forEach { issue ->
            val canonical = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue))
            if (!first) counting.utf8(",")
            first = false
            counting.utf8(canonical)
            logical("issue", canonical)
        }
        counting.utf8("],\"manifest\":")

        val typeCounts = ((accounting.upsertsByType.keys + accounting.deletionsByType.keys).map { type ->
            RawTypeCount(type, (accounting.upsertsByType[type] ?: 0) + (accounting.deletionsByType[type] ?: 0))
        } + listOfNotNull(
            accounting.unknownDeletionCount.takeIf { it > 0 }?.let { RawTypeCount("unknown_deletion", it) },
        )).sortedBy { it.wireType }
        val selected = header.recordTypeKeys.toSet()
        val reports = HealthConnectRecordCatalog.records.map { descriptor ->
            val status = when {
                descriptor.wireType !in selected -> RawChangesTypeStatus.NOT_SELECTED
                descriptor.featureName != null && descriptor.featureName !in capabilities.availableFeatures -> RawChangesTypeStatus.FEATURE_UNAVAILABLE
                descriptor.readPermission !in capabilities.grantedPermissions -> RawChangesTypeStatus.PERMISSION_NOT_GRANTED
                else -> RawChangesTypeStatus.EXPORTED
            }
            RawChangesTypeReport(
                typeKey = descriptor.wireType,
                wireType = descriptor.wireType,
                status = status,
                upsertionCount = accounting.upsertsByType[descriptor.wireType] ?: 0,
                deletionCount = accounting.deletionsByType[descriptor.wireType] ?: 0,
                permission = descriptor.readPermission,
                feature = descriptor.featureName,
            )
        } + RawExportTypeCatalog.medicalTypes.map { medical ->
            RawChangesTypeReport(
                typeKey = medical.typeKey,
                wireType = "medical_resource",
                status = RawChangesTypeStatus.UNSUPPORTED_CHANGES_API,
                permission = medical.permission,
                feature = RawExportTypeCatalog.PHR_FEATURE_NAME,
                message = "Health Connect getChanges does not expose PHR medical-resource changes or deletions.",
            )
        }
        val logicalHash = logicalDigest.digest().hex()
        val unsigned = RawChangesManifest(
            archiveId = header.archiveId,
            chainId = header.chainId,
            sequence = header.sequence,
            completedAt = RawInstant(completedAt.epochSecond, completedAt.nano),
            eventCount = accounting.eventCount,
            upsertionCount = accounting.upsertionCount,
            deletionCount = accounting.deletionCount,
            unknownDeletionCount = accounting.unknownDeletionCount,
            issueCount = issues.size.toLong(),
            pageCount = accounting.pageCount,
            typeCounts = typeCounts,
            typeReports = reports.sortedBy { it.typeKey },
            logicalChecksumSha256 = logicalHash,
            manifestChecksumSha256 = "",
        )
        val manifest = unsigned.copy(manifestChecksumSha256 = RawChangesCanonical.manifestHash(unsigned))
        val manifestJson = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawChangesManifest.serializer(), manifest))
        counting.utf8("$manifestJson}")
        counting.flush()
        fileStream.fd.sync()
        counting.close()
        return PreparedChangesArtifact(partialFile, finalFile, logicalHash, artifactDigest.digest().hex(), counting.count)
    }

    private class CountingOutputStream(output: OutputStream) : FilterOutputStream(output) {
        var count: Long = 0; private set
        override fun write(value: Int) { out.write(value); count++ }
        override fun write(buffer: ByteArray, offset: Int, length: Int) { out.write(buffer, offset, length); count += length }
        fun utf8(value: String) = write(value.toByteArray(Charsets.UTF_8))
    }

    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }
}
