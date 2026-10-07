package com.healthmd.diagnostics

import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.serialization.json.*

class DiagnosticBundleException(message: String) : Exception(message)
data class DiagnosticAttachment(val name: String, val open: () -> InputStream)
data class DiagnosticBundleFile(val path: String, val byteCount: Long, val sha256: String, val privacy: String, val originalName: String? = null, val originalNameTruncated: Boolean = false) {
    fun json() = buildJsonObject {
        put("path", path); put("byte_count", byteCount); put("sha256", sha256); put("privacy", privacy)
        originalName?.let { put("original_name", it) }
        put("original_name_truncated", originalNameTruncated)
    }
}
data class PreparedDiagnosticBundle(val directory: File, val zip: File, val zipSHA256: String, val manifestSHA256: String, val manifest: JsonObject, val files: List<DiagnosticBundleFile>) {
    fun verifiedFile(): File {
        if (!zip.isFile || Files.isSymbolicLink(zip.toPath()) || DiagnosticBundleBuilder.digest(zip) != zipSHA256) {
            throw DiagnosticBundleException("The reviewed bundle changed or was deleted. Prepare and review it again.")
        }
        (listOf("manifest.json") + files.map { it.path }).forEach(::verifyFile)
        return zip
    }
    private fun verifyFile(path: String) {
        val expected = if (path == "manifest.json") manifestSHA256 else files.firstOrNull { it.path == path }?.sha256
        if (DiagnosticBundleBuilder.digest(File(directory, path)) != expected) throw DiagnosticBundleException("The reviewed file changed. Prepare and review again.")
    }
    fun preview(path: String, maximumBytes: Int = 128 * 1024): Pair<String, Boolean> {
        if (path != "manifest.json" && files.none { it.path == path }) throw DiagnosticBundleException("Unknown bundle file.")
        verifyFile(path)
        require(maximumBytes in 1..128 * 1024)
        val bytes = java.io.ByteArrayOutputStream().also { output ->
            File(directory, path).inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                var remaining = maximumBytes + 1
                while (remaining > 0) {
                    val count = input.read(buffer, 0, minOf(buffer.size, remaining))
                    if (count < 0) break
                    if (count == 0) continue
                    output.write(buffer, 0, count); remaining -= count
                }
            }
        }.toByteArray()
        val prefix = bytes.take(maximumBytes).toByteArray()
        val text = runCatching { Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(prefix)).toString() }.getOrNull()
            ?: "Binary or non-UTF-8 file. Original bytes are included unchanged; inspect it with a trusted local viewer before sharing."
        return text to (bytes.size > maximumBytes)
    }
    fun delete() { if (!Files.isSymbolicLink(directory.toPath())) directory.deleteRecursively() }
}

/** A frozen, local ZIP; never a health query or upload. Attachment streams are user-selected. */
object DiagnosticBundleBuilder {
    const val ATTACHMENT_BYTE_LIMIT = 100 * 1024 * 1024L
    val README = """
        Health.md diagnostics v1

        This ZIP is NOT encrypted. Health.md does not upload it automatically.
        Review manifest.json, events.jsonl, and every attachment before sharing.
        Operational diagnostics exclude health measurements, health record IDs,
        requested health dates, paths, endpoint addresses, and credential values.
        Private context is opt-in and is not anonymous. Original user attachments
        are copied unchanged and may contain health data, identifiers or secrets.
        Attachments are not automatically scrubbed. No new health reads are made.
        Public GitHub/Discord posts may be accessible to anyone. Email and other
        destinations have their own retention and security rules. Shared copies
        cannot be recalled by Health.md. Delete local copies in Diagnostics.

        Events use stable event IDs and catalog-validated typed fields. Omitted fields
        distinguish not_recorded (absent at capture), redacted (excluded at sharing),
        and invalid (rejected by the catalog). Truncation, malformed events, and
        drops in the current app process are disclosed in the manifest. Wall clocks
        can differ between devices; sequence/monotonic timing orders each session.
        Existing session/operation IDs are random operational IDs, not health IDs.
        Source locations refer to the open-source app, not local filesystem paths.

        Catalog: packages/contracts/diagnostics/v1/catalog.json
        Source: https://github.com/CodyBontecou/health-md
    """.trimIndent()

    fun prepare(
        store: DiagnosticStore,
        includePrivate: Boolean = false,
        since: Long? = null,
        subsystem: String? = null,
        operationId: String? = null,
        attachments: List<DiagnosticAttachment> = emptyList(),
        appVersion: String = "unavailable",
        appBuild: String = "unavailable",
        osVersion: String = "unavailable",
    ): PreparedDiagnosticBundle {
        if (attachments.size > 50) throw DiagnosticBundleException("Attachments exceed 50 files. Remove files and prepare again.")
        require(!Files.isSymbolicLink(store.directory.toPath()))
        val root = File(store.directory, "bundles")
        require(!Files.isSymbolicLink(root.toPath()) && (root.isDirectory || root.mkdirs()))
        DiagnosticStore.protect(root)
        sweep(root)
        val directory = File(root, UUID.randomUUID().toString())
        check(directory.mkdir()); DiagnosticStore.protect(directory)
        var complete = false
        try {
            val snapshot = store.snapshot(includePrivate, since, subsystem, operationId)
            val files = mutableListOf<DiagnosticBundleFile>()
            fun add(path: String, text: String, privacy: String = "operational") {
                val file = File(directory, path)
                file.writeText(text); DiagnosticStore.protect(file)
                files += DiagnosticBundleFile(path, file.length(), digest(file), privacy)
            }
            add("README.txt", README)
            val hasPrivate = snapshot.events.any { event -> event.fields.keys.any { key -> DiagnosticField.entries.any { it.wire == key && it.isPrivate } } }
            val privacy = if (hasPrivate) "private_context" else "operational"
            add("events.jsonl", snapshot.events.joinToString("\n", postfix = if (snapshot.events.isEmpty()) "" else "\n") { it.document.toString() }, privacy)
            add("events.txt", snapshot.events.joinToString("\n\n") { "${it.timestamp} [${it.severity}] ${it.eventId} ${it.document["source"]?.jsonPrimitive?.content}\n${it.document}" }, privacy)
            var totalAttachmentBytes = 0L
            if (attachments.isNotEmpty()) { check(File(directory, "attachments").mkdir()); DiagnosticStore.protect(File(directory, "attachments")) }
            attachments.forEachIndexed { index, attachment ->
                val extension = attachment.name.substringAfterLast('.', "bin").lowercase().takeIf { Regex("^[a-z0-9]{1,10}$").matches(it) } ?: "bin"
                val path = "attachments/attachment-${index + 1}.$extension"
                val output = File(directory, path)
                attachment.open().use { input -> output.outputStream().use { destination ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        totalAttachmentBytes += count
                        if (totalAttachmentBytes > ATTACHMENT_BYTE_LIMIT) throw DiagnosticBundleException("Attachments exceed 100 MiB. Remove files and prepare again.")
                        destination.write(buffer, 0, count)
                    }
                    destination.fd.sync()
                } }
                DiagnosticStore.protect(output)
                files += DiagnosticBundleFile(path, output.length(), digest(output), "user_attachment", attachment.name.take(512), attachment.name.length > 512)
            }
            val manifest = buildJsonObject {
                put("schema", "healthmd.diagnostic_bundle"); put("schema_version", 1)
                put("generated_at", DiagnosticStore.timestamp(System.currentTimeMillis())); put("platform", "android")
                put("app_version", appVersion); put("app_build", appBuild); put("os_version", osVersion)
                put("include_private_context", includePrivate); put("contains_private_context", hasPrivate || attachments.isNotEmpty())
                put("health_content", if (hasPrivate || attachments.isNotEmpty()) "possible" else "not_included")
                put("event_count", snapshot.events.size); put("session_dropped_event_count", snapshot.droppedEventCount)
                put("invalid_event_count", snapshot.invalidEventCount); put("truncated", snapshot.truncated)
                since?.let { put("selection_since", DiagnosticStore.timestamp(it)) }
                subsystem?.let { put("selection_subsystem", it) }
                operationId?.let { put("selection_operation_id", it) }
                put("files", JsonArray(files.map { it.json() }))
            }
            val manifestFile = File(directory, "manifest.json")
            manifestFile.writeText(manifest.toString()); DiagnosticStore.protect(manifestFile)
            val zip = File(directory, "healthmd-diagnostics.zip")
            ZipOutputStream(zip.outputStream().buffered()).use { archive ->
                (listOf("manifest.json") + files.map { it.path }).forEach { path ->
                    archive.putNextEntry(ZipEntry(path))
                    File(directory, path).inputStream().use { it.copyTo(archive, 64 * 1024) }
                    archive.closeEntry()
                }
            }
            DiagnosticStore.protect(zip)
            val prepared = PreparedDiagnosticBundle(directory, zip, digest(zip), digest(manifestFile), manifest, files.toList())
            complete = true
            return prepared
        } finally { if (!complete) directory.deleteRecursively() }
    }
    fun digest(file: File): String {
        require(file.isFile && !Files.isSymbolicLink(file.toPath()))
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    internal fun sweep(root: File) {
        val now = System.currentTimeMillis()
        root.listFiles().orEmpty().filter { it.isDirectory && !Files.isSymbolicLink(it.toPath()) && runCatching { UUID.fromString(it.name) }.isSuccess }
            .sortedByDescending(File::lastModified).forEachIndexed { index, file ->
                if (index >= 2 || now - file.lastModified() >= DiagnosticStore.PRIVATE_RETENTION_MS) file.deleteRecursively()
            }
    }
}
