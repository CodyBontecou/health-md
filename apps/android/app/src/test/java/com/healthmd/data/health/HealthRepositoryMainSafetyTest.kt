package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import java.util.concurrent.Executors
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Test

/**
 * Health Connect record assembly (for example workout/route building) ran on the main thread
 * when a manual export read health data from `viewModelScope`; Play vitals reported main-thread
 * OOMs there. Provider reads must run off the caller's thread.
 */
class HealthRepositoryMainSafetyTest {

    @Test
    fun providerRangeReadRunsOffTheCallingThread() = runBlocking {
        val day = LocalDate.of(2026, 3, 15)
        var readThread: Thread? = null
        val provider = mockk<HealthDataProvider>()
        coEvery { provider.fetchHealthDataRange(any(), any(), any(), any(), any(), any(), any()) } answers {
            readThread = Thread.currentThread()
            firstArg<List<LocalDate>>().map(::HealthData)
        }
        val registry = mockk<HealthProviderRegistry>()
        every { registry.providerFor("health_connect") } returns provider
        val settings = mockk<SettingsRepository>()
        coEvery { settings.getSelectedHealthProviderId() } returns "health_connect"
        coEvery { settings.getSleepDayAttribution() } returns SleepDayAttribution.DEFAULT
        val repository = HealthRepositoryImpl(registry, settings)

        var callerThread: Thread? = null
        val caller = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "fake-main").also { callerThread = it }
        }.asCoroutineDispatcher()
        val result = try {
            withContext(caller) { repository.fetchHealthDataRange(dates = listOf(day)) }
        } finally {
            caller.close()
        }

        assertThat(result.map { it.date }).containsExactly(day)
        assertThat(readThread).isNotNull()
        assertThat(callerThread).isNotNull()
        assertThat(readThread).isNotSameInstanceAs(callerThread)
    }
}
