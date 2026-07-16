package com.healthmd.rawexport

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_HISTORY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_ALLERGIES_INTOLERANCES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_CONDITIONS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_LABORATORY_RESULTS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_MEDICATIONS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PERSONAL_DETAILS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PRACTITIONER_DETAILS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PREGNANCY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PROCEDURES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_SOCIAL_HISTORY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VACCINES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VISITS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VITAL_SIGNS
import androidx.health.connect.client.records.MedicalDataSource
import androidx.health.connect.client.records.MedicalResource
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.request.GetMedicalDataSourcesRequest
import androidx.health.connect.client.request.ReadMedicalResourcesInitialRequest
import androidx.health.connect.client.request.ReadMedicalResourcesPageRequest
import androidx.health.connect.client.request.ReadMedicalResourcesRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

@OptIn(ExperimentalPersonalHealthRecordApi::class)
class HealthConnectRawDataProvider(
    private val context: Context,
    private val client: HealthConnectClient = HealthConnectClient.getOrCreate(context),
    private val catalog: List<HealthConnectRecordDescriptor<out Record>> = HealthConnectRecordCatalog.records,
    private val now: () -> Instant = Instant::now,
) : RawHealthDataProvider {

    override suspend fun capabilities(): RawProviderCapabilities {
        val available = HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE
        if (!available) return RawProviderCapabilities(available = false)
        val granted = try {
            client.permissionController.getGrantedPermissions()
        } catch (_: Exception) {
            emptySet()
        }
        val features = FEATURE_NAMES.mapNotNull { (id, name) ->
            if (featureAvailable(id)) name else null
        }.toSet()
        return RawProviderCapabilities(
            available = true,
            grantedPermissions = granted,
            availableFeatures = features,
            historicalReadGranted = PERMISSION_READ_HEALTH_DATA_HISTORY in granted,
        )
    }

    override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = flow {
        emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
        val capabilities = capabilities()
        if (!capabilities.available) {
            emit(issue("health_connect_unavailable", "Health Connect is unavailable.", RawIssueSeverity.ERROR))
            emit(RawExportItem.Status(RawSnapshotStatus.FAILED))
            return@flow
        }

        var partial = false
        if (!capabilities.historicalReadGranted && request.startTime.toInstant().isBefore(now().minusSeconds(HISTORY_WINDOW_SECONDS))) {
            partial = true
            emit(issue("history_permission_missing", "Records older than Health Connect's default history window may be unavailable."))
        }

        val selected = when (request.scope) {
            RawSnapshotScope.SELECTED_RECORD_TYPES -> {
                val knownMetrics = catalog.flatMap { it.metricIds }.toSet() + MEDICAL_METRIC_ID
                (request.selectedMetricIds - knownMetrics).sorted().forEach { metric ->
                    partial = true
                    emit(issue("selection_unknown", "No raw native record type is registered for metric '$metric'."))
                }
                catalog.filter { it.metricIds.any(request.selectedMetricIds::contains) }
            }
            RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA -> catalog
        }

        for (descriptor in selected) {
            val granted = descriptor.readPermission in capabilities.grantedPermissions
            val featureReady = descriptor.featureGate?.let { featureAvailable(it.feature) } ?: true
            if (!granted || !featureReady) {
                if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) {
                    partial = true
                    emit(
                        issue(
                            if (!granted) "permission_missing" else "feature_unavailable",
                            if (!granted) "Read permission is not granted." else "Required Health Connect feature is unavailable.",
                            recordType = descriptor.wireType,
                        ),
                    )
                }
                continue
            }
            if (descriptor.mapper == null) {
                partial = true
                emit(issue("mapper_missing", "No explicit pinned-SDK mapper exists.", RawIssueSeverity.ERROR, descriptor.wireType))
                continue
            }
            try {
                readDescriptor(descriptor, request) { record -> emit(RawExportItem.Record(record)) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (security: SecurityException) {
                partial = true
                emit(issue("permission_revoked", security.safeMessage("Permission was revoked while reading."), RawIssueSeverity.ERROR, descriptor.wireType))
            } catch (error: Exception) {
                partial = true
                emit(issue("read_failed", error.safeMessage("Health Connect read failed."), RawIssueSeverity.ERROR, descriptor.wireType, retryable = true))
            }
        }

        val medicalRequested = request.scope == RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA || MEDICAL_METRIC_ID in request.selectedMetricIds
        if (medicalRequested) {
            val grantedTypes = MEDICAL_TYPES.filter { it.permission in capabilities.grantedPermissions }
            val phrAvailable = featureAvailable(HealthConnectFeatures.FEATURE_PERSONAL_HEALTH_RECORD)
            if (!phrAvailable || grantedTypes.isEmpty()) {
                if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) {
                    partial = true
                    emit(issue(if (!phrAvailable) "feature_unavailable" else "permission_missing", "Personal Health Record data is not available.", recordType = "medical_resource"))
                }
            } else {
                try {
                    readMedical(grantedTypes.map { it.type }, request.pageSize) { emit(RawExportItem.Record(it)) }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    partial = true
                    emit(issue("medical_read_failed", error.safeMessage("Medical resource read failed."), RawIssueSeverity.ERROR, "medical_resource", retryable = true))
                }
            }
        }

        emit(RawExportItem.Status(if (partial) RawSnapshotStatus.PARTIAL else RawSnapshotStatus.COMPLETE))
    }

    @Suppress("UNCHECKED_CAST")
    private suspend fun readDescriptor(
        descriptor: HealthConnectRecordDescriptor<out Record>,
        request: RawSnapshotRequest,
        emitRecord: suspend (RawRecord) -> Unit,
    ) = readTypedDescriptor(descriptor as HealthConnectRecordDescriptor<Record>, request, emitRecord)

    private suspend fun <T : Record> readTypedDescriptor(
        descriptor: HealthConnectRecordDescriptor<T>,
        request: RawSnapshotRequest,
        emitRecord: suspend (RawRecord) -> Unit,
    ) {
        var token: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = descriptor.recordClass,
                    timeRangeFilter = TimeRangeFilter.between(request.startTime.toInstant(), request.endTime.toInstant()),
                    ascendingOrder = true,
                    pageSize = request.pageSize,
                    pageToken = token,
                ),
            )
            for (native in response.records) {
                val mapped = descriptor.mapper?.invoke(native)
                    ?: error("mapper_missing:${descriptor.wireType}")
                val privacyFiltered = if (!request.includeExerciseRoutes && descriptor.wireType == "exercise_session") {
                    mapped.copy(fields = kotlinx.serialization.json.JsonObject(mapped.fields - "route"), hash = "")
                        .withCanonicalIdentityAndHash()
                } else {
                    mapped
                }
                emitRecord(privacyFiltered)
            }
            token = response.pageToken
        } while (!token.isNullOrBlank())
    }

    private suspend fun readMedical(
        types: List<Int>,
        pageSize: Int,
        emitRecord: suspend (RawRecord) -> Unit,
    ) {
        val sources: Map<String, MedicalDataSource> =
            client.getMedicalDataSources(GetMedicalDataSourcesRequest(emptyList())).associateBy { it.id }
        for (type in types.sorted()) {
            var request: ReadMedicalResourcesRequest = ReadMedicalResourcesInitialRequest(type, emptySet(), pageSize)
            while (true) {
                val response = client.readMedicalResources(request)
                response.medicalResources.forEach { resource ->
                    val source = requireNotNull(sources[resource.dataSourceId]) {
                        "Medical data source '${resource.dataSourceId}' was not returned."
                    }
                    emitRecord(RawMedicalResourceMapper.map(resource, source))
                }
                val token = response.nextPageToken
                if (token.isNullOrBlank()) break
                request = ReadMedicalResourcesPageRequest(token, pageSize)
            }
        }
    }

    private fun featureAvailable(feature: Int): Boolean = try {
        client.features.getFeatureStatus(feature) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
    } catch (_: Exception) {
        false
    }

    private fun issue(
        code: String,
        message: String,
        severity: RawIssueSeverity = RawIssueSeverity.WARNING,
        recordType: String? = null,
        retryable: Boolean = false,
    ) = RawExportItem.Issue(RawIssue(code, message, severity, recordType, retryable))

    private fun Throwable.safeMessage(fallback: String): String =
        message?.take(240)?.takeIf { it.isNotBlank() } ?: fallback

    private fun RawInstant.toInstant(): Instant = Instant.ofEpochSecond(epochSecond, nano.toLong())

    private data class MedicalType(val type: Int, val permission: String)

    companion object {
        private const val HISTORY_WINDOW_SECONDS = 30L * 24 * 60 * 60
        private const val MEDICAL_METRIC_ID = "medical_resources"
        private val FEATURE_NAMES = mapOf(
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND to "background_read",
            HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE to "skin_temperature",
            HealthConnectFeatures.FEATURE_PLANNED_EXERCISE to "planned_exercise",
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY to "history_read",
            HealthConnectFeatures.FEATURE_PERSONAL_HEALTH_RECORD to "personal_health_record",
            HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION to "mindfulness_session",
            HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY to "activity_intensity",
            HealthConnectFeatures.FEATURE_EXTENDED_DEVICE_TYPES to "extended_device_types",
        )
        private val MEDICAL_TYPES = listOf(
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_ALLERGIES_INTOLERANCES, PERMISSION_READ_MEDICAL_DATA_ALLERGIES_INTOLERANCES),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_CONDITIONS, PERMISSION_READ_MEDICAL_DATA_CONDITIONS),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_LABORATORY_RESULTS, PERMISSION_READ_MEDICAL_DATA_LABORATORY_RESULTS),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_MEDICATIONS, PERMISSION_READ_MEDICAL_DATA_MEDICATIONS),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_PERSONAL_DETAILS, PERMISSION_READ_MEDICAL_DATA_PERSONAL_DETAILS),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_PRACTITIONER_DETAILS, PERMISSION_READ_MEDICAL_DATA_PRACTITIONER_DETAILS),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_PREGNANCY, PERMISSION_READ_MEDICAL_DATA_PREGNANCY),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_PROCEDURES, PERMISSION_READ_MEDICAL_DATA_PROCEDURES),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_SOCIAL_HISTORY, PERMISSION_READ_MEDICAL_DATA_SOCIAL_HISTORY),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_VACCINES, PERMISSION_READ_MEDICAL_DATA_VACCINES),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_VISITS, PERMISSION_READ_MEDICAL_DATA_VISITS),
            MedicalType(MedicalResource.MEDICAL_RESOURCE_TYPE_VITAL_SIGNS, PERMISSION_READ_MEDICAL_DATA_VITAL_SIGNS),
        )
    }
}
