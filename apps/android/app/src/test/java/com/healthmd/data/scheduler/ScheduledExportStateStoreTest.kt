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

    private companion object {
        const val PREFERENCES_NAME = "health_md_scheduled_export_state"
    }
}
