package com.healthmd.rawexport

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_HISTORY
import androidx.health.connect.client.records.MedicalDataSource
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.request.GetMedicalDataSourcesRequest
import androidx.health.connect.client.request.ReadMedicalResourcesInitialRequest
import androidx.health.connect.client.request.ReadMedicalResourcesPageRequest
import androidx.health.connect.client.request.ReadMedicalResourcesRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

fun interface HistoryAccessBoundary {
    suspend fun firstPermissionGrantDate(): LocalDate?
}

@OptIn(ExperimentalPersonalHealthRecordApi::class)
class HealthConnectRawDataProvider(
    private val context: Context,
    private val client: HealthConnectClient = HealthConnectClient.getOrCreate(context),
    private val catalog: List<HealthConnectRecordDescriptor<out Record>> = HealthConnectRecordCatalog.records,
    private val historyAccessBoundary: HistoryAccessBoundary = HistoryAccessBoundary { null },
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
        }.toSortedSet()
        return RawProviderCapabilities(
            available = true,
            grantedPermissions = granted.toSortedSet(),
            availableFeatures = features,
            historicalReadGranted = PERMISSION_READ_HEALTH_DATA_HISTORY in granted,
        )
    }

    override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = flow {
        emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
        val capabilities = capabilities()
        val selectedKeys = selectedTypeKeys(request)
        if (!capabilities.available) {
            for (definition in RawExportTypeCatalog.definitions) {
                if (definition.typeKey !in selectedKeys) {
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.NOT_SELECTED)))
                } else {
                    emit(issue("unsupported_by_provider", "Health Connect is unavailable.", RawIssueSeverity.ERROR, definition.typeKey))
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.UNSUPPORTED_BY_PROVIDER, issueCount = 1, message = "Health Connect is unavailable.")))
                }
            }
            emit(RawExportItem.Status(RawSnapshotStatus.FAILED))
            return@flow
        }

        var partial = false
        val knownMetrics = RawExportTypeCatalog.definitions.flatMap { it.metricIds }.toSet()
        (request.selectedMetricIds - knownMetrics).sorted().forEach { metric ->
            if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) {
                partial = true
                emit(issue("selection_unknown", "No raw native record type is registered for metric '$metric'."))
            }
        }
        val firstGrantDate = historyAccessBoundary.firstPermissionGrantDate()
        val historyMissing = !capabilities.historicalReadGranted &&
            requiresHistoricalReadPermission(request, firstGrantDate)

        for (descriptor in catalog) {
            val definition = RawExportTypeCatalog.byKey.getValue(descriptor.wireType)
            if (definition.typeKey !in selectedKeys) {
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.NOT_SELECTED)))
                continue
            }
            if (descriptor.mapper == null) {
                val message = "The provider has no explicit pinned-SDK mapper for this type."
                emit(issue("unsupported_by_provider", message, RawIssueSeverity.ERROR, definition.typeKey))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.UNSUPPORTED_BY_PROVIDER, issueCount = 1, message = message)))
                if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) partial = true
                continue
            }
            val featureReady = descriptor.featureGate?.let { featureAvailable(it.feature) } ?: true
            if (!featureReady) {
                val message = "The required Health Connect feature is unavailable."
                emit(issue("feature_unavailable", message, recordType = definition.typeKey))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.FEATURE_UNAVAILABLE, issueCount = 1, message = message)))
                if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) partial = true
                continue
            }
            if (descriptor.readPermission !in capabilities.grantedPermissions) {
                val message = "Read permission is not granted."
                emit(issue("permission_not_granted", message, recordType = definition.typeKey))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.PERMISSION_NOT_GRANTED, issueCount = 1, message = message)))
                if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) partial = true
                continue
            }

            try {
                val count = readDescriptor(descriptor, request) { record -> emit(RawExportItem.Record(record)) }
                if (historyMissing) {
                    val message = "The requested range predates the ordinary Health Connect history window."
                    emit(issue("history_permission_missing", message, recordType = definition.typeKey))
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.HISTORY_PERMISSION_MISSING, count, 1, message)))
                    partial = true
                } else {
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.EXPORTED, count)))
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: SecurityException) {
                val message = "Permission was revoked while reading."
                emit(issue("permission_revoked", message, RawIssueSeverity.ERROR, definition.typeKey))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.READ_ERROR, issueCount = 1, message = message)))
                partial = true
            } catch (_: Exception) {
                val message = "Health Connect read failed."
                emit(issue("read_error", message, RawIssueSeverity.ERROR, definition.typeKey, retryable = true))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.READ_ERROR, issueCount = 1, message = message)))
                partial = true
            }
        }

        val phrFeatureAvailable = featureAvailable(HealthConnectFeatures.FEATURE_PERSONAL_HEALTH_RECORD)
        val sources = if (RawExportTypeCatalog.medicalTypes.any { it.typeKey in selectedKeys } && phrFeatureAvailable) {
            try {
                client.getMedicalDataSources(GetMedicalDataSourcesRequest(emptyList())).associateBy { it.id }
            } catch (_: Exception) {
                emptyMap()
            }
        } else {
            emptyMap()
        }
        for (medical in RawExportTypeCatalog.medicalTypes) {
            val definition = RawExportTypeCatalog.byKey.getValue(medical.typeKey)
            if (medical.typeKey !in selectedKeys) {
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.NOT_SELECTED)))
                continue
            }
            if (!phrFeatureAvailable) {
                val message = "The Personal Health Record feature is unavailable."
                emit(issue("feature_unavailable", message, recordType = medical.typeKey))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.FEATURE_UNAVAILABLE, issueCount = 1, message = message)))
                if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) partial = true
                continue
            }
            if (medical.permission !in capabilities.grantedPermissions) {
                val message = "Read permission is not granted."
                emit(issue("permission_not_granted", message, recordType = medical.typeKey))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.PERMISSION_NOT_GRANTED, issueCount = 1, message = message)))
                if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) partial = true
                continue
            }
            try {
                var missingSources = 0L
                val count = readMedicalCategory(medical.type, request.pageSize, sources) { resource, source ->
                    if (source == null) {
                        missingSources++
                        emit(issue("medical_source_missing", "A matching medical data source was not returned.", RawIssueSeverity.WARNING, medical.typeKey))
                    }
                    emit(RawExportItem.Record(RawMedicalResourceMapper.map(resource, source)))
                }
                if (missingSources > 0) {
                    val message = "One or more resources were exported without matching source metadata."
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.READ_ERROR, count, missingSources, message)))
                    partial = true
                } else {
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.EXPORTED, count)))
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                val message = "Medical resource read failed."
                emit(issue("read_error", message, RawIssueSeverity.ERROR, medical.typeKey, retryable = true))
                emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.READ_ERROR, issueCount = 1, message = message)))
                partial = true
            }
        }

        emit(RawExportItem.Status(if (partial) RawSnapshotStatus.PARTIAL else RawSnapshotStatus.COMPLETE))
    }

    private fun selectedTypeKeys(request: RawSnapshotRequest): Set<String> =
        RawExportTypeCatalog.definitions.filter { RawExportTypeCatalog.isSelected(it, request) }.mapTo(linkedSetOf()) { it.typeKey }

    private fun RawTypeDefinition.report(
        status: RawTypeStatus,
        recordCount: Long = 0,
        issueCount: Long = 0,
        message: String? = null,
    ) = RawTypeReport(
        typeKey = typeKey,
        wireType = wireType,
        providerId = providerId,
        status = status,
        recordCount = recordCount,
        issueCount = issueCount,
        permission = permission,
        feature = feature,
        rangeBehavior = rangeBehavior,
        pagination = pagination,
        serverAggregation = serverAggregation,
        message = message,
    )

    @Suppress("UNCHECKED_CAST")
    private suspend fun readDescriptor(
        descriptor: HealthConnectRecordDescriptor<out Record>,
        request: RawSnapshotRequest,
        emitRecord: suspend (RawRecord) -> Unit,
    ): Long = readTypedDescriptor(descriptor as HealthConnectRecordDescriptor<Record>, request, emitRecord)

    private suspend fun <T : Record> readTypedDescriptor(
        descriptor: HealthConnectRecordDescriptor<T>,
        request: RawSnapshotRequest,
        emitRecord: suspend (RawRecord) -> Unit,
    ): Long {
        var token: String? = null
        var count = 0L
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
            // The provider query is permitted to be broader. Enforce v1 half-open semantics page by page.
            for (native in response.records) {
                val mapped = descriptor.mapper?.invoke(native) ?: error("mapper_missing:${descriptor.wireType}")
                if (!mapped.isInHalfOpenRange(request, descriptor.rangeBehavior)) continue
                val privacyFiltered = if (!request.includeExerciseRoutes && descriptor.wireType == "exercise_session") {
                    mapped.copy(fields = kotlinx.serialization.json.JsonObject(mapped.fields - "route"), hash = "")
                        .withCanonicalIdentityAndHash()
                } else {
                    mapped
                }
                emitRecord(privacyFiltered)
                count++
            }
            token = response.pageToken
        } while (!token.isNullOrBlank())
        return count
    }

    private suspend fun readMedicalCategory(
        type: Int,
        pageSize: Int,
        sources: Map<String, MedicalDataSource>,
        emitResource: suspend (androidx.health.connect.client.records.MedicalResource, MedicalDataSource?) -> Unit,
    ): Long {
        var count = 0L
        var request: ReadMedicalResourcesRequest = ReadMedicalResourcesInitialRequest(type, emptySet(), pageSize)
        while (true) {
            val response = client.readMedicalResources(request)
            for (resource in response.medicalResources) {
                emitResource(resource, sources[resource.dataSourceId])
                count++
            }
            val token = response.nextPageToken
            if (token.isNullOrBlank()) break
            request = ReadMedicalResourcesPageRequest(token, pageSize)
        }
        return count
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

    private fun RawInstant.toInstant(): Instant = Instant.ofEpochSecond(epochSecond, nano.toLong())

    companion object {
        private val FEATURE_NAMES = mapOf(
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND to "background_read",
            HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE to "skin_temperature",
            HealthConnectFeatures.FEATURE_PLANNED_EXERCISE to "planned_exercise",
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY to "history_read",
            HealthConnectFeatures.FEATURE_PERSONAL_HEALTH_RECORD to RawExportTypeCatalog.PHR_FEATURE_NAME,
            HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION to "mindfulness_session",
            HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY to "activity_intensity",
            HealthConnectFeatures.FEATURE_EXTENDED_DEVICE_TYPES to "extended_device_types",
        )
    }
}

internal fun requiresHistoricalReadPermission(
    request: RawSnapshotRequest,
    firstPermissionGrantDate: LocalDate?,
): Boolean {
    // If legacy state has no recorded grant boundary, do not claim complete history coverage.
    val grantDate = firstPermissionGrantDate ?: return true
    val zone = request.calendarZoneId?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: ZoneId.of("UTC")
    val requestedStartDate = Instant.ofEpochSecond(request.startTime.epochSecond, request.startTime.nano.toLong())
        .atZone(zone)
        .toLocalDate()
    // A date-only persisted grant cannot prove access to the boundary day's hours, so equality is
    // conservatively treated as requiring READ_HEALTH_DATA_HISTORY.
    return !requestedStartDate.isAfter(grantDate.minusDays(30))
}

internal fun RawRecord.isInHalfOpenRange(request: RawSnapshotRequest, behavior: RawRangeBehavior): Boolean = when (behavior) {
    RawRangeBehavior.UNBOUNDED_NON_TEMPORAL -> true
    RawRangeBehavior.INSTANT -> {
        val time = requireNotNull(startTime) { "Instant record has no startTime" }
        require(endTime == null) { "Instant record unexpectedly has endTime" }
        time >= request.startTime && time < request.endTime
    }
    RawRangeBehavior.OVERLAP -> {
        val start = requireNotNull(startTime) { "Interval record has no startTime" }
        val end = requireNotNull(endTime) { "Interval record has no endTime" }
        start < request.endTime && end > request.startTime
    }
}

private operator fun RawInstant.compareTo(other: RawInstant): Int =
    compareValuesBy(this, other, RawInstant::epochSecond, RawInstant::nano)
