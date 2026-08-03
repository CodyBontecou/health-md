package com.healthmd.presentation.schedule

import com.google.common.truth.Truth.assertThat
import java.util.Locale
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ScheduleLocalizationTest {

    @Test
    fun formatAndParseInteger_roundTripsLocalizedDigits() {
        val locale = Locale.forLanguageTag("ar-EG")

        val formatted = formatInteger(42, locale)

        assertThat(parseLocalizedInteger(formatted, locale)).isEqualTo(42)
    }

    @Test
    fun parseLocalizedInteger_rejectsTrailingText() {
        assertThat(parseLocalizedInteger("42 days", Locale.US)).isNull()
    }

    @Test
    fun localizedTimePatternHelpers_returnUsableEditorParts() {
        assertThat(localizedTimeSeparator(Locale.US, use24HourTime = false)).isNotEmpty()
        assertThat(localizedTimeSeparator(Locale.GERMANY, use24HourTime = true)).isNotEmpty()
        assertThat(localizedHourMinimumDigits(Locale.US, use24HourTime = false)).isIn(1..2)
        assertThat(localizedHourMinimumDigits(Locale.US, use24HourTime = true)).isIn(1..2)
    }

    @Test
    fun twelveHourEditor_honorsLocaleHourCycleAndDayPeriodPosition() {
        assertThat(localizedDisplayHour(0, localizedHourCycle(Locale.US, false))).isEqualTo(12)
        assertThat(localizedDisplayHour(0, localizedHourCycle(Locale.JAPAN, false))).isEqualTo(0)

        assertThat(localizedDayPeriodPrecedesHour(Locale.JAPAN)).isTrue()
        assertThat(localizedDayPeriodPrecedesHour(Locale.SIMPLIFIED_CHINESE)).isTrue()

        val hindiHourCycle = localizedHourCycle(Locale.forLanguageTag("hi"), false)
        assertThat(hindiHourCycle).isAnyOf('h', 'K')
        assertThat(localizedDisplayHour(13, hindiHourCycle)).isIn(0..12)
    }
}
