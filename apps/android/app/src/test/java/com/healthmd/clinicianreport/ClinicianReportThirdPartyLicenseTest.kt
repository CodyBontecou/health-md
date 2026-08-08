package com.healthmd.clinicianreport

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ClinicianReportThirdPartyLicenseTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test fun packagedPdfBoxLicenseNoticeAndAttributionAreComplete() {
        val license = asset("licenses/pdfbox-android-apache-2.0.txt")
        val notice = asset("licenses/pdfbox-android-notice.txt")
        val source = asset("licenses/pdfbox-android-source.txt")

        assertThat(license).contains("Apache License")
        assertThat(license).contains("Version 2.0, January 2004")
        assertThat(notice).contains("Apache PDFBox")
        assertThat(notice).contains("The Apache Software Foundation")
        assertThat(notice).contains("Adobe Glyph List")
        assertThat(source).contains("com.tom-roush:pdfbox-android:2.0.27.0")
        assertThat(source).contains("https://github.com/TomRoush/PdfBox-Android")
        assertThat(source).contains("Apache License 2.0")
        assertThat(source).contains("based on Apache PDFBox and FontBox")
        assertThat(source).contains("do not endorse Health.md")
    }

    private fun asset(path: String): String = context.assets.open(path).bufferedReader().use { it.readText() }
}
