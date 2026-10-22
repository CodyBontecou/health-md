package com.healthmd.data.drive

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.healthmd.data.settings.ConfigurationProtectionPersistence
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
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

    /** A delayed OAuth result never changes active selection after protection is enabled. */
    suspend fun selectIfAllowed(id: String?): Boolean {
        var selected = false
        dataStore.edit { prefs ->
            if (prefs[ConfigurationProtectionPersistence.enabledKey] == true) return@edit
            if (id == null) prefs.remove(key) else prefs[key] = id
            selected = true
        }
        return selected
    }

    internal fun clearForDisconnect(prefs: MutablePreferences, destinationId: String) {
        if (prefs[key] == destinationId) prefs.remove(key)
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
        val frozenSettingsSnapshotJson = settingsSnapshotJson ?: kotlinx.serialization.json.Json.encodeToString(
            ExportSettings.serializer(),
            settings,
        )
        when (val loaded = runner.recoveryJournal(operationId)) {
            GoogleDriveJournalLoad.Corrupt -> return failed(normalized, GoogleDriveErrorId.AMBIGUOUS_COMMIT, operationId)
            GoogleDriveJournalLoad.Missing -> Unit
            is GoogleDriveJournalLoad.Found -> {
                val journal = loaded.journal
                val evidence = journal.captureEvidence
                if (evidence?.isValid() != true || journal.ownerDates != evidence.capturedOwnerDates ||
                    journal.destinationId != destinationId ||
                    journal.settingsSnapshotSha256 != sha256Hex(frozenSettingsSnapshotJson.encodeToByteArray()) ||
                    normalized.any { it.toString() !in evidence.requestedOwnerDates }
                ) return failed(normalized, GoogleDriveErrorId.REMOTE_CONFLICT, operationId)
                val resumed = runner.resumeIfPresent(
                    operationId = operationId,
                    expectedDestinationId = destinationId,
                    expectedOwnerDates = journal.ownerDates.map(LocalDate::parse),
                    expectedSettingsSnapshotSha256 = journal.settingsSnapshotSha256,
                ) ?: return failed(normalized, GoogleDriveErrorId.AMBIGUOUS_COMMIT, operationId)
                // A retry narrowed entirely to known capture failures is a new capture operation,
                // never an alias for the prior upload. Its deterministic ID survives another crash.
                if (resumed is GoogleDriveRunResult.Complete &&
                    normalized.all { date -> evidence.failedDates.any { it.date == date } }
                ) {
                    return exportDates(
                        normalized, settings, destinationId, profileId, source,
                        residualOperationId(operationId, normalized), frozenSettingsSnapshotJson, onProgress,
                    )
                }
                return resumed.toExportResult(normalized, operationId, evidence)
            }
        }
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
            return ExportResult(0, normalized.size, failures, target = ExportTarget.GOOGLE_DRIVE,
                freshCaptureRetryDates = normalized.toSet())
        }
        val bundle = try {
            bundleFactory.daily(
                operationId = operationId,
                profileId = profileId,
                source = source,
                data = captured,
                settings = settings.copy(exportTarget = ExportTarget.GOOGLE_DRIVE),
                settingsSnapshotJson = frozenSettingsSnapshotJson,
                requestedDates = normalized,
                captureFailures = failures,
            )
        } catch (_: Exception) {
            return ExportResult(
                0,
                normalized.size,
                normalized.map { FailedDateDetail(it, ExportFailureReason.FILE_WRITE_ERROR) },
                target = ExportTarget.GOOGLE_DRIVE,
            )
        }
        return runner.run(bundle, destinationId).toExportResult(normalized, operationId, bundle.captureEvidence)
    }

    suspend fun acknowledgeAfterHistory(operationId: String): Boolean =
        runner.acknowledgeAfterHistory(operationId)

    /** History has only a logical handle; residual capture uses the journal's frozen authority. */
    suspend fun retryFromHistory(dates: List<LocalDate>, operationId: String, currentSettings: ExportSettings): ExportResult {
        val journal = (runner.recoveryJournal(operationId) as? GoogleDriveJournalLoad.Found)?.journal
            ?: return failed(dates, GoogleDriveErrorId.AMBIGUOUS_COMMIT, operationId)
        val snapshotJson = journal.settingsSnapshotJson
            ?: return failed(dates, GoogleDriveErrorId.REMOTE_CONFLICT, operationId)
        val restored = runCatching {
            val snapshot = runCatching { AndroidExportSettingsSnapshotCodec.decode(snapshotJson) }.getOrNull()
            if (snapshot != null) snapshot.restoreOnto(currentSettings).copy(
                executionEnginePin = snapshot.enginePin, executionEngineAuthorityIsFrozen = true,
            ) else kotlinx.serialization.json.Json.decodeFromString(ExportSettings.serializer(), snapshotJson)
        }.getOrNull() ?: return failed(dates, GoogleDriveErrorId.REMOTE_CONFLICT, operationId)
        return exportDates(dates, restored, journal.destinationId, journal.profileId, "retry", operationId, snapshotJson)
    }

    private fun GoogleDriveRunResult.toExportResult(
        dates: List<LocalDate>,
        operationId: String,
        evidence: GoogleDriveCaptureEvidence,
    ): ExportResult {
        val captured = dates.filter { it.toString() in evidence.capturedOwnerDates }
        val captureFailures = evidence.failedDates.filter { it.date in dates }
        return ExportResult(
            // An artifact prefix cannot prove completion of any owner date.
            successCount = if (this is GoogleDriveRunResult.Complete) captured.size else 0,
            totalCount = dates.size,
            failedDateDetails = captureFailures + if (this is GoogleDriveRunResult.Stopped) captured.map {
                FailedDateDetail(it, error.toFailureReason(), error.serialId)
            } else emptyList(),
            target = ExportTarget.GOOGLE_DRIVE,
            artifactCount = when (this) {
                is GoogleDriveRunResult.Complete -> artifactCount
                is GoogleDriveRunResult.Stopped -> completedArtifactCount
            },
            retryDriveOperationIds = captured.associateWith { operationId },
            freshCaptureRetryDates = captureFailures.mapTo(linkedSetOf()) { it.date },
        )
    }

    private fun failed(dates: List<LocalDate>, error: GoogleDriveErrorId, operationId: String) = ExportResult(
        0, dates.size, dates.map { FailedDateDetail(it, error.toFailureReason(), error.serialId) },
        target = ExportTarget.GOOGLE_DRIVE, retryDriveOperationIds = dates.associateWith { operationId },
    )

    private fun residualOperationId(operationId: String, dates: List<LocalDate>): String =
        "drive-residual-" + sha256Hex(("healthmd.drive.residual.v1\u0000$operationId\u0000" +
            dates.joinToString("\u0000")).encodeToByteArray())
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
