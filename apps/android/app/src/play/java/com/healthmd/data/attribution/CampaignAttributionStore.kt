package com.healthmd.data.attribution

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

private val Context.campaignAttributionDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "campaign_attribution"
)

interface CampaignAttributionStore {
    suspend fun load(): CampaignAttributionSnapshot
    suspend fun getOrCreateInstallId(): String
    suspend fun persistPendingIfDiscoveryPending(event: CampaignInstallEvent): CampaignInstallEvent?
    suspend fun markDiscoveryTerminal()
    suspend fun markDelivered(eventId: String)
    suspend fun markPermanentlyRejected(eventId: String)
}

@Serializable
private data class PersistedCampaignAttribution(
    val installId: String? = null,
    val processingState: CampaignAttributionProcessingState =
        CampaignAttributionProcessingState.DISCOVERY_PENDING,
    val event: CampaignInstallEvent? = null,
    val deliverySucceeded: Boolean = false,
)

@Singleton
class DataStoreCampaignAttributionStore @Inject constructor(
    @ApplicationContext context: Context,
    private val uuidGenerator: CampaignAttributionUuidGenerator,
) : CampaignAttributionStore {
    private val dataStore = context.campaignAttributionDataStore

    override suspend fun load(): CampaignAttributionSnapshot =
        decode(dataStore.data.first()[STATE_KEY]).toSnapshot()

    override suspend fun getOrCreateInstallId(): String {
        var installId: String? = null
        dataStore.edit { preferences ->
            val current = decode(preferences[STATE_KEY])
            installId = current.installId?.takeIf { it.isNotBlank() } ?: uuidGenerator.randomUuid()
            preferences[STATE_KEY] = encode(current.copy(installId = installId))
        }
        return requireNotNull(installId)
    }

    override suspend fun persistPendingIfDiscoveryPending(
        event: CampaignInstallEvent,
    ): CampaignInstallEvent? {
        var persistedEvent: CampaignInstallEvent? = null
        dataStore.edit { preferences ->
            val current = decode(preferences[STATE_KEY])
            val updated = when (current.processingState) {
                CampaignAttributionProcessingState.DISCOVERY_PENDING -> current.copy(
                    installId = current.installId ?: event.installId,
                    processingState = CampaignAttributionProcessingState.PENDING_DELIVERY,
                    event = event,
                    deliverySucceeded = false,
                )

                CampaignAttributionProcessingState.PENDING_DELIVERY -> current
                else -> current
            }
            persistedEvent = updated.event
            preferences[STATE_KEY] = encode(updated)
        }
        return persistedEvent
    }

    override suspend fun markDiscoveryTerminal() {
        dataStore.edit { preferences ->
            val current = decode(preferences[STATE_KEY])
            if (current.processingState == CampaignAttributionProcessingState.DISCOVERY_PENDING) {
                preferences[STATE_KEY] = encode(
                    current.copy(
                        processingState = CampaignAttributionProcessingState.TERMINAL_NO_CAMPAIGN,
                        event = null,
                        deliverySucceeded = false,
                    )
                )
            }
        }
    }

    override suspend fun markDelivered(eventId: String) {
        updateMatchingPendingEvent(eventId) { current ->
            current.copy(
                processingState = CampaignAttributionProcessingState.DELIVERED,
                deliverySucceeded = true,
            )
        }
    }

    override suspend fun markPermanentlyRejected(eventId: String) {
        updateMatchingPendingEvent(eventId) { current ->
            current.copy(
                processingState = CampaignAttributionProcessingState.TERMINAL_REJECTED,
                deliverySucceeded = false,
            )
        }
    }

    private suspend fun updateMatchingPendingEvent(
        eventId: String,
        update: (PersistedCampaignAttribution) -> PersistedCampaignAttribution,
    ) {
        dataStore.edit { preferences ->
            val current = decode(preferences[STATE_KEY])
            if (current.processingState == CampaignAttributionProcessingState.PENDING_DELIVERY &&
                current.event?.eventId == eventId
            ) {
                preferences[STATE_KEY] = encode(update(current))
            }
        }
    }

    private fun decode(value: String?): PersistedCampaignAttribution {
        if (value == null) return PersistedCampaignAttribution()
        return runCatching {
            STORE_JSON.decodeFromString(PersistedCampaignAttribution.serializer(), value)
        }.getOrElse {
            // Fail closed: corrupted private state must not cause a second attribution event.
            PersistedCampaignAttribution(
                processingState = CampaignAttributionProcessingState.TERMINAL_REJECTED,
                deliverySucceeded = false,
            )
        }
    }

    private fun encode(value: PersistedCampaignAttribution): String =
        STORE_JSON.encodeToString(PersistedCampaignAttribution.serializer(), value)

    private fun PersistedCampaignAttribution.toSnapshot() = CampaignAttributionSnapshot(
        installId = installId,
        processingState = processingState,
        event = event,
        deliverySucceeded = deliverySucceeded,
    )

    private companion object {
        val STATE_KEY = stringPreferencesKey("state_json")
        val STORE_JSON = Json {
            encodeDefaults = true
            explicitNulls = false
            ignoreUnknownKeys = false
        }
    }
}
