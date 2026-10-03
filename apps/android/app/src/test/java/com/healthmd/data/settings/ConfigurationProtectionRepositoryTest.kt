package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.PendingScheduledExportRequest
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ConfigurationProtectionRepositoryTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var repository: SettingsRepositoryImpl

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val dataStoreFile = temporaryFolder.newFolder().resolve("settings.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { dataStoreFile },
        )
        repository = SettingsRepositoryImpl(
            dataStore = dataStore,
            context = mockk<Context>(relaxed = true),
        )
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    @Test
    fun `atomic settings transform applies to latest schedule configuration`() = runTest {
        val edited = ExportSettings.newInstallDefaults().copy(
            scheduleEnabled = false,
            scheduleHour = 22,
            scheduleMinute = 45,
        )
        repository.updateExportSettings(edited)
        val residualDate = LocalDate.parse("2026-08-20")

        val updated = repository.updateExportSettingsAtomically { latest ->
            latest.copy(
                pendingScheduledExportRequests = listOf(
                    PendingScheduledExportRequest(date = residualDate),
                ),
            )
        }

        assertThat(updated.scheduleEnabled).isFalse()
        assertThat(updated.scheduleHour).isEqualTo(22)
        assertThat(updated.scheduleMinute).isEqualTo(45)
        assertThat(repository.getExportSettings().pendingScheduledExportRequests.single().date)
            .isEqualTo(residualDate)
    }

    @Test
    fun `protection defaults off and persists both states`() = runTest {
        assertThat(repository.preventAccidentalChanges.first()).isFalse()

        repository.setPreventAccidentalChanges(true)
        assertThat(repository.preventAccidentalChanges.first()).isTrue()

        repository.setPreventAccidentalChanges(false)
        assertThat(repository.preventAccidentalChanges.first()).isFalse()
    }
}
