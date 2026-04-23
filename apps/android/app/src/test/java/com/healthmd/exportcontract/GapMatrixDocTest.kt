package com.healthmd.exportcontract

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class GapMatrixDocTest {

    private fun findGapMatrix(): File {
        val startDir = requireNotNull(System.getProperty("user.dir"))
        var dir: File? = File(startDir).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "docs/export-contract/android-ios-gap-matrix.md")
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw AssertionError("Could not locate docs/export-contract/android-ios-gap-matrix.md from $startDir")
    }

    @Test
    fun gapMatrix_exists_withCoreSections() {
        val text = findGapMatrix().readText()
        assertTrue(text.contains("# Android"))
        assertTrue(text.contains("## 1) JSON format gaps"))
        assertTrue(text.contains("## 2) Frontmatter / Obsidian Bases gaps"))
        assertTrue(text.contains("## 3) CSV format gaps"))
        assertTrue(text.contains("## 4) Prioritized implementation task list"))
        assertTrue(text.contains("## 5) Rollout recommendation"))
        assertTrue(text.contains("## 6) Summary counts"))
    }

    @Test
    fun gapMatrix_hasP0Tasks() {
        val text = findGapMatrix().readText()
        // All P0 tier tasks must be listed
        assertTrue(text.contains("T0-01"))
        assertTrue(text.contains("sleepStages"))
        assertTrue(text.contains("T0-04"))
        assertTrue(text.contains("ISO 8601"))
        assertTrue(text.contains("T0-10")) // vo2Max under activity
    }

    @Test
    fun gapMatrix_callsOutCriticalPluginFields() {
        val text = findGapMatrix().readText()
        // Plugin-critical fields called out by name
        assertTrue(text.contains("sleepStages"))
        assertTrue(text.contains("startDate"))
        assertTrue(text.contains("durationSeconds"))
        assertTrue(text.contains("activity.vo2Max"))
        assertTrue(text.contains("heartRateSamples"))
        assertTrue(text.contains("bloodOxygenSamples"))
    }

    @Test
    fun gapMatrix_hasRolloutRecommendation() {
        val text = findGapMatrix().readText()
        assertTrue(text.contains("dual-write"))
    }
}
