package com.healthmd.presentation.release

import com.google.common.truth.Truth.assertThat
import com.healthmd.export.FakeSettingsRepository
import kotlinx.coroutines.test.runTest
import org.junit.Test

class ReleaseNotesGateTest {
    @Test
    fun shouldPresent_whenVersionChangedAndSetupComplete() {
        assertThat(
            ReleaseNotesGate.shouldPresent(
                currentVersionKey = "1.4.0+42",
                lastPresentedVersionKey = "1.3.0+41",
                hasCompletedSetup = true,
                suppressForAutomationOrDebug = false,
            )
        ).isTrue()
    }

    @Test
    fun doesNotPresent_whenAlreadySeenOrSuppressedOrBeforeSetup() {
        assertThat(ReleaseNotesGate.shouldPresent("1.4.0+42", "1.4.0+42", true, false)).isFalse()
        assertThat(ReleaseNotesGate.shouldPresent("1.4.0+42", null, false, false)).isFalse()
        assertThat(ReleaseNotesGate.shouldPresent("1.4.0+42", null, true, true)).isFalse()
        assertThat(ReleaseNotesGate.shouldPresent(null, null, true, false)).isFalse()
    }

    @Test
    fun repositoryPersistsLastPresentedReleaseVersion() = runTest {
        val repository = FakeSettingsRepository()

        assertThat(repository.getLastPresentedReleaseVersion()).isNull()

        repository.setLastPresentedReleaseVersion("1.4.0+42")

        assertThat(repository.getLastPresentedReleaseVersion()).isEqualTo("1.4.0+42")
    }
}
