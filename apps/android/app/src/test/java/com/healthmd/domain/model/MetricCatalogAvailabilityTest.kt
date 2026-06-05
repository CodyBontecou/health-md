package com.healthmd.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MetricCatalogAvailabilityTest {

    @Test
    fun supportedCatalog_excludesUnavailableMetricIds() {
        val supportedIds = HealthMetrics.allMetrics.map { it.id }.toSet()
        val unavailableIds = HealthMetrics.unavailableMetrics.map { it.id }.toSet()

        assertTrue("Phase 3 unavailable catalog should not be empty", unavailableIds.isNotEmpty())
        assertTrue(
            "Supported metrics and unavailable metrics must be disjoint",
            supportedIds.intersect(unavailableIds).isEmpty(),
        )
        assertFalse("Unsupported hearing selector must not be selectable", "audio_exposure" in supportedIds)
        assertTrue("Legacy hearing selector should be explained as unavailable", "audio_exposure" in unavailableIds)
        assertTrue("Apple Watch wrist temperature should be marked unavailable", "wrist_temperature" in unavailableIds)
        assertTrue("State of Mind should be marked unavailable", "state_of_mind_entries" in unavailableIds)
        assertTrue("Lung/inhaler metrics should be marked unavailable", "inhaler_usage" in unavailableIds)
    }

    @Test
    fun categories_onlyIncludeSupportedMetricGroups() {
        assertFalse(
            "Symptoms has no Health Connect-backed Android metrics and should not render as a 0/0 category",
            HealthMetricCategory.SYMPTOMS in HealthMetrics.categories,
        )
        assertFalse(
            "Hearing has no Health Connect-backed Android metrics and should not render as a selectable category",
            HealthMetricCategory.HEARING in HealthMetrics.categories,
        )
        assertTrue(
            "Every rendered category should contain at least one supported metric",
            HealthMetrics.categories.all { HealthMetrics.metricsForCategory(it).isNotEmpty() },
        )

        val selection = MetricSelectionState()
        assertFalse(selection.isCategoryFullyEnabled(HealthMetricCategory.SYMPTOMS))
        assertEquals(selection, selection.toggleCategory(HealthMetricCategory.SYMPTOMS))
    }

    @Test
    fun metricSelection_ignoresPersistedUnavailableIdsInCountsAndToggles() {
        val staleSelection = MetricSelectionState(
            enabledMetrics = setOf("steps", "audio_exposure", "wrist_temperature"),
        )

        assertEquals("Only supported metric IDs should count as enabled", 1, staleSelection.enabledCount)
        assertTrue(staleSelection.isEnabled("steps"))
        assertFalse(staleSelection.isEnabled("audio_exposure"))
        assertFalse(staleSelection.isEnabled("wrist_temperature"))
        assertEquals(
            "Toggling an unavailable metric should be a no-op",
            staleSelection,
            staleSelection.toggle("audio_exposure"),
        )

        val defaultWithStaleIds = MetricSelectionState(
            enabledMetrics = MetricSelectionState().enabledMetrics + setOf("audio_exposure", "wrist_temperature"),
        )
        assertEquals(HealthMetrics.totalCount, defaultWithStaleIds.enabledCount)
    }
}
