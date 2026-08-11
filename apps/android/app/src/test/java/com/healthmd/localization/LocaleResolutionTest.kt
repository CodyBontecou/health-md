package com.healthmd.localization

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.R
import java.util.Locale
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LocaleResolutionTest {
    private val applicationContext: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun generatedPseudoLocalesExerciseExpansionAndRtlResolution() {
        val english = localizedContext("en-US").getString(R.string.nav_settings)
        val expanded = localizedContext("en-XA").getString(R.string.nav_settings)
        val mirroredContext = localizedContext("ar-XB")

        assertThat(expanded).isNotEqualTo(english)
        assertThat(mirroredContext.getString(R.string.nav_settings)).isNotEqualTo(english)
        assertThat(mirroredContext.resources.configuration.layoutDirection)
            .isEqualTo(View.LAYOUT_DIRECTION_RTL)
    }

    @Test
    fun arabicResourcesResolveWithRtlLayoutDirection() {
        val context = localizedContext("ar")

        assertThat(context.getString(R.string.nav_settings)).isNotEmpty()
        assertThat(context.resources.configuration.layoutDirection)
            .isEqualTo(View.LAYOUT_DIRECTION_RTL)
    }

    @Test
    fun punjabiGurmukhiDoesNotLeakIntoShahmukhiLocales() {
        val english = localizedContext("en-US").getString(R.string.nav_settings)
        val gurmukhi = localizedContext("pa-Guru-IN").getString(R.string.nav_settings)
        val shahmukhi = localizedContext("pa-Arab-PK").getString(R.string.nav_settings)

        assertThat(gurmukhi).containsMatch("[\\u0A00-\\u0A7F]")
        assertThat(shahmukhi).isEqualTo(english)
    }

    private fun localizedContext(languageTag: String): Context {
        val configuration = Configuration(applicationContext.resources.configuration).apply {
            setLocales(LocaleList(Locale.forLanguageTag(languageTag)))
        }
        return applicationContext.createConfigurationContext(configuration)
    }
}
