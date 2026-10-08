package com.healthmd.presentation.theme

import android.content.Context
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import androidx.compose.ui.graphics.toArgb
import androidx.test.core.app.ApplicationProvider
import com.healthmd.R
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SystemAppearanceTest {
    @Test
    fun `native windows resolve the system palette in light and dark modes`() {
        for (dark in listOf(false, true, false)) {
            val base = ApplicationProvider.getApplicationContext<Context>()
            val configuration = Configuration(base.resources.configuration).apply {
                uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                    if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
            }
            val context = ContextThemeWrapper(
                base.createConfigurationContext(configuration), R.style.Theme_HealthMd,
            )
            val colors = if (dark) GeistDarkColors else GeistLightColors
            val attributes = context.obtainStyledAttributes(intArrayOf(
                android.R.attr.windowBackground,
                android.R.attr.textColorPrimary,
                android.R.attr.colorAccent,
                android.R.attr.windowLightStatusBar,
                android.R.attr.windowLightNavigationBar,
                android.R.attr.forceDarkAllowed,
                android.R.attr.isLightTheme,
            ))
            try {
                assertEquals(colors.background100.toArgb(), attributes.getColor(0, 0))
                assertEquals(colors.primary.toArgb(), attributes.getColor(1, 0))
                assertEquals(colors.accent.toArgb(), attributes.getColor(2, 0))
                assertEquals(!dark, attributes.getBoolean(3, dark))
                assertEquals(!dark, attributes.getBoolean(4, dark))
                assertEquals(false, attributes.getBoolean(5, true))
                assertEquals(!dark, attributes.getBoolean(6, dark))
            } finally {
                attributes.recycle()
            }
        }
    }
}
