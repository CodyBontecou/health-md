package com.healthmd.presentation.schedule.composer

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import java.io.File
import java.time.LocalDate
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Test

class ComposerSentenceTest {
    private val values = mapOf(
        ComposerToken.WHEN to "Every morning at 7:30",
        ComposerToken.RANGE to "yesterday",
        ComposerToken.METRICS to "64 metrics",
        ComposerToken.WHERE to "Vault",
        ComposerToken.FORMATS to "Markdown",
        ComposerToken.NOTE to "update my daily note",
    )

    @Test
    fun templatesSplitIntoTextAndTokensInTemplateOrder() {
        val segments = ComposerSentence.segments("{when}, write {range}’s {metrics} to {where}.", values)
        assertThat(segments).containsExactly(
            ComposerSegment.Token(ComposerToken.WHEN, "Every morning at 7:30"),
            ComposerSegment.Text(", write "),
            ComposerSegment.Token(ComposerToken.RANGE, "yesterday"),
            ComposerSegment.Text("’s "),
            ComposerSegment.Token(ComposerToken.METRICS, "64 metrics"),
            ComposerSegment.Text(" to "),
            ComposerSegment.Token(ComposerToken.WHERE, "Vault"),
            ComposerSegment.Text("."),
        ).inOrder()
    }

    @Test
    fun summaryLeavesOutOptionalPartsWhoseTokensHaveNoValue() {
        val template = "{when}, write {range}[’s {metrics}][ as {formats}] to {where}[ and {note}]."
        val sparse = values - ComposerToken.METRICS - ComposerToken.FORMATS - ComposerToken.NOTE
        assertThat(ComposerSentence.plainText(ComposerSentence.summarySegments(template, sparse)))
            .isEqualTo("Every morning at 7:30, write yesterday to Vault.")
        assertThat(ComposerSentence.plainText(ComposerSentence.summarySegments(template, values)))
            .isEqualTo("Every morning at 7:30, write yesterday’s 64 metrics as Markdown to Vault and update my daily note.")
        val multi = "{when}, write[ {metrics} for] {range}[ as {formats}] to {where}[ and {note}]."
        assertThat(ComposerSentence.plainText(ComposerSentence.summarySegments(multi, sparse + (ComposerToken.RANGE to "the last 7 days"))))
            .isEqualTo("Every morning at 7:30, write the last 7 days to Vault.")
    }

    @Test
    fun emphasisMakesOnlyTheTimeTheChoice() {
        val segments = ComposerSentence.segments("{when}.", values, mapOf(ComposerToken.WHEN to "7:30"))
        assertThat(segments).containsExactly(
            ComposerSegment.Text("Every morning at "),
            ComposerSegment.Token(ComposerToken.WHEN, "7:30"),
            ComposerSegment.Text("."),
        ).inOrder()
    }

    @Test
    fun unknownTokensStayVisibleAsText() {
        val segments = ComposerSentence.segments("{when} {oops} {note}", values)
        assertThat(ComposerSentence.plainText(segments)).isEqualTo("Every morning at 7:30 {oops} update my daily note")
    }

    @Test
    fun scheduleKindsAndRanges() {
        val daily = ScheduledProfileEntry(profileId = "p", isEnabled = true, anchorEpochDay = 0, hour = 7, minute = 30)
        assertThat(ComposerSentence.whenKind(null)).isEqualTo(ComposerWhenKind.MANUAL)
        assertThat(ComposerSentence.whenKind(daily.copy(isEnabled = false))).isEqualTo(ComposerWhenKind.MANUAL)
        assertThat(ComposerSentence.whenKind(daily)).isEqualTo(ComposerWhenKind.DAILY)
        assertThat(ComposerSentence.whenKind(daily.copy(cadenceUnit = ScheduledProfileCadenceUnit.WEEK))).isEqualTo(ComposerWhenKind.WEEKLY)
        assertThat(ComposerSentence.whenKind(daily.copy(cadenceValue = 2))).isEqualTo(ComposerWhenKind.CUSTOM)
        assertThat(ComposerSentence.isMultiDay(daily)).isFalse()
        assertThat(ComposerSentence.isMultiDay(daily.copy(lookbackDays = 7))).isTrue()
        assertThat(ComposerDayPeriod.of(7)).isEqualTo(ComposerDayPeriod.MORNING)
        assertThat(ComposerDayPeriod.of(21)).isEqualTo(ComposerDayPeriod.NIGHT)
        assertThat(ComposerSentence.previewDate(LocalDate.of(2026, 10, 31))).isEqualTo(LocalDate.of(2026, 10, 30))
    }

    @Test
    fun everyLocaleTemplateKeepsEveryToken() {
        val root = resourceRoot()
        root.listFiles().orEmpty().filter { File(it, "redesign.xml").isFile }.forEach { folder ->
            val strings = strings(File(folder, "redesign.xml"))
            listOf("composer_template_single", "composer_template_multi").forEach { key ->
                val template = strings.getValue(key)
                assertWithMessage("$key in ${folder.name}").that(ComposerSentence.missingTokens(template)).isEmpty()
            }
        }
    }

    private fun strings(file: File): Map<String, String> {
        val nodes = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).getElementsByTagName("string")
        return (0 until nodes.length).associate { i ->
            nodes.item(i).attributes.getNamedItem("name").nodeValue to nodes.item(i).textContent
        }
    }

    private fun resourceRoot(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            val resources = File(directory, "app/src/main/res")
            if (resources.isDirectory) return resources
            directory = directory.parentFile
        }
        error("Could not locate app/src/main/res")
    }
}
