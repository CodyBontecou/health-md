package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.google.common.truth.Truth.assertThat
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SettingsRepositoryScheduledReviewMomentTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var repository: SettingsRepositoryImpl

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("settings.preferences_pb")
        repository = SettingsRepositoryImpl(
            dataStore = PreferenceDataStoreFactory.create(scope = dataStoreScope, produceFile = { file }),
            context = mockk<Context>(relaxed = true),
        )
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    @Test
    fun scheduledSuccessCountsAndLeavesOneMoment() = runTest {
        assertThat(repository.takeScheduledReviewMoment()).isFalse()

        repository.recordScheduledReviewSuccess(epochDay = 20_000)
        repository.recordScheduledReviewSuccess(epochDay = 20_001)

        val state = repository.getReviewPromptState(migrationEpochMillis = 0)
        assertThat(state.successfulExportCount).isEqualTo(2)
        assertThat(state.successDayCount).isEqualTo(2)
        assertThat(repository.takeScheduledReviewMoment()).isTrue()
        assertThat(repository.takeScheduledReviewMoment()).isFalse()
    }

    @Test
    fun manualSuccessesCountWithoutLeavingAMoment() = runTest {
        repository.recordReviewEligibleSuccess(epochDay = 20_000)

        assertThat(repository.getReviewPromptState(0).successfulExportCount).isEqualTo(1)
        assertThat(repository.takeScheduledReviewMoment()).isFalse()
    }
}
