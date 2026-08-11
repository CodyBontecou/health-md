package com.healthmd.localization

import android.graphics.Paint
import androidx.core.content.res.ResourcesCompat
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.healthmd.R
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalizedFontFallbackTest {
    @Test
    fun bundledGeistFamiliesFallBackForEverySupportedScript() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val scriptSamples = mapOf(
            "Arabic" to "ص",
            "Bengali" to "স",
            "Devanagari" to "स",
            "Gurmukhi" to "ਸ",
            "Han" to "健",
            "Japanese kana" to "あ",
        )

        listOf(R.font.geist_regular, R.font.geist_mono_regular).forEach { fontResource ->
            val typeface = requireNotNull(ResourcesCompat.getFont(context, fontResource))
            val paint = Paint().apply {
                this.typeface = typeface
                textSize = 32f
            }

            scriptSamples.forEach { (script, sample) ->
                assertTrue(
                    "font resource $fontResource must render $script via fallback",
                    paint.hasGlyph(sample),
                )
            }
        }
    }
}
