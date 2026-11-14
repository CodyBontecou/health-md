package com.healthmd.domain.onboarding

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.HealthMetrics
import org.junit.Test

class HealthPackTest {
    @Test
    fun packIdsMatchTheSharedOnboardingContract() {
        assertThat(HealthPack.entries.map { it.id })
            .containsExactly("sleep", "activity", "heart", "body", "mind", "nutrition", "cycle").inOrder()
    }

    @Test
    fun everyPackMetricIsARealExportableMetricAndPacksDoNotOverlap() {
        val known = HealthMetrics.allMetrics.map { it.id }.toSet()
        val all = HealthPack.entries.flatMap { it.metricIds }
        assertThat(known).containsAtLeastElementsIn(all)
        assertThat(all).containsNoDuplicates()
    }

    @Test
    fun firstThreePacksAreOnByDefaultAndCycleIsOff() {
        assertThat(HealthPack.defaults).containsExactly(HealthPack.SLEEP, HealthPack.ACTIVITY, HealthPack.HEART)
        assertThat(HealthPack.CYCLE.selectedByDefault).isFalse()
        assertThat(HealthPack.metricCount(HealthPack.defaults))
            .isEqualTo(HealthPack.SLEEP.metricCount + HealthPack.ACTIVITY.metricCount + HealthPack.HEART.metricCount)
    }

    @Test
    fun androidDifferencesAreExplicit() {
        // Health Connect HRV is RMSSD (the `hrv` metric); there is no State of Mind record.
        assertThat(HealthPack.SLEEP.metricIds).contains("hrv")
        assertThat(HealthPack.MIND.metricIds).containsExactly("mindful_minutes", "mindful_sessions")
    }

    @Test
    fun selectionIsTheUnionOfPackMetrics() {
        val ids = HealthPack.metricIds(setOf(HealthPack.BODY, HealthPack.MIND))
        assertThat(ids).containsExactlyElementsIn(HealthPack.BODY.metricIds + HealthPack.MIND.metricIds)
        assertThat(HealthPack.metricIds(emptySet())).isEmpty()
        assertThat(HealthPack.fullySelectedIn(ids)).containsExactly(HealthPack.BODY, HealthPack.MIND)
    }
}
