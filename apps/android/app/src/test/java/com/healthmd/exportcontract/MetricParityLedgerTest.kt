package com.healthmd.exportcontract

import com.healthmd.domain.model.HealthMetrics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class MetricParityLedgerTest {

    private data class IosParityRow(
        val iosMetricId: String,
        val iosCategory: String,
        val androidStatus: String,
        val androidMetricIds: List<String>,
        val notes: String,
    )

    private data class AndroidOnlyRow(
        val androidMetricId: String,
        val androidCategory: String,
        val unit: String,
        val androidStatus: String,
        val notes: String,
    )

    private fun findLedgerDoc(): File {
        val startDir = requireNotNull(System.getProperty("user.dir"))
        var dir: File? = File(startDir).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "docs/export-contract/android-ios-metric-parity-ledger.md")
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw AssertionError("Could not locate docs/export-contract/android-ios-metric-parity-ledger.md from $startDir")
    }

    private fun extractSection(text: String, heading: String): String {
        val start = text.indexOf("## $heading")
        require(start >= 0) { "Missing section: $heading" }
        val tail = text.substring(start)
        val next = tail.indexOf("\n## ", startIndex = 1)
        return if (next >= 0) tail.substring(0, next) else tail
    }

    private fun tableRows(section: String): List<List<String>> = section
        .lineSequence()
        .filter { it.startsWith("| ") }
        .filterNot { it.startsWith("|---") }
        .map { line ->
            line.trim().trim('|').split('|').map { it.trim() }
        }
        .filterNot { cells -> cells.firstOrNull()?.contains("metric id", ignoreCase = true) == true }
        .toList()

    private fun parseIosRows(): List<IosParityRow> = tableRows(
        extractSection(findLedgerDoc().readText(), "iOS metric parity table"),
    ).map { cells ->
        assertEquals("Unexpected iOS parity table width for row $cells", 5, cells.size)
        IosParityRow(
            iosMetricId = cells[0],
            iosCategory = cells[1],
            androidStatus = cells[2],
            androidMetricIds = cells[3].split(',').map { it.trim() }.filter { it.isNotBlank() },
            notes = cells[4],
        )
    }

    private fun parseAndroidOnlyRows(): List<AndroidOnlyRow> = tableRows(
        extractSection(findLedgerDoc().readText(), "Android-only supported metrics"),
    ).map { cells ->
        assertEquals("Unexpected Android-only table width for row $cells", 5, cells.size)
        AndroidOnlyRow(
            androidMetricId = cells[0],
            androidCategory = cells[1],
            unit = cells[2],
            androidStatus = cells[3],
            notes = cells[4],
        )
    }

    @Test
    fun iosLedger_containsEveryIosMetricWithAnAndroidDecision() {
        val rows = parseIosRows()
        val ids = rows.map { it.iosMetricId }.toSet()

        assertEquals("Ledger should track the full iOS HealthMetrics.swift inventory", 171, rows.size)
        assertEquals("Ledger should not duplicate iOS metric ids", 171, ids.size)
        assertTrue(ids.contains("medications"))
        assertTrue(ids.contains("symptom_headache"))
        assertTrue(ids.contains("uv_exposure"))
        assertTrue(ids.contains("cycling_ftp"))

        val validStatuses = setOf("supported", "mapped/alias", "health-connect-unavailable", "apple-exclusive")
        rows.forEach { row ->
            assertTrue("Invalid status for ${row.iosMetricId}: ${row.androidStatus}", row.androidStatus in validStatuses)
            assertTrue("Missing Android metric/status id for ${row.iosMetricId}", row.androidMetricIds.isNotEmpty())
            assertTrue("Missing notes for ${row.iosMetricId}", row.notes.isNotBlank())
        }
    }

    @Test
    fun ledgerSupportedAndMappedRows_referenceSelectableAndroidMetricIds() {
        val supportedIds = HealthMetrics.allMetrics.map { it.id }.toSet()
        val rows = parseIosRows().filter { it.androidStatus == "supported" || it.androidStatus == "mapped/alias" }

        rows.forEach { row ->
            row.androidMetricIds.forEach { androidId ->
                assertTrue(
                    "${row.iosMetricId} maps to non-selectable Android id $androidId",
                    androidId in supportedIds,
                )
            }
        }
    }

    @Test
    fun unavailableLedgerRows_areRepresentedInUnavailableCatalog() {
        val unavailableIds = HealthMetrics.unavailableMetrics.map { it.id }.toSet()
        val unavailableLedgerIds = parseIosRows()
            .filter { it.androidStatus == "health-connect-unavailable" || it.androidStatus == "apple-exclusive" }
            .map { it.iosMetricId }
            .toSet()

        assertTrue(
            "Unavailable catalog is missing ledger ids: ${unavailableLedgerIds - unavailableIds}",
            unavailableIds.containsAll(unavailableLedgerIds),
        )
        assertTrue("Medication gap should be explicit", "medications" in unavailableIds)
        assertTrue("Other HealthKit signals should be explicit", "uv_exposure" in unavailableIds)
        assertTrue("Per-symptom gaps should be explicit", "symptom_headache" in unavailableIds)
        assertTrue("Hearing gaps should be explicit", "headphone_audio" in unavailableIds)
        assertTrue("State of Mind gaps should be explicit", "daily_mood" in unavailableIds)
        assertTrue("Running dynamics gaps should be explicit", "running_ground_contact" in unavailableIds)
    }

    @Test
    fun everySelectableAndroidMetric_isExplainedByIosMappingOrAndroidOnlyTable() {
        val supportedIds = HealthMetrics.allMetrics.map { it.id }.toSet()
        val iosAndroidReferences = parseIosRows()
            .filter { it.androidStatus == "supported" || it.androidStatus == "mapped/alias" }
            .flatMap { it.androidMetricIds }
            .toSet()
        val androidOnlyRows = parseAndroidOnlyRows()
        val androidOnlyIds = androidOnlyRows.map { it.androidMetricId }.toSet()

        androidOnlyRows.forEach { row ->
            assertEquals("android-only", row.androidStatus)
            assertTrue("Android-only row ${row.androidMetricId} is not selectable", row.androidMetricId in supportedIds)
            assertTrue("Android-only row ${row.androidMetricId} should include a category", row.androidCategory.isNotBlank())
            assertTrue("Android-only row ${row.androidMetricId} should include notes", row.notes.isNotBlank())
        }

        assertTrue(
            "Selectable Android metrics missing from ledger: ${supportedIds - iosAndroidReferences - androidOnlyIds}",
            supportedIds.minus(iosAndroidReferences).minus(androidOnlyIds).isEmpty(),
        )
    }
}
