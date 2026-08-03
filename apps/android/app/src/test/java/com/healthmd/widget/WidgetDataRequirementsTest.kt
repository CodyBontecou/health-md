package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.WidgetDataRequirements
import org.junit.Test

class WidgetDataRequirementsTest {
    @Test
    fun `summary requests only phone-widget categories`() {
        val requirements = WidgetDataRequirements.forKind(HealthWidgetKind.SUMMARY)

        assertThat(requirements.activity).isTrue()
        assertThat(requirements.sleep).isTrue()
        assertThat(requirements.heart).isTrue()
    }

    @Test
    fun `installed widget requirements form a minimal union`() {
        val requirements = WidgetDataRequirements.forKinds(
            listOf(HealthWidgetKind.ACTIVITY, HealthWidgetKind.SLEEP),
        )

        assertThat(requirements.activity).isTrue()
        assertThat(requirements.sleep).isTrue()
        assertThat(requirements.heart).isFalse()
    }

    @Test
    fun `each focused widget requests only its category`() {
        assertThat(WidgetDataRequirements.forKind(HealthWidgetKind.ACTIVITY))
            .isEqualTo(WidgetDataRequirements(activity = true))
        assertThat(WidgetDataRequirements.forKind(HealthWidgetKind.HEART_RANGE))
            .isEqualTo(WidgetDataRequirements(heart = true))
        assertThat(WidgetDataRequirements.forKind(HealthWidgetKind.SLEEP))
            .isEqualTo(WidgetDataRequirements(sleep = true))
    }
}
