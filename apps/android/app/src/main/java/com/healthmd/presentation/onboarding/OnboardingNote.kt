package com.healthmd.presentation.onboarding

import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.onboarding.HealthPack
import java.time.LocalDate

/** One `Label: value` line of a rendered note section. */
data class NoteRow(val label: String, val value: String)

/** A `## Section` of a note, tagged with the pack whose colour it takes (null = neutral). */
data class NoteSection(val title: String, val pack: HealthPack?, val rows: List<NoteRow>)

/** One day of the first-note preview: the rendered view and the exact file bytes behind it. */
data class OnboardingNoteDay(
    val date: LocalDate,
    val fileName: String? = null,
    val raw: String? = null,
    val sections: List<NoteSection> = emptyList(),
) {
    val hasNote: Boolean get() = raw != null
}

enum class SampleReason { NO_DATA, NO_HEALTH_ACCESS }

sealed interface NotePreviewState {
    data object Idle : NotePreviewState
    data object Loading : NotePreviewState
    /** Real notes for each of the last seven days, oldest first. */
    data class Ready(val days: List<OnboardingNoteDay>) : NotePreviewState
    /** Nothing to write yet: show a sample note and keep the free export unused. */
    data class Sample(val reason: SampleReason, val days: List<OnboardingNoteDay>) : NotePreviewState
}

/**
 * Turns the Markdown the export pipeline would write into the rendered first-note view. It reads
 * the default template shape (frontmatter, `#` title, `##` sections and `- **Label:** value`
 * bullets) and ignores tables, callouts and prose, so a custom template still previews its
 * recognised rows and always keeps its exact text behind "View raw file".
 */
object OnboardingNoteParser {
    private val headingRegex = Regex("^(#{2,6})\\s+(.+)$")
    private val boldRowRegex = Regex("^[-*+•]\\s+\\*\\*(.+?):\\*\\*\\s*(.*)$")
    private val plainRowRegex = Regex("^[-*+•]\\s+([^:]{1,48}):\\s+(.+)$")

    fun parse(markdown: String): List<NoteSection> {
        val lines = stripFrontmatter(markdown).lines()
        val sections = mutableListOf<NoteSection>()
        var title: String? = null
        var rows = mutableListOf<NoteRow>()
        fun flush() {
            val name = title
            if (name != null && rows.isNotEmpty()) sections += NoteSection(name, packFor(name), rows.toList())
            rows = mutableListOf()
        }
        for (raw in lines) {
            val line = raw.trim()
            val heading = headingRegex.matchEntire(line)
            if (heading != null) {
                flush()
                title = cleanTitle(heading.groupValues[2])
                continue
            }
            if (title == null) continue
            val row = boldRowRegex.matchEntire(line) ?: plainRowRegex.matchEntire(line) ?: continue
            val label = row.groupValues[1].trim()
            val value = row.groupValues[2].trim()
            if (label.isNotEmpty() && value.isNotEmpty()) rows += NoteRow(label, value)
        }
        flush()
        return sections
    }

    /** Builds seven days (oldest first) from a dry-run preview, keeping days without a note. */
    fun days(dates: List<LocalDate>, preview: ExportPreview): List<OnboardingNoteDay> {
        val byDate = preview.days.associateBy { it.date }
        return dates.sorted().map { date ->
            val day = byDate[date]
            val file = day?.files?.firstOrNull { it.format == ExportFormat.MARKDOWN } ?: day?.files?.firstOrNull()
            if (file == null) {
                OnboardingNoteDay(date)
            } else {
                val content = file.content + file.previewTailContent
                OnboardingNoteDay(
                    date = date,
                    fileName = file.relativePath.substringAfterLast('/'),
                    raw = content,
                    sections = if (file.format == ExportFormat.MARKDOWN || file.format == ExportFormat.OBSIDIAN_BASES) {
                        parse(content)
                    } else {
                        emptyList()
                    },
                )
            }
        }
    }

    /** Headline chips: the first row of each section, at most [limit]. */
    fun highlights(sections: List<NoteSection>, limit: Int = 5): List<Pair<NoteSection, NoteRow>> =
        sections.mapNotNull { section -> section.rows.firstOrNull()?.let { section to it } }.take(limit)

    /** Bar value for the week chart: sleep total minutes, else steps, else null (flat bars). */
    fun chartValue(day: OnboardingNoteDay): Double? {
        val sleep = day.sections.firstOrNull { it.pack == HealthPack.SLEEP }
            ?.rows?.firstOrNull { it.label.equals("Total", ignoreCase = true) }
        sleep?.let { row -> durationMinutes(row.value)?.let { return it } }
        val steps = day.sections.flatMap { it.rows }.firstOrNull { it.label.equals("Steps", ignoreCase = true) }
        return steps?.value?.filter(Char::isDigit)?.toDoubleOrNull()
    }

    /** True when every day's chart value comes from the sleep total. */
    fun chartIsSleep(days: List<OnboardingNoteDay>): Boolean = days.any { day ->
        day.sections.any { s -> s.pack == HealthPack.SLEEP && s.rows.any { it.label.equals("Total", true) } }
    }

    internal fun durationMinutes(value: String): Double? {
        val hours = Regex("(\\d+)\\s*h").find(value)?.groupValues?.get(1)?.toDoubleOrNull()
        val minutes = Regex("(\\d+)\\s*m(?!s)").find(value)?.groupValues?.get(1)?.toDoubleOrNull()
        if (hours == null && minutes == null) return null
        return (hours ?: 0.0) * 60 + (minutes ?: 0.0)
    }

    private fun stripFrontmatter(markdown: String): String {
        val text = markdown.trimStart('﻿')
        if (!text.startsWith("---")) return text
        val end = text.indexOf("\n---", startIndex = 3)
        return if (end < 0) text else text.substring((end + 4).coerceAtMost(text.length))
    }

    /** Drops a leading emoji or symbol prefix ("😴 Sleep" -> "Sleep"). */
    private fun cleanTitle(raw: String): String =
        raw.trim().dropWhile { !it.isLetterOrDigit() }.trim().ifEmpty { raw.trim() }

    internal fun packFor(title: String): HealthPack? {
        val t = title.lowercase()
        return when {
            t.startsWith("sleep") -> HealthPack.SLEEP
            t.startsWith("activity") || t.startsWith("workout") -> HealthPack.ACTIVITY
            t.startsWith("heart") || t.startsWith("vital") || t.startsWith("respiratory") -> HealthPack.HEART
            t.startsWith("body") -> HealthPack.BODY
            t.startsWith("mind") -> HealthPack.MIND
            t.startsWith("nutrition") -> HealthPack.NUTRITION
            t.startsWith("cycle") || t.startsWith("reproductive") -> HealthPack.CYCLE
            else -> null
        }
    }
}

/**
 * The sample note shown before there is Health Connect data. Values are fixed, clearly labelled
 * as sample, never written to disk, and only cover the packs the user picked.
 */
object OnboardingSampleNote {
    private val sampleRows: Map<HealthPack, Pair<String, List<NoteRow>>> = mapOf(
        HealthPack.SLEEP to ("Sleep" to listOf(
            NoteRow("Total", "7h 30m"), NoteRow("Deep", "1h 18m"), NoteRow("REM", "1h 52m"),
            NoteRow("HRV (RMSSD)", "60.0 ms"),
        )),
        HealthPack.ACTIVITY to ("Activity" to listOf(
            NoteRow("Steps", "8,000"), NoteRow("Active Calories", "624 kcal"), NoteRow("Exercise", "42 min"),
        )),
        HealthPack.HEART to ("Heart" to listOf(
            NoteRow("Average HR", "72 bpm"), NoteRow("Min HR", "52 bpm"), NoteRow("Max HR", "148 bpm"),
        )),
        HealthPack.BODY to ("Body" to listOf(NoteRow("Weight", "72.4 kg"), NoteRow("Body Fat", "18.2%"))),
        HealthPack.MIND to ("Mindfulness" to listOf(NoteRow("Mindful Minutes", "12 min"))),
        HealthPack.NUTRITION to ("Nutrition" to listOf(NoteRow("Calories", "2,140 kcal"), NoteRow("Protein", "118 g"))),
        HealthPack.CYCLE to ("Cycle" to listOf(NoteRow("Flow", "Light"))),
    )

    fun sections(packs: Set<HealthPack>): List<NoteSection> = HealthPack.entries
        .filter { it in packs }
        .mapNotNull { pack -> sampleRows[pack]?.let { (title, rows) -> NoteSection(title, pack, rows) } }

    fun raw(date: LocalDate, sections: List<NoteSection>): String = buildString {
        append("---\ndate: ").append(date).append("\ntype: health-data\n---\n\n")
        append("# Health Data — ").append(date).append('\n')
        sections.forEach { section ->
            append("\n## ").append(section.title).append("\n\n")
            section.rows.forEach { append("- **").append(it.label).append(":** ").append(it.value).append('\n') }
        }
    }

    fun days(dates: List<LocalDate>, packs: Set<HealthPack>): List<OnboardingNoteDay> {
        val sections = sections(packs)
        return dates.sorted().map { date ->
            OnboardingNoteDay(date = date, fileName = "$date.md", raw = raw(date, sections), sections = sections)
        }
    }
}
