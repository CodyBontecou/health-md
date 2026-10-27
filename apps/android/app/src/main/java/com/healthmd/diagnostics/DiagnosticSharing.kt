package com.healthmd.diagnostics

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.nio.file.Files
import java.util.UUID

/** Only final ZIP copies are exposed, via a narrow cache-path FileProvider. */
object DiagnosticSharing {
    fun share(context: Context, bundle: PreparedDiagnosticBundle) {
        val directory = File(context.cacheDir, "diagnostic-share-v1")
        require(!Files.isSymbolicLink(directory.toPath()))
        check(directory.isDirectory || directory.mkdirs())
        DiagnosticStore.protect(directory)
        sweep(directory)
        val target = File(directory, "healthmd-diagnostics-${UUID.randomUUID()}.zip")
        try {
            bundle.verifiedFile().copyTo(target)
            DiagnosticStore.protect(target)
            if (DiagnosticBundleBuilder.digest(target) != bundle.zipSHA256) throw DiagnosticBundleException("The reviewed bundle changed. Prepare and review it again.")
            val uri: Uri = FileProvider.getUriForFile(context, "${context.packageName}.diagnostics", target)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/zip"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = android.content.ClipData.newRawUri("Health.md diagnostics", uri)
            }
            context.startActivity(Intent.createChooser(intent, context.getString(com.healthmd.R.string.diagnostics_share)))
        } catch (error: Exception) { target.delete(); throw error }
    }
    fun clearCopies(context: Context): Boolean {
        val root = File(context.cacheDir, "diagnostic-share-v1")
        return !root.exists() || (!Files.isSymbolicLink(root.toPath()) && root.deleteRecursively())
    }
    fun sweep(context: Context) { sweep(File(context.cacheDir, "diagnostic-share-v1")) }
    private fun sweep(directory: File) {
        if (Files.isSymbolicLink(directory.toPath())) return
        val now = System.currentTimeMillis()
        directory.listFiles().orEmpty().filter { it.isFile && !Files.isSymbolicLink(it.toPath()) }.sortedByDescending(File::lastModified)
            .forEachIndexed { index, file -> if (index >= 2 || now - file.lastModified() >= DiagnosticStore.PRIVATE_RETENTION_MS) file.delete() }
    }
}
