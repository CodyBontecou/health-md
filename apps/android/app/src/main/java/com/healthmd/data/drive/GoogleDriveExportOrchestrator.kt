package com.healthmd.data.drive

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.HealthRepository
import java.time.LocalDate
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/** Separate local selection keeps Google authority out of settings snapshots and Shared Setup. */
@Singleton
class GoogleDriveSelectionStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    private val key = stringPreferencesKey("active_google_drive_destination_id")
    val destinationId = dataStore.data.map { it[key] }
    suspend fun get(): String? = destinationId.first()
    suspend fun select(id: String?) {
        dataStore.edit { prefs -> if (id == null) prefs.remove(key) else prefs[key] = id }
    }
}

@Singleton
class GoogleDriveExportOrchestrator @Inject constructor(
    private val healthRepository: HealthRepository,
    private val bundleFactory: GeneratedExportBundleFactory,
    private val runner: GoogleDriveDestinationRunner,
) {
    suspend fun exportDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        destinationId: String,
        profileId: String? = null,
        source: String = "manual",
        operationId: String = UUID.randomUUID().toString(),
        settingsSnapshotJson: String? = null,
        onProgress: ((Int, Int, String) -> Unit)? = null,
    ): ExportResult {
        val normalized = dates.distinct().sorted()
        if (normalized.isEmpty()) return ExportResult(0, 0, target = ExportTarget.GOOGLE_DRIVE)
        val captured = mutableListOf<HealthData>()
        val failures = mutableListOf<FailedDateDetail>()
        val selection = settings.effectiveDataTypeSelection()
        normalized.forEachIndexed { index, date ->
            onProgress?.invoke(index + 1, normalized.size, date.toString())
            if (healthRepository.isBeforeFirstUnlock()) {
                failures += FailedDateDetail(date, ExportFailureReason.DEVICE_LOCKED)
                return@forEachIndexed
            }
            val data = try {
                healthRepository.fetchHealthDataRange(
                    listOf(date),
                    selection,
                    settings.shouldFetchGranularData(),
                ).firstOrNull() ?: healthRepository.fetchHealthData(date)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: SecurityException) {
                failures += FailedDateDetail(date, ExportFailureReason.ACCESS_DENIED)
                return@forEachIndexed
            } catch (_: Exception) {
                failures += FailedDateDetail(date, ExportFailureReason.HEALTH_CONNECT_ERROR)
                return@forEachIndexed
            }.filtered(selection).filtered(settings.metricSelection)
            if (!data.hasAnyData) {
                failures += FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA)
            } else {
                captured += data
            }
        }
        if (captured.isEmpty()) {
            return ExportResult(0, normalized.size, failures, target = ExportTarget.GOOGLE_DRIVE)
        }
        val bundle = try {
            bundleFactory.daily(
                operationId = operationId,
                profileId = profileId,
                source = source,
                data = captured,
                settings = settings.copy(exportTarget = ExportTarget.GOOGLE_DRIVE),
                settingsSnapshotJson = settingsSnapshotJson ?: kotlinx.serialization.json.Json.encodeToString(
                    ExportSettings.serializer(),
                    settings,
                ),
            )
        } catch (_: Exception) {
            return ExportResult(
                0,
                normalized.size,
                normalized.map { FailedDateDetail(it, ExportFailureReason.FILE_WRITE_ERROR) },
                target = ExportTarget.GOOGLE_DRIVE,
            )
        }
        return when (val result = runner.run(bundle, destinationId)) {
            is GoogleDriveRunResult.Complete -> ExportResult(
                successCount = captured.size,
                totalCount = normalized.size,
                failedDateDetails = failures,
                target = ExportTarget.GOOGLE_DRIVE,
                artifactCount = result.artifactCount,
            )
            is GoogleDriveRunResult.Stopped -> ExportResult(
                successCount = if (result.completedArtifactCount > 0) captured.size.coerceAtMost(normalized.size - failures.size) else 0,
                totalCount = normalized.size,
                failedDateDetails = failures + normalized.filterNot { date -> failures.any { it.date == date } }.map {
                    FailedDateDetail(it, result.error.toFailureReason(), result.error.serialId)
                },
                target = ExportTarget.GOOGLE_DRIVE,
                artifactCount = result.completedArtifactCount,
                retryDriveOperationIds = normalized.associateWith { operationId },
            )
        }
    }
}

internal val GoogleDriveErrorId.serialId: String
    get() = name.lowercase()

internal fun GoogleDriveErrorId.toFailureReason(): ExportFailureReason = when (this) {
    GoogleDriveErrorId.CONFIGURATION_MISSING -> ExportFailureReason.UNKNOWN
    GoogleDriveErrorId.REAUTHORIZATION_REQUIRED,
    GoogleDriveErrorId.ACCOUNT_MISMATCH,
    GoogleDriveErrorId.PERMISSION_DENIED -> ExportFailureReason.ACCESS_DENIED
    GoogleDriveErrorId.FOLDER_UNAVAILABLE,
    GoogleDriveErrorId.REMOTE_CONFLICT,
    GoogleDriveErrorId.AMBIGUOUS_COMMIT,
    GoogleDriveErrorId.CHECKSUM_MISMATCH,
    GoogleDriveErrorId.PARTIAL_COMPLETION -> ExportFailureReason.FILE_WRITE_ERROR
    GoogleDriveErrorId.QUOTA_EXCEEDED,
    GoogleDriveErrorId.RATE_LIMITED -> ExportFailureReason.RATE_LIMITED
}
