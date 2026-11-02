package com.healthmd.presentation.schedule

import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AutomationSentenceTest {
    private fun entry(
        enabled: Boolean = true,
        unit: ScheduledProfileCadenceUnit = ScheduledProfileCadenceUnit.DAY,
        value: Int = 1,
    ) = ScheduledProfileEntry(
        profileId = "p1",
        isEnabled = enabled,
        anchorEpochDay = 0,
        cadenceValue = value,
        cadenceUnit = unit,
    )

    private fun profile(
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        folder: String? = null,
        api: String? = null,
        gateway: String? = null,
    ) = ExportProfile(
        id = "p1",
        name = "Daily",
        settingsSnapshotJson = "{}",
        target = target,
        apiEndpointUrl = api,
        agentDataGatewayUrl = gateway,
        folderDisplayName = folder,
        createdAtEpochMillis = 0,
        updatedAtEpochMillis = 0,
    )

    @Test
    fun `one-unit cadences read as daily weekly or monthly`() {
        assertEquals(AutomationSentenceKind.DAILY, AutomationSentence.kind(entry()))
        assertEquals(AutomationSentenceKind.WEEKLY, AutomationSentence.kind(entry(unit = ScheduledProfileCadenceUnit.WEEK)))
        assertEquals(AutomationSentenceKind.MONTHLY, AutomationSentence.kind(entry(unit = ScheduledProfileCadenceUnit.MONTH)))
    }

    @Test
    fun `other counts are custom and unscheduled profiles run on demand`() {
        assertEquals(AutomationSentenceKind.CUSTOM, AutomationSentence.kind(entry(value = 3)))
        assertEquals(AutomationSentenceKind.MANUAL, AutomationSentence.kind(entry(enabled = false)))
        assertEquals(AutomationSentenceKind.MANUAL, AutomationSentence.kind(null))
    }

    @Test
    fun `destinations show a folder name or only the endpoint host`() {
        assertEquals("Vault", AutomationSentence.destination(profile(folder = " Vault ")))
        assertNull(AutomationSentence.destination(profile(folder = " ")))
        assertEquals(
            "api.example.com",
            AutomationSentence.destination(profile(ExportTarget.API_ENDPOINT, api = "https://api.example.com/health?token=secret")),
        )
        assertEquals(
            "gateway.example.com",
            AutomationSentence.destination(profile(ExportTarget.AGENT_DATA_GATEWAY, gateway = "https://gateway.example.com")),
        )
        assertNull(AutomationSentence.destination(profile(ExportTarget.API_ENDPOINT, api = "not a url")))
    }
}
