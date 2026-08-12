package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.google.common.truth.Truth.assertThat
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

class SettingsRepositoryOnboardingMigrationTest {

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
    fun `fresh install persists incomplete state before folder selection`() = runTest {
        assertThat(repository.resolveOnboardingCompletion()).isFalse()

        repository.saveExportFolderUri("content://folder-selected-during-onboarding")

        assertThat(repository.resolveOnboardingCompletion()).isFalse()
        assertThat(repository.hasCompletedOnboarding.first()).isFalse()
    }

    @Test
    fun `pre-onboarding install with a folder migrates to completed`() = runTest {
        repository.saveExportFolderUri("content://legacy-folder")

        assertThat(repository.resolveOnboardingCompletion()).isTrue()
        assertThat(repository.hasCompletedOnboarding.first()).isTrue()
    }

    @Test
    fun `explicit completed state wins when folder is absent`() = runTest {
        repository.setOnboardingCompleted(true)

        assertThat(repository.resolveOnboardingCompletion()).isTrue()
    }
}
