package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.testing.syntheticExportEnginePin
import org.junit.Test

/** Direct profile policy must preserve the snapshot's explicit engine authority, including legacy. */
class DirectProfileEngineAuthorityTest {
    @Test
    fun `wake capture rejects absent historical malformed or conflicting pins before admission`() {
        val context = com.healthmd.domain.model.AndroidCaptureContext(java.time.ZoneId.of("Asia/Kathmandu"),
            com.healthmd.domain.model.SleepDayAttribution.MORNING_ENDS)
        val historical = syntheticExportEnginePin(zoneId = context.zoneId.id)
        for (pin in listOf(null, historical, historical.copy(
            profile = com.healthmd.domain.exportengine.AndroidExportProfile.android_sleep_v6))) {
            assertThat(runCatching { requireDirectGeneratedFilesAuthority(context, pin) }.exceptionOrNull())
                .isInstanceOf(IllegalArgumentException::class.java)
        }
        // Night begins retains explicit legacy authority.
        requireDirectGeneratedFilesAuthority(context.copy(
            sleepDayAttribution = com.healthmd.domain.model.SleepDayAttribution.NIGHT_BEGINS,
            exportProfileID = null), null)
    }

    @Test
    fun `frozen capture never reads a changed device preference or ambient zone`() = kotlinx.coroutines.test.runTest {
        val original = com.healthmd.domain.model.AndroidCaptureContext(java.time.ZoneId.of("Asia/Kathmandu"),
            com.healthmd.domain.model.SleepDayAttribution.NIGHT_BEGINS)
        val restored = resolveDirectGeneratedFilesCaptureContext(ExportSettings(
            executionSleepCaptureContext = original, executionSleepCaptureAuthorityIsFrozen = true)) {
            error("Frozen profile capture must not read mutable device settings")
        }
        assertThat(restored).isEqualTo(original)
    }

    @Test
    fun `missing frozen capture cannot acquire current preference`() = kotlinx.coroutines.test.runTest {
        var captures = 0
        val failure = runCatching {
            resolveDirectGeneratedFilesCaptureContext(ExportSettings(executionSleepCaptureAuthorityIsFrozen = true)) {
                captures++
                error("Not a new operation")
            }
        }.exceptionOrNull()
        assertThat(failure).isInstanceOf(com.healthmd.domain.model.SleepAttributionUnavailableException::class.java)
        assertThat((failure as com.healthmd.domain.model.SleepAttributionUnavailableException).reason)
            .isEqualTo(com.healthmd.domain.model.SleepCaptureAuthorityError.MISSING_DURABLE_ATTRIBUTION)
        assertThat(captures).isEqualTo(0)
    }

    @Test
    fun `saved-device basis captures one new immutable context`() = kotlinx.coroutines.test.runTest {
        var captures = 0
        val fresh = com.healthmd.domain.model.AndroidCaptureContext(java.time.ZoneId.of("UTC"),
            com.healthmd.domain.model.SleepDayAttribution.NIGHT_BEGINS)
        val resolved = resolveDirectGeneratedFilesCaptureContext(ExportSettings()) { captures++; fresh }
        assertThat(resolved).isEqualTo(fresh)
        assertThat(captures).isEqualTo(1)
    }

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
