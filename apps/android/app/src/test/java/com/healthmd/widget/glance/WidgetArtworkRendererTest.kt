package com.healthmd.widget.glance

import androidx.compose.ui.graphics.Color
import com.google.common.truth.Truth.assertThat
import com.healthmd.widget.model.HealthWidgetDay
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WidgetArtworkRendererTest {
    private val renderer = WidgetArtworkRenderer()

    @Test
    fun `activity artwork renders three bounded progress rings`() {
        val bitmap = renderer.renderActivityRings(
            day = HealthWidgetDay(
                localDate = "2026-08-02",
                steps = 12_500,
                activeCaloriesKilocalories = 750.0,
                exerciseMinutes = 45.0,
            ),
            activeColor = Color.Red,
            exerciseColor = Color.Green,
            stepsColor = Color.Blue,
            sizePx = 160,
        )

        assertThat(bitmap.width).isEqualTo(160)
        assertThat(bitmap.height).isEqualTo(160)
        assertThat(nonTransparentPixelCount(bitmap)).isGreaterThan(1_000)
        // The center remains transparent so Glance can overlay accessible step text.
        assertThat(bitmap.getPixel(80, 80).ushr(24)).isEqualTo(0)
    }

    @Test
    fun `heart artwork preserves calendar gaps and renders available points`() {
        val bitmap = renderer.renderHeartRange(
            days = listOf(
                HealthWidgetDay("2026-07-27", averageHeartRateBpm = 70.0, minimumHeartRateBpm = 50.0, maximumHeartRateBpm = 130.0),
                HealthWidgetDay("2026-07-28"),
                HealthWidgetDay("2026-07-29", averageHeartRateBpm = 74.0, minimumHeartRateBpm = 48.0, maximumHeartRateBpm = 145.0),
            ),
            color = Color.Red,
            widthPx = 300,
            heightPx = 100,
        )

        assertThat(bitmap).isNotNull()
        assertThat(bitmap!!.width).isEqualTo(300)
        assertThat(nonTransparentPixelCount(bitmap)).isGreaterThan(100)
    }

    @Test
    fun `heart artwork is absent when there are no average heart values`() {
        assertThat(
            renderer.renderHeartRange(
                days = listOf(HealthWidgetDay("2026-08-02")),
                color = Color.Red,
            )
        ).isNull()
    }

    private fun nonTransparentPixelCount(bitmap: android.graphics.Bitmap): Int {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return pixels.count { pixel -> pixel.ushr(24) != 0 }
    }
}
