package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.MarkdownMerger
import org.junit.Test

class MarkdownMergerTest {

    private val merger = MarkdownMerger()

    @Test
    fun updateModeMergesFrontmatterAndPreservesCustomSections() {
        val existing = """
            ---
            date: 2026-06-05
            type: health-data
            mood: focused
            steps: 100
            ---

            Personal note before exported sections.

            ## Sleep

            - old sleep

            ## Journal

            I wrote this myself.
        """.trimIndent()

        val fresh = """
            ---
            date: 2026-06-05
            type: health-data
            steps: 1200
            active_calories: 400
            ---

            # Health Data — 2026-06-05

            ## Sleep

            - new sleep

            ## Activity

            - Steps: 1,200
        """.trimIndent()

        val merged = merger.merge(existing, fresh)

        assertThat(merged).contains("mood: focused")
        assertThat(merged).contains("steps: 1200")
        assertThat(merged).contains("active_calories: 400")
        assertThat(merged).contains("Personal note before exported sections.")
        assertThat(merged).contains("## Journal\n\nI wrote this myself.")
        assertThat(merged).contains("## Sleep\n\n- new sleep")
        assertThat(merged).doesNotContain("- old sleep")
        assertThat(merged).contains("## Activity\n\n- Steps: 1,200")
    }

    @Test
    fun updateModeHandlesExistingNoteWithoutFrontmatter() {
        val existing = """
            My note intro.

            ## Activity

            old activity
        """.trimIndent()

        val fresh = """
            ---
            date: 2026-06-05
            ---

            ## Activity

            new activity
        """.trimIndent()

        val merged = merger.merge(existing, fresh)

        assertThat(merged).startsWith("---\ndate: 2026-06-05\n---")
        assertThat(merged).contains("My note intro.")
        assertThat(merged).contains("## Activity\n\nnew activity")
        assertThat(merged).doesNotContain("old activity")
    }
}
