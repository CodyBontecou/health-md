package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.SleepDayAttribution
import io.mockk.mockk
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

/**
 * Issue #104: the sleep attribution preference is a device-local capture setting
 * persisted in DataStore with the shared cross-platform wire values.
 */
class SettingsRepositorySleepAttributionTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var repository: SettingsRepositoryImpl

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { temporaryFolder.newFile("sleep-attribution.preferences_pb") },
        )
        repository = SettingsRepositoryImpl(dataStore, mockk<Context>(relaxed = true))
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    @Test
    fun `missing preference fails closed to night begins`() = runTest {
        assertThat(repository.getSleepDayAttribution()).isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
        assertThat(repository.sleepDayAttribution.first()).isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
    }

    @Test
    fun `persisted morning ends round trips through the flow`() = runTest {
        repository.setSleepDayAttribution(SleepDayAttribution.MORNING_ENDS)

        assertThat(repository.getSleepDayAttribution()).isEqualTo(SleepDayAttribution.MORNING_ENDS)
        assertThat(repository.sleepDayAttribution.first()).isEqualTo(SleepDayAttribution.MORNING_ENDS)
    }

    @Test
    fun `reselecting night begins persists the shipped default`() = runTest {
        repository.setSleepDayAttribution(SleepDayAttribution.MORNING_ENDS)
        repository.setSleepDayAttribution(SleepDayAttribution.NIGHT_BEGINS)

        assertThat(repository.getSleepDayAttribution()).isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
    }

    @Test
    fun `unknown wire values fail closed to the shipped default`() {
        assertThat(SleepDayAttribution.fromWireValue(null)).isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
        assertThat(SleepDayAttribution.fromWireValue("solstice"))
            .isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
        assertThat(SleepDayAttribution.fromWireValue("morning_ends"))
            .isEqualTo(SleepDayAttribution.MORNING_ENDS)
        assertThat(SleepDayAttribution.fromWireValue("night_begins"))
            .isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
    }
}
