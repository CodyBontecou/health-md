package com.healthmd.rawexport

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.security.MessageDigest

data class RawPromotionExpectation(
    val byteCount: Long,
    val checksumSha256: String,
) {
    init {
        require(byteCount >= 0)
        require(checksumSha256.matches(Regex("[0-9a-f]{64}")))
    }
}

data class RawPromotionReceipt(
    val location: String,
    val displayName: String,
    val byteCount: Long,
    val checksumSha256: String,
)

interface RawAtomicExportSink : AutoCloseable {
    val output: OutputStream
    val partialLocation: String
    /** Promote only after the final artifact itself matches the exact partial-byte expectation. */
    fun promote(expectation: RawPromotionExpectation, checkCancellation: () -> Unit = {}): RawPromotionReceipt
    /** Deletes both partial and any just-promoted final when finalization is cancelled or fails. */
    fun abort()
}

interface RawExportStorage {
    fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink
}

private val PRIVATE_ARTIFACT_NAME = Regex("^[0-9a-f]{32}\\.(json|ndjson)(\\.partial)?$")

internal fun cleanupAbandonedPrivateArtifacts(root: File, activePaths: Set<String>) {
    root.listFiles()?.filter {
        it.isFile && PRIVATE_ARTIFACT_NAME.matches(it.name) && it.absolutePath !in activePaths
    }?.forEach { check(it.delete()) { "Unable to clean an abandoned private raw snapshot artifact." } }
}

internal fun cleanupAbandonedFilePartials(root: File, activePaths: Set<String>) {
    root.listFiles()?.filter {
        it.isFile && it.name.endsWith(".partial") && PRIVATE_ARTIFACT_NAME.matches(it.name) &&
            it.absolutePath !in activePaths
    }?.forEach { check(it.delete()) { "Unable to clean an abandoned raw snapshot partial." } }
}

/** Storage capable of publishing a checksum only after verified snapshot promotion. */
interface RawIntegrityStorage {
    fun writeIntegrityArtifact(snapshotId: String, format: RawExportFormat, checksumSha256: String): String
}

/** Internal storage rooted exactly at noBackupFilesDir/raw-export. */
class NoBackupRawExportStorage(context: Context) : RawExportStorage {
    private val root = File(context.noBackupFilesDir, "raw-export").apply { mkdirs() }

    init {
        synchronized(partialLock) {
            // Once per process is startup cleanup: it removes crash-left completed API artifacts while
            // never racing a final artifact produced by another live export in this process.
            if (!privateStartupCleanupDone) {
                cleanupAbandonedPrivateArtifacts(root, activePartials + activeFinals)
                privateStartupCleanupDone = true
            }
        }
    }

    override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink = synchronized(partialLock) {
        val extension = if (format == RawExportFormat.JSON) "json" else "ndjson"
        val partial = File(root, "$snapshotId.$extension.partial")
        val final = File(root, "$snapshotId.$extension")
        cleanupAbandonedFilePartials(root, activePartials)
        check(!final.exists()) { "Raw snapshot already exists and is immutable." }
        activePartials += partial.absolutePath
        FileAtomicSink(partial, final) { promoted ->
            synchronized(partialLock) {
                activePartials -= partial.absolutePath
                if (promoted) activeFinals += final.absolutePath else activeFinals -= final.absolutePath
            }
        }
    }

    private class FileAtomicSink(
        private val partial: File,
        private val final: File,
        private val release: (Boolean) -> Unit,
    ) : RawAtomicExportSink {
        private var closed = false
        private var promoted = false
        private var released = false
        override val output: OutputStream = FileOutputStream(partial, false)
        override val partialLocation: String get() = partial.absolutePath

        override fun promote(expectation: RawPromotionExpectation, checkCancellation: () -> Unit): RawPromotionReceipt {
            closeOutput()
            checkCancellation()
            check(partial.exists()) { "Partial artifact is missing" }
            verifyRawPromotionFile(partial, expectation, checkCancellation)
            synchronized(partialLock) {
                checkCancellation()
                check(!final.exists()) { "Raw snapshot already exists and is immutable." }
                check(partial.renameTo(final)) { "Unable to atomically promote raw snapshot" }
            }
            try {
                verifyRawPromotionFile(final, expectation, checkCancellation)
                checkCancellation()
            } catch (error: Throwable) {
                final.delete()
                throw error
            }
            promoted = true
            releaseOnce(true)
            return RawPromotionReceipt(final.absolutePath, final.name, expectation.byteCount, expectation.checksumSha256)
        }

        override fun abort() {
            closeOutput()
            partial.delete()
            if (promoted) final.delete()
            promoted = false
            releaseOnce(false)
        }

        override fun close() = closeOutput()
        private fun closeOutput() {
            if (!closed) {
                output.flush(); output.close(); closed = true
            }
        }
        private fun releaseOnce(wasPromoted: Boolean) {
            if (!released) { released = true; release(wasPromoted) }
            else if (!wasPromoted) release(false)
        }
    }

    companion object {
        private val partialLock = Any()
        private val activePartials = mutableSetOf<String>()
        private val activeFinals = mutableSetOf<String>()
        private var privateStartupCleanupDone = false
    }
}

/**
 * SAF tree adapter. The final document is created only after the completed partial has been closed,
 * copied, and verified byte-for-byte by count and SHA-256. Providers do not offer atomic rename.
 */
class SafRawExportStorage(
    private val context: Context,
    private val treeUri: Uri,
    relativeDirectory: String = "",
    stableNamePrefix: String? = null,
) : RawExportStorage, RawIntegrityStorage {
    private val resolver = context.contentResolver
    private val directorySegments = relativeDirectory.split('/').map(String::trim).filter(String::isNotEmpty)
    private val namePrefix = stableNamePrefix?.trim()?.takeIf(String::isNotEmpty)
    private val verifiedPromotions = mutableMapOf<Pair<String, RawExportFormat>, RawPromotionReceipt>()

    override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink = synchronized(partialLock) {
        val mime = if (format == RawExportFormat.JSON) "application/vnd.healthmd.raw-snapshot+json" else "application/x-ndjson"
        val parent = resolveDirectory()
        val finalName = finalName(snapshotId, format)
        check(findChild(parent, finalName) == null) { "Raw snapshot already exists and is immutable." }
        // Only Health.md names for this destination are eligible; unrelated user *.partial files survive.
        partialChildren(parent).filter { child ->
            child.uri.toString() !in activeSafPartials && isOwnedPartialName(child.displayName)
        }.forEach {
            check(DocumentsContract.deleteDocument(resolver, it.uri)) {
                "Unable to clean an abandoned raw snapshot partial."
            }
        }
        val partialName = "$finalName.partial"
        findChild(parent, partialName)?.let { stale ->
            check(DocumentsContract.deleteDocument(resolver, stale)) {
                "Unable to replace an abandoned raw snapshot partial."
            }
        }
        val partial = requireNotNull(
            DocumentsContract.createDocument(resolver, parent, mime, partialName),
        ) { "Unable to create SAF partial document" }
        check(displayName(partial) == partialName) { "SAF provider changed the immutable raw snapshot partial name." }
        activeSafPartials += partial.toString()
        SafSink(resolver, treeUri, parent, partial, finalName, mime, {
            synchronized(partialLock) { activeSafPartials -= partial.toString() }
        }) { receipt ->
            synchronized(partialLock) { verifiedPromotions[snapshotId to format] = receipt }
        }
    }

    override fun writeIntegrityArtifact(
        snapshotId: String,
        format: RawExportFormat,
        checksumSha256: String,
    ): String = synchronized(partialLock) {
        require(checksumSha256.matches(Regex("[0-9a-f]{64}"))) { "Invalid SHA-256 checksum" }
        val receipt = requireNotNull(verifiedPromotions[snapshotId to format]) {
            "Cannot publish integrity metadata before verified snapshot promotion."
        }
        require(receipt.checksumSha256 == checksumSha256) { "Checksum does not identify the promoted artifact." }
        val artifact = Uri.parse(receipt.location)
        require(displayName(artifact) == receipt.displayName) { "Promoted artifact name changed before sidecar publication." }
        verifyUri(resolver, artifact, RawPromotionExpectation(receipt.byteCount, checksumSha256)) {}
        val parent = resolveDirectory()
        require(findChild(parent, receipt.displayName)?.toString() == artifact.toString()) {
            "Promoted artifact is no longer bound to its immutable name."
        }
        val sidecarName = "${receipt.displayName}.sha256"
        check(findChild(parent, sidecarName) == null) { "Raw snapshot checksum already exists and is immutable." }
        val sidecar = requireNotNull(
            DocumentsContract.createDocument(resolver, parent, CHECKSUM_MIME_TYPE, sidecarName),
        ) { "Unable to create raw snapshot checksum" }
        try {
            check(displayName(sidecar) == sidecarName) { "SAF provider changed the raw snapshot checksum name." }
            requireNotNull(resolver.openOutputStream(sidecar, "wt")).bufferedWriter(Charsets.UTF_8).use {
                it.write("$checksumSha256  ${receipt.displayName}\n")
            }
        } catch (error: Throwable) {
            runCatching { DocumentsContract.deleteDocument(resolver, sidecar) }
            throw error
        }
        sidecar.toString()
    }

    fun finalName(snapshotId: String, format: RawExportFormat): String =
        stableFileName(namePrefix, snapshotId, format)

    private fun isOwnedPartialName(displayName: String): Boolean {
        val prefix = namePrefix?.let { Regex.escape(it) + "-" }.orEmpty()
        return displayName.matches(Regex("^$prefix[0-9a-f]{32}\\.(json|ndjson)\\.partial$"))
    }

    private fun resolveDirectory(): Uri {
        var current = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        directorySegments.forEach { segment ->
            require(segment != "." && segment != ".." && !segment.contains('\\')) {
                "Invalid raw snapshot directory"
            }
            current = findChild(current, segment) ?: requireNotNull(
                DocumentsContract.createDocument(
                    resolver,
                    current,
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    segment,
                ),
            ) { "Unable to create raw snapshot directory" }
        }
        return current
    }

    private data class Child(val uri: Uri, val displayName: String)

    private fun partialChildren(parent: Uri): List<Child> {
        val parentId = DocumentsContract.getDocumentId(parent)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val output = mutableListOf<Child>()
        resolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameIndex)
                if (name.endsWith(".partial")) {
                    output += Child(DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(idIndex)), name)
                }
            }
        }
        return output
    }

    private fun findChild(parent: Uri, expectedDisplayName: String): Uri? {
        val parentId = DocumentsContract.getDocumentId(parent)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        resolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex) == expectedDisplayName) {
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(idIndex))
                }
            }
        }
        return null
    }

    private fun displayName(uri: Uri): String? = displayName(resolver, uri)

    companion object {
        private const val CHECKSUM_MIME_TYPE = "application/vnd.healthmd.sha256"
        private val partialLock = Any()
        private val activeSafPartials = mutableSetOf<String>()

        fun stableFileName(prefix: String?, snapshotId: String, format: RawExportFormat): String {
            val extension = if (format == RawExportFormat.JSON) "json" else "ndjson"
            return listOfNotNull(prefix?.trim()?.takeIf(String::isNotEmpty), snapshotId)
                .joinToString("-") + ".$extension"
        }

        private fun displayName(resolver: ContentResolver, uri: Uri): String? = resolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) null else cursor.getString(
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            )
        }
    }

    private class SafSink(
        private val resolver: ContentResolver,
        private val treeUri: Uri,
        private val parent: Uri,
        private val partial: Uri,
        private val finalName: String,
        private val mime: String,
        private val release: () -> Unit,
        private val recordPromotion: (RawPromotionReceipt) -> Unit,
    ) : RawAtomicExportSink {
        private var closed = false
        private var promoted = false
        private var final: Uri? = null
        private var released = false
        override val output: OutputStream = requireNotNull(resolver.openOutputStream(partial, "wt"))
        override val partialLocation: String get() = partial.toString()

        override fun promote(expectation: RawPromotionExpectation, checkCancellation: () -> Unit): RawPromotionReceipt =
            synchronized(partialLock) {
                closeOutput()
                checkCancellation()
                check(findChild(resolver, treeUri, parent, finalName) == null) {
                    "Raw snapshot already exists and is immutable."
                }
                val created = requireNotNull(DocumentsContract.createDocument(resolver, parent, mime, finalName)) {
                    "Unable to create final SAF document"
                }
                final = created
                try {
                    check(displayName(resolver, created) == finalName) {
                        "SAF provider auto-renamed the immutable raw snapshot artifact."
                    }
                    val sourceDigest = MessageDigest.getInstance("SHA-256")
                    var sourceBytes = 0L
                    requireNotNull(resolver.openInputStream(partial)).use { input ->
                        requireNotNull(resolver.openOutputStream(created, "wt")).use { destination ->
                            val buffer = ByteArray(32 * 1024)
                            while (true) {
                                checkCancellation()
                                val count = input.read(buffer)
                                if (count < 0) break
                                if (count > 0) {
                                    destination.write(buffer, 0, count)
                                    sourceDigest.update(buffer, 0, count)
                                    sourceBytes += count
                                }
                            }
                            destination.flush()
                        }
                    }
                    require(sourceBytes == expectation.byteCount && sourceDigest.digest().hex() == expectation.checksumSha256) {
                        "SAF partial bytes changed before promotion."
                    }
                    verifyUri(resolver, created, expectation, checkCancellation)
                    check(displayName(resolver, created) == finalName) { "Promoted SAF artifact name changed during verification." }
                    checkCancellation()
                    if (!DocumentsContract.deleteDocument(resolver, partial)) {
                        error("Raw snapshot promotion failed because the SAF partial could not be removed")
                    }
                    checkCancellation()
                    promoted = true
                    val receipt = RawPromotionReceipt(created.toString(), finalName, expectation.byteCount, expectation.checksumSha256)
                    recordPromotion(receipt)
                    releaseOnce()
                    receipt
                } catch (error: Throwable) {
                    runCatching { DocumentsContract.deleteDocument(resolver, created) }
                    throw error
                }
            }

        override fun abort() = synchronized(partialLock) {
            closeOutput()
            runCatching { DocumentsContract.deleteDocument(resolver, partial) }
            if (promoted) final?.let { runCatching { DocumentsContract.deleteDocument(resolver, it) } }
            promoted = false
            releaseOnce()
        }

        override fun close() = closeOutput()
        private fun closeOutput() {
            if (!closed) { output.flush(); output.close(); closed = true }
        }
        private fun releaseOnce() { if (!released) { released = true; release() } }
    }
}

private fun findChild(resolver: ContentResolver, treeUri: Uri, parent: Uri, displayName: String): Uri? {
    val parentId = DocumentsContract.getDocumentId(parent)
    val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
    resolver.query(
        children,
        arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor ->
        val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        while (cursor.moveToNext()) {
            if (cursor.getString(nameIndex) == displayName) {
                return DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(idIndex))
            }
        }
    }
    return null
}

internal fun verifyRawPromotionFile(
    file: File,
    expectation: RawPromotionExpectation,
    checkCancellation: () -> Unit = {},
) {
    file.inputStream().use { input -> verifyStream(input, expectation, checkCancellation) }
}

private fun verifyUri(
    resolver: ContentResolver,
    uri: Uri,
    expectation: RawPromotionExpectation,
    checkCancellation: () -> Unit,
) {
    requireNotNull(resolver.openInputStream(uri)).use { input -> verifyStream(input, expectation, checkCancellation) }
}

private fun verifyStream(
    input: java.io.InputStream,
    expectation: RawPromotionExpectation,
    checkCancellation: () -> Unit,
) {
    val digest = MessageDigest.getInstance("SHA-256")
    var bytes = 0L
    val buffer = ByteArray(32 * 1024)
    while (true) {
        checkCancellation()
        val count = input.read(buffer)
        if (count < 0) break
        if (count > 0) {
            digest.update(buffer, 0, count)
            bytes += count
        }
    }
    checkCancellation()
    require(bytes == expectation.byteCount && digest.digest().hex() == expectation.checksumSha256) {
        "Promoted raw snapshot does not match the completed partial bytes."
    }
}

private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }
