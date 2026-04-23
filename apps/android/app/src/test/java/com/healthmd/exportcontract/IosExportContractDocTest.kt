package com.healthmd.exportcontract

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class IosExportContractDocTest {

    private fun findContractDoc(): File {
        val startDir = requireNotNull(System.getProperty("user.dir"))
        var dir: File? = File(startDir).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "docs/export-contract/ios-export-contract.md")
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw AssertionError("Could not locate docs/export-contract/ios-export-contract.md from $startDir")
    }

    @Test
    fun iosContractDoc_exists_withCoreSections() {
        val doc = findContractDoc()
        val text = doc.readText()

        assertTrue(text.contains("# iOS Export Contract (Canonical Source of Truth)"))
        assertTrue(text.contains("## 1) JSON contract"))
        assertTrue(text.contains("## 2) Markdown frontmatter / Obsidian Bases contract"))
        assertTrue(text.contains("## 3) CSV contract"))
        assertTrue(text.contains("## 4) Compatibility-critical fields for `obsidian-health-md` visualizations"))
    }

    @Test
    fun iosContractDoc_containsFullAndSparseExamples() {
        val text = findContractDoc().readText()

        assertTrue(text.contains("### 1.4 Fully populated day example"))
        assertTrue(text.contains("### 1.5 Sparse day example"))
        assertTrue(text.contains("### 2.4 Fully populated Obsidian Bases example"))
        assertTrue(text.contains("### 2.5 Sparse Obsidian Bases example"))
        assertTrue(text.contains("### 3.3 Fully populated CSV example"))
        assertTrue(text.contains("### 3.4 Sparse CSV example"))
    }

    @Test
    fun iosContractDoc_callsOutPluginCriticalParityFields() {
        val text = findContractDoc().readText()

        assertTrue(text.contains("sleep.sleepStages[]"))
        assertTrue(text.contains("heart.heartRateSamples[]"))
        assertTrue(text.contains("heart.hrvSamples[]"))
        assertTrue(text.contains("vitals.bloodOxygenSamples[]"))
        assertTrue(text.contains("vitals.respiratoryRateSamples[]"))
        assertTrue(text.contains("activity.vo2Max"))
    }
}
