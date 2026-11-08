package com.healthmd.presentation.schedule.composer

import android.text.format.DateFormat
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.rawexport.ExportMode
import com.healthmd.presentation.i18n.localizedDisplayName
import java.time.DayOfWeek
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle

/** Token values of an automation's sentence, and the part of a value that is the choice. */
internal data class ComposerValues(val values: Map<ComposerToken, String>, val emphasis: Map<ComposerToken, String>)

/**
 * The sentence's values in the user's language, time format and calendar (iOS
 * `AutomationSentence.make`). The composer names every choice so each can be edited; the
 * [summary] of cards and the detail leaves out defaults: every metric, notes-only formats and
 * an untouched daily note, and leads a Today Refresh automation with its refresh cadence.
 */
@Composable
internal fun automationSentenceValues(
    settings: ExportSettings,
    entry: ScheduledProfileEntry?,
    destination: String,
    summary: Boolean,
): ComposerValues {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val clock = entry?.let {
        val pattern = DateFormat.getBestDateTimePattern(locale, if (DateFormat.is24HourFormat(context)) "Hm" else "hm")
        LocalTime.of(it.hour, it.minute).format(DateTimeFormatter.ofPattern(pattern, locale))
    }.orEmpty()
    val refreshes = summary && entry?.isEnabled == true && entry.todayRefreshEnabled
    var emphasis: String? = clock.takeIf { it.isNotEmpty() }
    val whenText = when {
        refreshes -> {
            val minutes = requireNotNull(entry).todayRefreshMinutes
            emphasis = null
            if (minutes < 60) {
                pluralStringResource(R.plurals.automation_refresh_every_minutes, minutes, minutes)
            } else {
                pluralStringResource(R.plurals.automation_refresh_every_hours, minutes / 60, minutes / 60)
            }
        }
        else -> when (ComposerSentence.whenKind(entry)) {
            ComposerWhenKind.MANUAL -> stringResource(R.string.composer_when_manual)
            ComposerWhenKind.DAILY -> stringResource(
                when (ComposerDayPeriod.of(requireNotNull(entry).hour)) {
                    ComposerDayPeriod.MORNING -> R.string.composer_when_morning
                    ComposerDayPeriod.AFTERNOON -> R.string.composer_when_afternoon
                    ComposerDayPeriod.EVENING -> R.string.composer_when_evening
                    ComposerDayPeriod.NIGHT -> R.string.composer_when_night
                },
                clock,
            )
            ComposerWhenKind.WEEKLY -> stringResource(
                R.string.composer_when_weekly,
                DayOfWeek.of(requireNotNull(entry).weekdayIso).getDisplayName(TextStyle.FULL, locale),
                clock,
            )
            ComposerWhenKind.MONTHLY -> stringResource(R.string.composer_when_monthly, clock)
            ComposerWhenKind.CUSTOM -> {
                val count = requireNotNull(entry).cadenceValue
                pluralStringResource(
                    when (entry.cadenceUnit) {
                        ScheduledProfileCadenceUnit.DAY -> R.plurals.automation_schedule_every_days
                        ScheduledProfileCadenceUnit.WEEK -> R.plurals.automation_schedule_every_weeks
                        ScheduledProfileCadenceUnit.MONTH -> R.plurals.automation_schedule_every_months
                    },
                    count,
                    count,
                    clock,
                )
            }
        }
    }
    val days = ComposerSentence.rangeDays(entry)
    val range = when {
        refreshes -> stringResource(R.string.automation_range_today)
        days > 1 -> pluralStringResource(R.plurals.composer_range_last_days, days, days)
        else -> stringResource(R.string.composer_range_yesterday)
    }
    val metricCount = settings.metricSelection.enabledCount
    val metrics = pluralStringResource(R.plurals.composer_metrics, metricCount, metricCount)
    val sorted = ExportFormat.entries.filter { it in settings.exportFormats }
    val rawSnapshot = settings.exportMode == ExportMode.RAW_SNAPSHOT
    val rawSnapshotName = stringResource(R.string.export_type_raw_snapshot)
    val noteOn = !rawSnapshot && settings.dailyNoteInjection.enabled
    val noteUpdate = stringResource(R.string.composer_note_update)
    val noteLeave = stringResource(R.string.composer_note_leave)
    val localizedFormats = sorted.associateWith { it.localizedDisplayName() }
    val values = buildMap {
        put(ComposerToken.WHEN, whenText)
        put(ComposerToken.RANGE, range)
        put(ComposerToken.WHERE, destination)
        if (summary) {
            // "write the last 7 days" already means every metric.
            if (!rawSnapshot && metricCount < HealthMetrics.totalCount) put(ComposerToken.METRICS, metrics)
            // Notes are the default; other formats are named. Bases is the Obsidian product name.
            val notesOnly = !rawSnapshot && ExportFormat.MARKDOWN in sorted &&
                sorted.all { it == ExportFormat.MARKDOWN || it == ExportFormat.OBSIDIAN_BASES }
            val formats = ComposerSentence.outputFormatNames(settings, rawSnapshotName) { if (it == ExportFormat.OBSIDIAN_BASES) "Bases" else localizedFormats.getValue(it) }
                .joinToString(" + ")
            if (!notesOnly && formats.isNotEmpty()) put(ComposerToken.FORMATS, formats)
            if (noteOn) put(ComposerToken.NOTE, noteUpdate)
        } else {
            if (!rawSnapshot) put(ComposerToken.METRICS, metrics)
            put(ComposerToken.FORMATS, ComposerSentence.outputFormatNames(settings, rawSnapshotName) { localizedFormats.getValue(it) }.joinToString(" + ").ifEmpty { "—" })
            if (!rawSnapshot) put(ComposerToken.NOTE, if (noteOn) noteUpdate else noteLeave)
        }
    }
    return ComposerValues(values, emphasis = emphasis?.let { mapOf(ComposerToken.WHEN to it) } ?: emptyMap())
}

/** The read-only summary sentence of cards and the detail, its choices in [tokenStyle]. */
@Composable
internal fun automationSummary(
    settings: ExportSettings,
    entry: ScheduledProfileEntry?,
    destination: String,
    sends: Boolean,
    tokenStyle: SpanStyle,
): AnnotatedString {
    val values = automationSentenceValues(settings, entry, destination, summary = true)
    val multiDay = values.values[ComposerToken.RANGE] != stringResource(R.string.automation_range_today) &&
        ComposerSentence.isMultiDay(entry)
    val template = stringResource(
        when {
            sends && multiDay -> R.string.automation_summary_send_multi
            sends -> R.string.automation_summary_send_single
            multiDay -> R.string.automation_summary_multi
            else -> R.string.automation_summary_single
        },
    )
    val segments = ComposerSentence.summarySegments(template, values.values, values.emphasis)
    return buildAnnotatedString {
        segments.forEach { segment ->
            when (segment) {
                is ComposerSegment.Text -> append(segment.text)
                is ComposerSegment.Token -> withStyle(tokenStyle) { append(segment.value) }
            }
        }
    }
}
