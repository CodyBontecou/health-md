package com.healthmd.presentation.schedule.composer

import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import java.time.LocalDate

/**
 * The automation composer's sentence, mirroring the iOS `AutomationSentence` token model: the
 * word order lives in one localized template per language with `{token}` placeholders, so each
 * choice can sit wherever the grammar needs it. Pure, so it is unit tested.
 */
enum class ComposerToken(val key: String) {
    WHEN("when"), RANGE("range"), METRICS("metrics"), WHERE("where"), FORMATS("formats"), NOTE("note");

    companion object {
        fun fromKey(key: String): ComposerToken? = entries.firstOrNull { it.key == key }
    }
}

sealed interface ComposerSegment {
    data class Text(val text: String) : ComposerSegment
    data class Token(val token: ComposerToken, val value: String) : ComposerSegment
}

/** The time of day a daily run names: "Every morning at 7:30". */
enum class ComposerDayPeriod {
    MORNING, AFTERNOON, EVENING, NIGHT;

    companion object {
        fun of(hour: Int): ComposerDayPeriod = when (hour) {
            in 5..11 -> MORNING
            in 12..16 -> AFTERNOON
            in 17..20 -> EVENING
            else -> NIGHT
        }
    }
}

/** How the schedule reads as the sentence's `{when}`. */
enum class ComposerWhenKind { MANUAL, DAILY, WEEKLY, MONTHLY, CUSTOM }

object ComposerSentence {
    /**
     * Splits a template on `{token}`. Unknown names or tokens without a value stay as text, so a
     * bad translation shows up visibly instead of dropping a choice. When [emphasis] names a part
     * of a value, only that part is the choice ("Every morning at " + "7:30").
     */
    fun segments(
        template: String,
        values: Map<ComposerToken, String>,
        emphasis: Map<ComposerToken, String> = emptyMap(),
    ): List<ComposerSegment> {
        val result = mutableListOf<ComposerSegment>()
        fun text(value: String) {
            if (value.isEmpty()) return
            val last = result.lastOrNull()
            if (last is ComposerSegment.Text) result[result.lastIndex] = ComposerSegment.Text(last.text + value)
            else result += ComposerSegment.Text(value)
        }
        var rest = template
        while (true) {
            val open = rest.indexOf('{')
            val close = if (open >= 0) rest.indexOf('}', open) else -1
            if (open < 0 || close < 0) break
            val token = ComposerToken.fromKey(rest.substring(open + 1, close))
            val value = token?.let(values::get)
            if (token == null || value == null) {
                text(rest.substring(0, close + 1))
            } else {
                text(rest.substring(0, open))
                val part = emphasis[token]
                val at = if (part.isNullOrEmpty() || part == value) -1 else value.indexOf(part)
                if (at >= 0) {
                    text(value.substring(0, at))
                    result += ComposerSegment.Token(token, part!!)
                    text(value.substring(at + part.length))
                } else {
                    result += ComposerSegment.Token(token, value)
                }
            }
            rest = rest.substring(close + 1)
        }
        text(rest)
        return result
    }

    fun plainText(segments: List<ComposerSegment>): String = segments.joinToString("") {
        when (it) {
            is ComposerSegment.Text -> it.text
            is ComposerSegment.Token -> it.value
        }
    }

    /** Every `{token}` a composer template must keep. */
    fun missingTokens(template: String): Set<ComposerToken> =
        ComposerToken.entries.filterNot { template.contains("{${it.key}}") }.toSet()

    fun whenKind(entry: ScheduledProfileEntry?): ComposerWhenKind = when {
        entry == null || !entry.isEnabled -> ComposerWhenKind.MANUAL
        entry.cadenceValue != 1 -> ComposerWhenKind.CUSTOM
        entry.cadenceUnit == ScheduledProfileCadenceUnit.DAY -> ComposerWhenKind.DAILY
        entry.cadenceUnit == ScheduledProfileCadenceUnit.WEEK -> ComposerWhenKind.WEEKLY
        else -> ComposerWhenKind.MONTHLY
    }

    /** Days one run writes. Today Refresh runs keep today's partial file fresh instead. */
    fun rangeDays(entry: ScheduledProfileEntry?): Int = (entry?.lookbackDays ?: 1).coerceAtLeast(1)

    fun isMultiDay(entry: ScheduledProfileEntry?): Boolean = rangeDays(entry) > 1

    /** The day the composer previews: the most recent complete day a run writes. */
    fun previewDate(today: LocalDate): LocalDate = today.minusDays(1)
}
