package com.healthmd.exportcontract

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class Phase3DocTest {

    private fun findPhase3Doc(): File {
        val startDir = requireNotNull(System.getProperty("user.dir"))
        var dir: File? = File(startDir).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "docs/export-contract/android-phase3-apple-exclusive.md")
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw AssertionError("Could not locate docs/export-contract/android-phase3-apple-exclusive.md from $startDir")
    }

    @Test
    fun phase3Doc_documentsAppleExclusiveAndUnavailableCatalog() {
        val text = findPhase3Doc().readText()

        assertTrue(text.contains("Phase 3"))
        assertTrue(text.contains("HealthMetrics.unavailableMetrics"))
        assertTrue(text.contains("Wrist Temperature"))
        assertTrue(text.contains("Electrodermal Activity"))
        assertTrue(text.contains("State of Mind"))
        assertTrue(text.contains("Heart Rate Recovery"))
        assertTrue(text.contains("Inhaler Usage"))
        assertTrue(text.contains("audio_exposure"))
        assertTrue(text.contains("do **not** emit fake `null` fields"))
    }
}
