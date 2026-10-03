package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.testing.syntheticExportEnginePin
import org.junit.Test

/** Direct profile policy must preserve the snapshot's explicit engine authority, including legacy. */
class DirectProfileEngineAuthorityTest {
    @Test
    fun `frozen null pin remains explicit legacy instead of inheriting rollout`() {
        var planned = false
        val resolved = resolveDirectGeneratedFilesEnginePin(
            ExportSettings(
                executionEnginePin = null,
                executionEngineAuthorityIsFrozen = true,
            ),
        ) {
            planned = true
            syntheticExportEnginePin()
        }

        assertThat(resolved).isNull()
        assertThat(planned).isFalse()
    }

    @Test
    fun `saved-device settings without frozen authority plan a fresh pin`() {
        val plannedPin = syntheticExportEnginePin()

        val resolved = resolveDirectGeneratedFilesEnginePin(ExportSettings()) { plannedPin }

        assertThat(resolved).isEqualTo(plannedPin)
    }

    @Test
    fun `existing explicit pin is retained`() {
        val existing = syntheticExportEnginePin()
        var planned = false

        val resolved = resolveDirectGeneratedFilesEnginePin(
            ExportSettings(
                executionEnginePin = existing,
                executionEngineAuthorityIsFrozen = true,
            ),
        ) {
            planned = true
            syntheticExportEnginePin()
        }

        assertThat(resolved).isEqualTo(existing)
        assertThat(planned).isFalse()
    }
}
