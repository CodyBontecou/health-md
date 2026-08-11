package com.healthmd.clinicianreport

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.clinicianreport.AndroidClinicianReportPdfRenderer
import com.healthmd.data.clinicianreport.ClinicianReportFileStore
import com.healthmd.data.clinicianreport.ClinicianReportPdfRenderer
import com.healthmd.data.clinicianreport.ReportPageSize
import com.healthmd.domain.clinicianreport.*
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.OutputStream
import java.time.LocalDate
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
class ClinicianReportFileStoreTest {
    @Test fun failedRenderDeletesPartialPdf() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = ClinicianReportFileStore(context, object : ClinicianReportPdfRenderer {
            override fun render(report: ClinicianReportData, output: OutputStream, pageSize: ReportPageSize, shouldContinue: () -> Boolean): Int {
                output.write("partial health data".toByteArray())
                error("render failed")
            }
        })
        val report = report()
        runCatching { store.generate(report, LocalDate.of(2026, 1, 1), LocalDate.of(2026, 1, 30)) }
        val files = java.io.File(context.cacheDir, "clinician-reports").listFiles().orEmpty()
        assertThat(files.filter { it.extension == "pdf" }).isEmpty()
    }

    @Test fun pinnedReportRegionSelectsPaperIndependentlyOfSystemLocale() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        var renderedSize: ReportPageSize? = null
        val store = ClinicianReportFileStore(context, object : ClinicianReportPdfRenderer {
            override fun render(report: ClinicianReportData, output: OutputStream, pageSize: ReportPageSize, shouldContinue: () -> Boolean): Int {
                renderedSize = pageSize
                output.write("%PDF-test".toByteArray())
                return 1
            }
        })
        store.generate(report(paperRegionCode = "DE"), LocalDate.of(2026, 1, 1), LocalDate.of(2026, 1, 1))
        assertThat(renderedSize).isEqualTo(ReportPageSize.A4)
    }

    @Test(timeout = 15_000) fun largeTaggedRenderCancellationStopsBeforeAllRowsAndDeletesEveryArtifact() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val rowCount = 5_000
        val largeSection = MetricReportSummary(
            metric = ReportMetric.HEART_RATE,
            facts = listOf(ReportFact("Readings", rowCount.toString())),
            sources = listOf("Synthetic Source"),
            coverageDisclosure = "Synthetic coverage",
            noDataMessage = null,
            table = ReportTable(
                title = "Heart Rate Readings",
                columns = listOf("Date", "Time", "Value", "Source"),
                rows = List(rowCount) { index -> listOf("Jan 1, 2026", "8:00 AM", "${60 + index % 20} bpm", "Synthetic Source") },
            ),
            localizedTitle = "Heart Rate",
            sourcesDisclosure = "Sources: Synthetic Source",
            detailReadingsDescription = "$rowCount readings",
        )
        val checks = AtomicInteger()
        val store = ClinicianReportFileStore(context, AndroidClinicianReportPdfRenderer(context))

        assertThrows(CancellationException::class.java) {
            store.generate(
                report(sections = listOf(largeSection)),
                LocalDate.of(2026, 1, 1),
                LocalDate.of(2026, 3, 31),
            ) { checks.incrementAndGet() < 200 }
        }

        assertThat(checks.get()).isEqualTo(200)
        assertThat(checks.get()).isLessThan(rowCount)
        val files = java.io.File(context.cacheDir, "clinician-reports").listFiles().orEmpty()
        assertThat(files.filter { it.extension in setOf("pdf", "partial") }).isEmpty()
    }

    @Test fun filenameExcludesDisplayNameCleansStaleFileAndSharesContentUri() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val directory = java.io.File(context.cacheDir, "clinician-reports").apply { mkdirs() }
        val stale = java.io.File(directory, "old.pdf").apply { writeText("old") }
        val store = ClinicianReportFileStore(context, object : ClinicianReportPdfRenderer {
            override fun render(report: ClinicianReportData, output: OutputStream, pageSize: ReportPageSize, shouldContinue: () -> Boolean): Int { output.write("%PDF-test".toByteArray()); return 1 }
        })
        val report = report(displayName = "Sensitive Name")
        val file = store.generate(report, LocalDate.of(2026, 1, 1), LocalDate.of(2026, 1, 30))
        assertThat(stale.exists()).isFalse()
        assertThat(file.readText()).isEqualTo("%PDF-test")
        assertThat(directory.listFiles().orEmpty().filter { it.extension == "partial" }).isEmpty()
        assertThat(file.name).isEqualTo("Health-Summary_2026-01-01_2026-01-30.pdf")
        assertThat(file.name).doesNotContain("Sensitive")
        assertThat(file.name).doesNotContain("_to_")
        val intent = store.shareIntent(file)
        assertThat(intent.type).isEqualTo("application/pdf")
        assertThat(store.contentUri(file).scheme).isEqualTo("content")
        assertThat(intent.flags and android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION).isNotEqualTo(0)
    }

    private fun report(
        displayName: String? = null,
        paperRegionCode: String? = "US",
        sections: List<MetricReportSummary> = emptyList(),
    ) = ClinicianReportData(
        title = "Health Summary",
        displayName = displayName,
        dateRangeLabel = "range",
        generatedLabel = "generated",
        timeZoneLabel = "UTC",
        sections = sections,
        warnings = emptyList(),
        completeness = ReportCompleteness.COMPLETE,
        disclaimer = "disclaimer",
        attribution = "attribution",
        practiceLine = null,
        languageTag = "en",
        paperRegionCode = paperRegionCode,
        isRtl = false,
        pdfSubject = "subject",
        pdfKeywords = listOf("Health.md"),
        metadataPeriodLabel = "Period",
        metadataGeneratedLabel = "Generated",
        metadataTimeZoneLabel = "Time zone",
        metadataPatientLabel = "Patient",
        availabilityNoteTitle = "Availability",
        aboutTitle = "About",
        pageFooterTemplate = "Health.md • Page %1\$d",
    )
}
