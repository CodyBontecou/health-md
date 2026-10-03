package com.healthmd.data.onboardinganalytics

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

private val Context.onboardingAnalyticsDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "onboarding_analytics"
)

@Serializable
internal data class PersistedOnboardingAnalyticsState(
    val installId: String? = null,
    val events: List<OnboardingAnalyticsEvent> = emptyList(),
    val emittedMilestones: List<String> = emptyList(),
)

internal interface OnboardingAnalyticsStatePersistence {
    suspend fun read(): PersistedOnboardingAnalyticsState
    suspend fun update(
        transform: (PersistedOnboardingAnalyticsState) -> PersistedOnboardingAnalyticsState,
    ): PersistedOnboardingAnalyticsState
}

@Singleton
internal class DataStoreOnboardingAnalyticsStatePersistence @Inject constructor(
    @ApplicationContext context: Context,
) : OnboardingAnalyticsStatePersistence {
    private val dataStore = context.onboardingAnalyticsDataStore

    override suspend fun read(): PersistedOnboardingAnalyticsState =
        OnboardingAnalyticsStateCodec.decode(dataStore.data.first()[STATE_KEY])

    override suspend fun update(
        transform: (PersistedOnboardingAnalyticsState) -> PersistedOnboardingAnalyticsState,
    ): PersistedOnboardingAnalyticsState {
        var result = PersistedOnboardingAnalyticsState()
        dataStore.edit { preferences ->
            result = transform(OnboardingAnalyticsStateCodec.decode(preferences[STATE_KEY]))
            preferences[STATE_KEY] = OnboardingAnalyticsStateCodec.encode(result)
        }
        return result
    }

    private companion object {
        val STATE_KEY = stringPreferencesKey("state_json")
    }
}

internal object OnboardingAnalyticsStateCodec {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = false
    }

    fun encode(state: PersistedOnboardingAnalyticsState): String =
        json.encodeToString(PersistedOnboardingAnalyticsState.serializer(), state)

    fun decode(value: String?): PersistedOnboardingAnalyticsState {
        if (value == null) return PersistedOnboardingAnalyticsState()
        return runCatching {
            json.decodeFromString(PersistedOnboardingAnalyticsState.serializer(), value)
        }.getOrElse {
            // Corrupt private analytics state is discarded rather than uploaded or logged.
            PersistedOnboardingAnalyticsState()
        }
    }
}

data class OnboardingAnalyticsBatch(
    val installId: String,
    val events: List<OnboardingAnalyticsEvent>,
)

interface OnboardingAnalyticsStore {
    suspend fun getOrCreateInstallId(): String
    suspend fun enqueue(event: OnboardingAnalyticsEvent, milestoneKey: String): Boolean
    suspend fun loadBatch(limit: Int): OnboardingAnalyticsBatch?
    suspend fun remove(eventIds: Set<String>)
    suspend fun hasPendingEvents(): Boolean
}

@Singleton
class DurableOnboardingAnalyticsStore @Inject internal constructor(
    private val persistence: OnboardingAnalyticsStatePersistence,
    private val uuidGenerator: OnboardingAnalyticsUuidGenerator,
) : OnboardingAnalyticsStore {
    override suspend fun getOrCreateInstallId(): String {
        var installId = ""
        persistence.update { current ->
            installId = current.installId?.takeIf(OnboardingAnalyticsPrivacyValidator::isUuid)
                ?: uuidGenerator.randomUuid().also {
                    require(OnboardingAnalyticsPrivacyValidator.isUuid(it))
                }
            current.copy(installId = installId)
        }
        return installId
    }

    override suspend fun enqueue(
        event: OnboardingAnalyticsEvent,
        milestoneKey: String,
    ): Boolean {
        require(OnboardingAnalyticsPrivacyValidator.isValid(event))
        require(milestoneKey in ALLOWED_MILESTONE_KEYS)
        var inserted = false
        persistence.update { current ->
            if (milestoneKey in current.emittedMilestones) {
                current
            } else {
                inserted = true
                val installId = current.installId
                    ?.takeIf(OnboardingAnalyticsPrivacyValidator::isUuid)
                    ?: uuidGenerator.randomUuid().also {
                        require(OnboardingAnalyticsPrivacyValidator.isUuid(it))
                    }
                current.copy(
                    installId = installId,
                    events = (current.events + event).takeLast(MAX_QUEUE_SIZE),
                    emittedMilestones = (current.emittedMilestones + milestoneKey)
                        .takeLast(MAX_MILESTONE_KEYS),
                )
            }
        }
        return inserted
    }

    override suspend fun loadBatch(limit: Int): OnboardingAnalyticsBatch? {
        require(limit in 1..MAX_QUEUE_SIZE)
        var sanitized = PersistedOnboardingAnalyticsState()
        persistence.update { current ->
            sanitized = current.copy(
                events = current.events.filter(OnboardingAnalyticsPrivacyValidator::isValid)
                    .takeLast(MAX_QUEUE_SIZE),
                emittedMilestones = current.emittedMilestones
                    .filter { it in ALLOWED_MILESTONE_KEYS }
                    .distinct()
                    .takeLast(MAX_MILESTONE_KEYS),
            )
            sanitized
        }
        if (sanitized.events.isEmpty()) return null
        val installId = sanitized.installId
            ?.takeIf(OnboardingAnalyticsPrivacyValidator::isUuid)
            ?: getOrCreateInstallId()
        return OnboardingAnalyticsBatch(installId, sanitized.events.take(limit))
    }

    override suspend fun remove(eventIds: Set<String>) {
        if (eventIds.isEmpty()) return
        persistence.update { current ->
            current.copy(events = current.events.filterNot { it.eventId in eventIds })
        }
    }

    override suspend fun hasPendingEvents(): Boolean = persistence.read().events.isNotEmpty()

    companion object {
        const val MAX_QUEUE_SIZE = 50
        const val MAX_MILESTONE_KEYS = 64

        internal fun milestoneKey(
            eventName: PricingOnboardingEventName,
            step: OnboardingAnalyticsStep,
        ): String = "${eventName.wireName}:${step.wireName}"

        private val ALLOWED_MILESTONE_KEYS = buildSet {
            PricingOnboardingEventName.entries.forEach { eventName ->
                OnboardingAnalyticsStep.entries.forEach { step ->
                    add(milestoneKey(eventName, step))
                }
            }
        }

    }
}
