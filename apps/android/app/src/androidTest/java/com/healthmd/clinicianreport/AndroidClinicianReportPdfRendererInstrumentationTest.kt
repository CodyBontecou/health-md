package com.healthmd.clinicianreport

import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import com.healthmd.data.clinicianreport.AndroidClinicianReportPdfRenderer
import com.healthmd.data.clinicianreport.ReportPageSize
import com.healthmd.data.clinicianreport.AndroidClinicianReportVocabularyFactory
import com.healthmd.domain.clinicianreport.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

@RunWith(AndroidJUnit4::class)
class AndroidClinicianReportPdfRendererInstrumentationTest {
    @Test fun largeReadingsReportIsValidAndMultiPage() {
        val range = ReportDateRange(LocalDate.of(2026, 1, 1), LocalDate.of(2026, 1, 30))
        val config = ReportConfiguration(range, setOf(ReportMetric.HEART_RATE), ReportDetailLevel.SUMMARY_AND_READINGS)
        val input = ClinicianReportInput(
            config, ZoneId.of("UTC"), Instant.parse("2026-02-01T00:00:00Z"),
            scalarObservations = (0 until 500).map { ScalarReportObservation(ReportMetric.HEART_RATE, Instant.parse("2026-01-01T00:00:00Z").plusSeconds(it * 60L), 60.0 + it % 20) },
        )
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val report = ClinicianReportGenerator(AndroidClinicianReportVocabularyFactory(context).current()).generate(input)
        listOf(ReportPageSize.LETTER, ReportPageSize.A4).forEach { size ->
            val file = File(context.cacheDir, "renderer-${size.width}.pdf")
            val expectedPages = file.outputStream().use { AndroidClinicianReportPdfRenderer(context).render(report, it, size) }
            assertEquals("%PDF-", file.readBytes().copyOfRange(0, 5).decodeToString())
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { pdf ->
                    assertEquals(expectedPages, pdf.pageCount)
                    assertTrue(pdf.pageCount > 1)
                }
            }
            file.delete()
        }
    }
}
