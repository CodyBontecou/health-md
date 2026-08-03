package com.healthmd.widget.glance

import android.content.Context
import android.icu.text.CompactDecimalFormat
import android.text.format.DateFormat
import com.healthmd.widget.model.HealthWidgetDay
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

internal object HealthWidgetFormatters {
    const val MISSING = "—"

    fun integer(value: Double?, locale: Locale): String = value?.takeIf(Double::isFinite)?.let {
        NumberFormat.getIntegerInstance(locale).format(it.roundToInt())
    } ?: MISSING

    fun integer(value: Int?, locale: Locale): String = value?.let {
        NumberFormat.getIntegerInstance(locale).format(it)
    } ?: MISSING

    fun decimal(value: Double?, locale: Locale, maximumFractionDigits: Int = 1): String =
        value?.takeIf(Double::isFinite)?.let {
            NumberFormat.getNumberInstance(locale).apply {
                minimumFractionDigits = 0
                this.maximumFractionDigits = maximumFractionDigits
            }.format(it)
        } ?: MISSING

    fun compactSteps(value: Int?, locale: Locale): String = value?.let { steps ->
        runCatching {
            CompactDecimalFormat.getInstance(locale, CompactDecimalFormat.CompactStyle.SHORT)
                .format(steps)
        }.getOrElse {
            integer(steps, locale)
        }
    } ?: MISSING

    fun sleepHours(minutes: Double?, locale: Locale): String =
        decimal(minutes?.div(60.0), locale)

    fun time(context: Context, epochMillis: Long?): String = epochMillis?.let {
        DateFormat.getTimeFormat(context).format(Date(it))
    } ?: MISSING

    fun weekdayInitial(localDate: String, locale: Locale): String = runCatching {
        LocalDate.parse(localDate)
            .dayOfWeek
            .getDisplayName(TextStyle.NARROW, locale)
    }.getOrDefault("")

    fun averageSleepHours(days: List<HealthWidgetDay>): Double? {
        val values = days.mapNotNull(HealthWidgetDay::sleepDurationMinutes)
        if (values.isEmpty()) return null
        return values.average() / 60.0
    }

    fun ageMinutes(capturedAtEpochMillis: Long?, now: Instant): Long? {
        capturedAtEpochMillis ?: return null
        val elapsed = now.toEpochMilli() - capturedAtEpochMillis
        return elapsed.takeIf { it >= 0 }?.div(60_000L)
    }

    fun today(snapshotZoneId: String, now: Instant): LocalDate = runCatching {
        now.atZone(ZoneId.of(snapshotZoneId)).toLocalDate()
    }.getOrElse { LocalDate.now() }
}
