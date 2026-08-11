package com.healthmd.clinicianreport

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.healthmd.data.clinicianreport.AndroidClinicianReportVocabularyFactory
import com.healthmd.domain.clinicianreport.ClinicianReportVocabulary
import com.healthmd.domain.clinicianreport.ClinicianReportVocabularyFactory
import java.util.Locale

internal fun reportVocabulary(locale: Locale = Locale.US): ClinicianReportVocabulary =
    reportVocabularyFactory().forLocale(locale)

internal fun reportVocabularyFactory(): ClinicianReportVocabularyFactory =
    AndroidClinicianReportVocabularyFactory(ApplicationProvider.getApplicationContext<Context>())
