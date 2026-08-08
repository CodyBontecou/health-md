package com.healthmd.data.clinicianreport

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.healthmd.domain.clinicianreport.ClinicianReportData
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import javax.inject.Inject

class ClinicianReportFileStore @Inject constructor(
    @ApplicationContext private val context: Context,
    private val renderer: ClinicianReportPdfRenderer,
) {
    private val directory: File get() = File(context.cacheDir, "clinician-reports")

    @Synchronized
    fun generate(
        report: ClinicianReportData,
        startDate: LocalDate,
        endDate: LocalDate,
        shouldPublish: () -> Boolean = { true },
    ): File {
        directory.mkdirs()
        directory.listFiles()?.filter {
            it.extension.equals("pdf", true) || it.extension.equals("partial", true)
        }?.forEach(File::delete)
        val formatter = DateTimeFormatter.ISO_LOCAL_DATE
        val title = report.title
            .replace(Regex("[^\\p{L}\\p{N}_-]+"), "-")
            .trim('-')
            .take(60)
            .ifBlank { "HealthMd" }
        val file = File(directory, "${title}_${startDate.format(formatter)}_${endDate.format(formatter)}.pdf")
        val partial = File.createTempFile("clinician-report-", ".partial", directory)
        try {
            partial.outputStream().buffered().use { output ->
                renderer.render(report, output, shouldContinue = shouldPublish)
            }
            require(partial.isFile && partial.length() > 0) { "The PDF could not be generated." }
            if (!shouldPublish()) throw java.util.concurrent.CancellationException("Report request was superseded")
            // The temporary and final files share one private directory, so rename publishes the
            // completed PDF atomically instead of exposing a partially copied `.pdf` artifact.
            if (file.exists() && !file.delete()) error("The previous PDF could not be replaced.")
            check(partial.renameTo(file)) { "The completed PDF could not be published." }
            if (!shouldPublish()) {
                file.delete()
                throw java.util.concurrent.CancellationException("Report request was superseded")
            }
            return file
        } catch (failure: Throwable) {
            partial.delete()
            file.delete()
            throw failure
        }
    }

    @Synchronized
    fun delete(file: File) {
        if (file.parentFile?.absoluteFile == directory.absoluteFile) file.delete()
    }

    fun contentUri(file: File): Uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.clinician-reports",
        file,
    )

    fun shareIntent(file: File): Intent {
        val uri = contentUri(file)
        return Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newUri(context.contentResolver, file.nameWithoutExtension, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    @Synchronized
    fun copyTo(file: File, destination: Uri) {
        // Hold the same store lock as generation/deletion so an explicit save cannot lose its
        // private source file while a configuration change or later generation cleans the cache.
        file.inputStream().buffered().use { input ->
            context.contentResolver.openOutputStream(destination, "w")?.use { output ->
                input.copyTo(output)
            } ?: error("The selected document could not be opened.")
        }
    }
}
