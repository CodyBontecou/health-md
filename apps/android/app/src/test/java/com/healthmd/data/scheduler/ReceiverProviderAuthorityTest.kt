package com.healthmd.data.scheduler

import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthProviderCaptureAuthority
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.RestorableHealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.domain.repository.forCaptureOperation
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ReceiverProviderAuthorityTest {
    @Test
    fun nightReceiverOccurrencesFreezeProviderAccountsAndKeepPendingAuthority() = runTest {
        val zone = ZoneId.of("UTC")
        val current = ExportSettings(exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT, apiEndpointUrl = "https://example.test/upload")
        val snapshot = AndroidExportSettingsSnapshot.capture(current, null, zone,
            AndroidCaptureContext(zone, SleepDayAttribution.NIGHT_BEGINS))
        val profile = ExportProfile(id = "synthetic-receiver", name = "Synthetic receiver",
            settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot),
            target = ExportTarget.API_ENDPOINT, apiEndpointUrl = current.apiEndpointUrl,
            createdAtEpochMillis = 0, updatedAtEpochMillis = 0)
        val settings = mockk<SettingsRepository>()
        coEvery { settings.getSleepDayAttribution() } returns SleepDayAttribution.NIGHT_BEGINS
        val planner = mockk<ExportEnginePinPlanner>()
        every { planner.forScheduledExport(any(), any(), any()) } returns null
        val factory = ScheduledProfileSnapshotFactory(planner, settings)
        val firstAuthority = HealthProviderCaptureAuthority(selectedProviderId = "whoop", providerIds = listOf("whoop"),
            connectionIds = mapOf("whoop" to "11111111-1111-4111-8111-111111111111"))
        val source = SyntheticSource(firstAuthority)

        val first = requireNotNull(factory.captureForNewOccurrence(profile, current, zone, source, forceFresh = true))
        val accepted = AndroidExportSettingsSnapshotCodec.decode(first.settingsSnapshotJson)
        assertEquals(firstAuthority, accepted.providerCaptureAuthority)
        assertEquals(1, source.captures)
        assertEquals(AndroidExportSettingsSnapshot.RECEIVER_PROVIDER_AUTHORITY_VERSION, accepted.version)
        assertThrows(Exception::class.java) { AndroidExportSettingsSnapshotCodec.encodeCanonical(accepted.copy(version = 3)) }
        assertThrows(Exception::class.java) { AndroidExportSettingsSnapshotCodec.encodeCanonical(accepted.copy(providerCaptureAuthority = null)) }
        val wrapped = com.healthmd.data.receivercoverage.ReceiverCoverageSnapshot.wrap(first.settingsSnapshotJson,
            com.healthmd.data.receivercoverage.ReceiverCoverageConfiguration("https://example.test/coverage", "synthetic", 0).json(),
            "synthetic-plan", "a".repeat(64), "b".repeat(64))
        assertEquals(accepted, AndroidExportSettingsSnapshotCodec.decodeScheduled(wrapped))

        source.authority = firstAuthority.copy(connectionIds = mapOf("whoop" to "22222222-2222-4222-8222-222222222222"))
        val next = requireNotNull(factory.captureForNewOccurrence(profile, current, zone, source, forceFresh = true))
        assertNotEquals("A changed account must not reuse the receiver's output-settings scope binding",
            first.settingsSnapshotJson, next.settingsSnapshotJson)
        val pending = requireNotNull(factory.restoreForRun(first, current, 7))
        assertEquals(firstAuthority, pending.executionProviderCaptureAuthority)
        assertEquals(true, pending.executionProviderCaptureAuthorityIsFrozen)
        source.forCaptureOperation(pending)
        assertEquals(listOf(firstAuthority), source.restored)
        assertEquals(2, source.captures)
    }

    private class SyntheticSource(var authority: HealthProviderCaptureAuthority) :
        HealthRepository by mockk(relaxed = true), RestorableHealthRepository {
        var captures = 0
        val restored = mutableListOf<HealthProviderCaptureAuthority>()
        override suspend fun captureProviderAuthority(): HealthProviderCaptureAuthority {
            captures++
            return authority
        }
        override suspend fun restoreProviderAuthority(authority: HealthProviderCaptureAuthority): HealthRepository {
            restored += authority
            return mockk()
        }
    }
}
