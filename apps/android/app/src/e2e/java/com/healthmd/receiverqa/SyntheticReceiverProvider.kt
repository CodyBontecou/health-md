package com.healthmd.receiverqa

import android.content.Context
import com.healthmd.data.health.HealthDataProvider
import com.healthmd.data.health.RestorableHealthDataProvider
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HealthData
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import javax.inject.Named
import javax.inject.Singleton
import java.time.LocalDate
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout

/** E2E-only SDK boundary: never opens Health Connect, OAuth or any external source. */
class SyntheticReceiverProvider(private val context: Context) : HealthDataProvider, RestorableHealthDataProvider {
    override val providerId = "receiver_qa"
    override suspend fun fetchHealthData(date: LocalDate): HealthData {
        val state = ReceiverQaState(context)
        state.event("source_enter", date.toString())
        withTimeout(60_000) { while (state.read().getValue("capture_gate").toBoolean()) delay(100) }
        state.event("capture", date.toString())
        return HealthData(date, activity = ActivityData(steps = 170))
    }
    override suspend fun isAvailable() = true
    override suspend fun hasPermissions() = true
    override suspend fun hasHistoricalReadPermission() = true
    override suspend fun hasBackgroundReadPermission() = true
    override suspend fun getEarliestDataDate(): LocalDate = LocalDate.of(2020, 1, 1)
    override fun isBeforeFirstUnlock() = false
    override suspend fun acceptedConnectionId(): String = GRANT
    override fun forAcceptedConnection(connectionId: String?): HealthDataProvider {
        require(connectionId == GRANT)
        return this
    }
    companion object { const val GRANT = "00000000-0000-4000-8000-000000000170" }
}

@Module
@InstallIn(SingletonComponent::class)
object ReceiverQaProviderModule {
    @Provides @IntoSet @Singleton @Named("additional_runtime_health_providers")
    fun source(@ApplicationContext context: Context): HealthDataProvider = SyntheticReceiverProvider(context)
}
