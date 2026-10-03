package com.healthmd.automation

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileResolution
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import org.junit.Test

class AutomationProfileResolutionTest {
    @Test
    fun `single automation reference resolves stable id before profile name`() {
        val idMatch = profile(id = "stable-id", name = "Archive")
        val nameMatch = profile(id = "other-id", name = "stable-id")

        val resolution = resolveAutomationProfileReference(
            profiles = listOf(nameMatch, idMatch),
            reference = "stable-id",
        )

        assertThat((resolution as ExportProfileResolution.Resolved).profile)
            .isEqualTo(idMatch)
    }

    @Test
    fun `single automation reference falls back to trimmed case-insensitive name`() {
        val archive = profile(id = "archive-id", name = "Weekly Archive")

        val resolution = resolveAutomationProfileReference(
            profiles = listOf(archive),
            reference = "  weekly archive  ",
        )

        assertThat((resolution as ExportProfileResolution.Resolved).profile)
            .isEqualTo(archive)
    }

    @Test
    fun `resolved profile with invalid snapshot fails closed instead of using live settings`() {
        val profile = profile(id = "invalid", name = "Invalid")

        assertThat(hasInvalidAutomationProfileSnapshot(profile, restoredSettings = null)).isTrue()
        assertThat(
            hasInvalidAutomationProfileSnapshot(profile, restoredSettings = ExportSettings()),
        ).isFalse()
        assertThat(
            hasInvalidAutomationProfileSnapshot(profile = null, restoredSettings = null),
        ).isFalse()
    }

    private fun profile(id: String, name: String) = ExportProfile(
        id = id,
        name = name,
        settingsSnapshotJson = "snapshot",
        target = ExportTarget.DEVICE_FOLDER,
        createdAtEpochMillis = 1L,
        updatedAtEpochMillis = 1L,
    )
}
