package com.healthmd.rawexport

import com.healthmd.data.health.providers.cloud.CloudHealthApiClient
import com.healthmd.data.health.providers.cloud.CloudNativeRawPageProvider
import com.healthmd.data.health.providers.cloud.CloudRawMetrics
import com.healthmd.data.health.providers.cloud.FitbitCloudDataProvider
import com.healthmd.data.health.providers.cloud.OuraCloudDataProvider
import com.healthmd.data.health.providers.cloud.WhoopCloudDataProvider
import com.healthmd.data.health.providers.cloud.WithingsCloudDataProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** Truthful raw-provider dispatch. Unknown providers never fall back to Health Connect. */
class RawHealthRepositoryRegistry(
    healthConnectRepository: RawHealthRepository,
    apiClient: CloudHealthApiClient? = null,
    cloudProviders: List<CloudNativeRawPageProvider> = emptyList(),
) {
    private val repositories: Map<String, RawHealthRepository> = buildMap {
        put(HEALTH_CONNECT, healthConnectRepository)
        if (apiClient != null) {
            cloudProviders.forEach { source ->
                put(source.rawProviderId, DefaultRawHealthRepository(CloudRawHealthDataProvider(source, apiClient)))
            }
        }
        listOf("polar", "samsung_health", "huawei_health", "garmin").forEach { providerId ->
            put(providerId, UnsupportedRawHealthRepository(providerId))
        }
    }

    fun repositoryFor(providerId: String): RawHealthRepository? = repositories[providerId]
    fun registeredProviderIds(): Set<String> = repositories.keys.toSortedSet()

    companion object {
        const val HEALTH_CONNECT = "health_connect"

        fun healthConnectOnly(repository: RawHealthRepository): RawHealthRepositoryRegistry =
            RawHealthRepositoryRegistry(repository)

        fun create(
            healthConnectRepository: RawHealthRepository,
            apiClient: CloudHealthApiClient,
            fitbit: FitbitCloudDataProvider,
            withings: WithingsCloudDataProvider,
            oura: OuraCloudDataProvider,
            whoop: WhoopCloudDataProvider,
        ) = RawHealthRepositoryRegistry(
            healthConnectRepository,
            apiClient,
            listOf(fitbit, withings, oura, whoop),
        )
    }
}

/** Emits an explicit manifest/report rather than inventing payloads from normalized data. */
class UnsupportedRawHealthRepository(
    private val providerId: String,
) : RawHealthRepository {
    private val definitions = listOf(
        "activity", "sleep", "heart", "body", "workouts", "respiratory", "vitals",
        "nutrition", "mobility", "reproductive", "other",
    ).map { category ->
        RawProviderTypeDefinition(
            typeKey = "unsupported/$category",
            wireType = "provider_payload",
            providerId = providerId,
            rangeBehavior = RawRangeBehavior.OVERLAP,
            metricIds = when (category) {
                "activity" -> CloudRawMetrics.activity
                "sleep" -> CloudRawMetrics.sleep
                "heart" -> CloudRawMetrics.heart
                "body" -> CloudRawMetrics.body
                "workouts" -> CloudRawMetrics.workouts
                "respiratory" -> CloudRawMetrics.respiratory
                "vitals" -> CloudRawMetrics.vitals
                "nutrition" -> CloudRawMetrics.nutrition
                "mobility" -> CloudRawMetrics.mobility
                "reproductive" -> CloudRawMetrics.reproductive
                else -> CloudRawMetrics.otherKnown
            },
        )
    }

    override suspend fun capabilities() = RawProviderCapabilities(
        sdkVersion = "no-native-adapter",
        available = false,
        providerId = providerId,
        fidelityLevel = RawProviderFidelity.UNSUPPORTED,
    )

    override fun typeDefinitions(): List<RawProviderTypeDefinition> = definitions

    override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = flow {
        emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
        definitions.forEach { definition ->
            val selected = request.scope == RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA ||
                definition.metricIds.any(request.selectedMetricIds::contains)
            if (!selected) {
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.NOT_SELECTED)))
            } else {
                val message = "$providerId has no provider-native raw adapter."
                emit(RawExportItem.Issue(RawIssue("unsupported_by_provider", message, RawIssueSeverity.ERROR, definition.typeKey)))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.UNSUPPORTED_BY_PROVIDER, message)))
            }
        }
        emit(RawExportItem.Status(RawSnapshotStatus.FAILED))
    }

    private fun RawProviderTypeDefinition.report(status: RawTypeStatus, message: String? = null) = RawTypeReport(
        typeKey = typeKey,
        wireType = wireType,
        providerId = providerId,
        status = status,
        rangeBehavior = rangeBehavior,
        message = message,
    )

}
