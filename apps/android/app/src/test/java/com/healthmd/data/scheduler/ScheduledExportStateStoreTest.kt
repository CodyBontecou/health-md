package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import java.time.LocalDate
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ScheduledExportStateStoreTest {
    private lateinit var context: Context

    @Before
    fun clearState() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    @Test
    fun generationSurvivesProcessStateReload() {
        val occurrence = ScheduledExportOccurrence(
            configuration = ScheduledExportConfiguration(
                cadenceValue = 15,
                cadenceUnit = ScheduleCadenceUnit.MINUTES,
                hour = 6,
                minute = 0,
                lookbackDays = 1,
                dateWindow = ScheduleDateWindow.PAST_COMPLETE_DAYS,
                target = ExportTarget.DEVICE_FOLDER,
                destinationFingerprint = null,
                zoneId = "UTC",
            ),
            triggerAtMillis = 1_800_000_000_000L,
            intendedLocalDate = LocalDate.parse("2027-01-15"),
            generation = "generation-process-reload",
        )
        val firstProcessStore = ScheduledExportStateStore(context)
        firstProcessStore.markGenerationMigrationComplete()
        firstProcessStore.save(occurrence)

        val reloadedProcessStore = ScheduledExportStateStore(context)

        assertThat(reloadedProcessStore.load()).isEqualTo(occurrence)
        assertThat(reloadedProcessStore.isGenerationMigrationComplete()).isTrue()

        reloadedProcessStore.clear()
        assertThat(ScheduledExportStateStore(context).load()).isNull()
        assertThat(ScheduledExportStateStore(context).isGenerationMigrationComplete()).isTrue()
    }

    @Test
    fun transitionAtomicallyAdmitsReplacementAndSurvivesEveryDurablePhase() {
        val old = occurrence("generation-old", 1_800_000_000_000L)
        val replacement = occurrence("generation-new", 1_800_000_900_000L)
        val store = ScheduledExportStateStore(context)
        store.markGenerationMigrationComplete()
        store.save(old)
        store.prepareTransition(
            ScheduledExportTransition(
                replacement = replacement,
                previousGeneration = old.generation,
                previousOccurrenceId = old.id,
                cleanupScope = ScheduledExportCleanupScope.GENERATION,
                phase = ScheduledExportTransitionPhase.PREPARED,
                reason = "TEST_REPLACEMENT",
            ),
        )

        val afterPrepare = ScheduledExportStateStore(context)
        assertThat(afterPrepare.load()).isEqualTo(replacement)
        assertThat(afterPrepare.loadTransition()?.previousGeneration).isEqualTo(old.generation)
        assertThat(afterPrepare.loadTransition()?.phase)
            .isEqualTo(ScheduledExportTransitionPhase.PREPARED)

        assertThat(
            afterPrepare.updateTransitionPhase(
                "generation-new",
                ScheduledExportTransitionPhase.OLD_WORK_CANCELLED,
            ),
        ).isTrue()
        assertThat(ScheduledExportStateStore(context).loadTransition()?.phase)
            .isEqualTo(ScheduledExportTransitionPhase.OLD_WORK_CANCELLED)
        assertThat(afterPrepare.finalizeTransition("generation-new")).isFalse()

        assertThat(
            afterPrepare.updateTransitionPhase(
                "generation-new",
                ScheduledExportTransitionPhase.NEW_OCCURRENCE_ARMED,
            ),
        ).isTrue()
        assertThat(afterPrepare.finalizeTransition("generation-new")).isTrue()

        val finalized = ScheduledExportStateStore(context)
        assertThat(finalized.load()).isEqualTo(replacement)
        assertThat(finalized.loadTransition()).isNull()
        assertThat(finalized.isGenerationMigrationComplete()).isTrue()
    }

    private fun occurrence(generation: String, triggerAtMillis: Long) =
        ScheduledExportOccurrence(
            configuration = ScheduledExportConfiguration(
                cadenceValue = 15,
                cadenceUnit = ScheduleCadenceUnit.MINUTES,
                hour = 6,
                minute = 0,
                lookbackDays = 1,
                dateWindow = ScheduleDateWindow.PAST_COMPLETE_DAYS,
                target = ExportTarget.DEVICE_FOLDER,
                destinationFingerprint = null,
                zoneId = "UTC",
            ),
            triggerAtMillis = triggerAtMillis,
            intendedLocalDate = LocalDate.parse("2027-01-15"),
            generation = generation,
        )

    private companion object {
        const val PREFERENCES_NAME = "health_md_scheduled_export_state"
    }
}
