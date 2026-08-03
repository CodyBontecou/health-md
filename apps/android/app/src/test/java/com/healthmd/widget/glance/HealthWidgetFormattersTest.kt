package com.healthmd.widget.glance

import com.google.common.truth.Truth.assertThat
import com.healthmd.widget.model.HealthWidgetDay
import java.util.Locale
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HealthWidgetFormattersTest {
    @Test
    fun `sleep hours and decimals use locale formatting`() {
        assertThat(HealthWidgetFormatters.sleepHours(450.0, Locale.US)).isEqualTo("7.5")
        assertThat(HealthWidgetFormatters.decimal(7.5, Locale.GERMANY)).isEqualTo("7,5")
    }

    @Test
    fun `compact steps use locale-aware ICU notation`() {
        assertThat(HealthWidgetFormatters.compactSteps(8_742, Locale.US)).isEqualTo("8.7K")
        assertThat(HealthWidgetFormatters.compactSteps(12_000, Locale.JAPAN)).isEqualTo("1.2万")
    }

    @Test
    @Config(sdk = [28])
    fun `compact steps use ICU on the minimum supported sdk`() {
        assertThat(HealthWidgetFormatters.compactSteps(1_200, Locale.US)).isEqualTo("1.2K")
    }

    @Test
    fun `missing values render an em dash`() {
        assertThat(HealthWidgetFormatters.integer(null as Int?, Locale.US)).isEqualTo("—")
        assertThat(HealthWidgetFormatters.decimal(null, Locale.US)).isEqualTo("—")
        assertThat(HealthWidgetFormatters.compactSteps(null, Locale.US)).isEqualTo("—")
    }

    @Test
    fun `seven-day average ignores missing sleep days`() {
        val days = listOf(
            HealthWidgetDay(localDate = "2026-08-01", sleepDurationMinutes = 420.0),
            HealthWidgetDay(localDate = "2026-08-02"),
            HealthWidgetDay(localDate = "2026-08-03", sleepDurationMinutes = 480.0),
        )

        assertThat(HealthWidgetFormatters.averageSleepHours(days)).isEqualTo(7.5)
    }
}
