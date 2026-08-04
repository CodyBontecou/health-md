package com.healthmd.localization

import android.app.LocaleManager
import android.os.LocaleList
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.healthmd.domain.model.DateFormatPreference
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FormatPreferencesLocaleTest {
    @Test
    fun monthNamesFollowThePerAppLanguage() {
        val localeManager = InstrumentationRegistry.getInstrumentation()
            .targetContext
            .getSystemService(LocaleManager::class.java)
        val originalLocales = localeManager.applicationLocales

        try {
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                localeManager.applicationLocales = LocaleList.forLanguageTags("fr")
            }
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()

            val appLocale = InstrumentationRegistry.getInstrumentation()
                .targetContext
                .resources
                .configuration
                .locales[0]
            val formatted = DateFormatPreference.US_LONG.format(LocalDate.of(2026, 1, 13))

            assertEquals("fr", appLocale.language)
            assertTrue("expected a French month name, got: $formatted", formatted.contains("janvier"))
        } finally {
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                localeManager.applicationLocales = originalLocales
            }
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        }
    }
}
