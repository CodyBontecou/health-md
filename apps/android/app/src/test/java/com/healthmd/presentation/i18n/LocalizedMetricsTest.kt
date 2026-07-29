package com.healthmd.presentation.i18n

import com.google.common.truth.Truth.assertThat
import com.healthmd.R
import com.healthmd.domain.model.HealthMetrics
import org.junit.Test

class LocalizedMetricsTest {
    @Test
    fun everySelectableRegistryMetricHasANativeLabelResource() {
        val missing = HealthMetrics.allMetrics
            .filter { it.displayNameRes() == R.string.metric_name_unknown }
            .map { it.id }

        assertThat(missing).isEmpty()
    }
}
