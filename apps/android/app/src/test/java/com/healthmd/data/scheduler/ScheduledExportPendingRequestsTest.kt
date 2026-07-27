package com.healthmd.data.scheduler

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.testing.syntheticExportEnginePin
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.domain.model.ExportTarget
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class ScheduledExportPendingRequestsTest {

    @Test
    fun pendingRequests_mergesLegacyDatesWithExplicitRequests() {
        val explicitDate = LocalDate.parse("2026-06-02")
        val settings = ExportSettings(
            pendingScheduledRetryDates = listOf("2026-06-01", "not-a-date", "2026-06-02"),
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = explicitDate,
                    firstFailedAtMillis = 100L,
                    lastAttemptAtMillis = 200L,
                    lastFailureReason = ExportFailureReason.DEVICE_LOCKED,
                    attemptCount = 2,
                )
            ),
        )

        val requests = ScheduledExportPendingRequests.pendingRequests(settings)

        assertThat(requests.map { it.date }).containsExactly(
            LocalDate.parse("2026-06-01"),
            explicitDate,
        ).inOrder()
        assertThat(requests.first { it.date == explicitDate }.lastFailureReason)
            .isEqualTo(ExportFailureReason.DEVICE_LOCKED)
        assertThat(requests.first { it.date == explicitDate }.attemptCount).isEqualTo(2)
    }

    @Test
    fun scheduledRunDates_pastCompleteDaysEndsYesterdayAndIncludesPendingDates() {
        val today = LocalDate.parse("2026-06-10")
        val pendingDate = LocalDate.parse("2026-06-05")
        val settings = ExportSettings(
            scheduleLookbackDays = 3,
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = pendingDate,
                    firstFailedAtMillis = 100L,
                    attemptCount = 1,
                ),
            ),
        )

        val dates = ScheduledExportPendingRequests.scheduledRunDates(settings, today)

        assertThat(dates).containsExactly(
            pendingDate,
            LocalDate.parse("2026-06-07"),
            LocalDate.parse("2026-06-08"),
            LocalDate.parse("2026-06-09"),
        ).inOrder()
    }

    @Test
    fun scheduledRunDates_multipleMissedOccurrencesUnionsTheirWindows() {
        val settings = ExportSettings(scheduleLookbackDays = 1)

        val dates = ScheduledExportPendingRequests.scheduledRunDates(
            settings = settings,
            intendedRunDates = listOf(
                LocalDate.parse("2026-06-14"),
                LocalDate.parse("2026-06-16"),
            ),
        )

        assertThat(dates).containsExactly(
            LocalDate.parse("2026-06-13"),
            LocalDate.parse("2026-06-15"),
        ).inOrder()
    }

    @Test
    fun scheduledRunDates_todayExportsTodayAndIncludesPendingCompletedDates() {
        val today = LocalDate.parse("2026-06-10")
        val pendingYesterday = LocalDate.parse("2026-06-09")
        val pendingToday = LocalDate.parse("2026-06-10")
        val settings = ExportSettings(
            scheduleDateWindow = ScheduleDateWindow.TODAY,
            scheduleLookbackDays = 7,
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = pendingYesterday,
                    firstFailedAtMillis = 100L,
                    attemptCount = 1,
                ),
                PendingScheduledExportRequest(
                    date = pendingToday,
                    firstFailedAtMillis = 200L,
                    attemptCount = 1,
                ),
            ),
        )

        val dates = ScheduledExportPendingRequests.scheduledRunDates(settings, today)

        assertThat(dates).containsExactly(pendingYesterday, pendingToday).inOrder()
    }

    @Test
    fun pendingRequestsKeepApiAndFolderRetriesSeparateForTheSameDate() {
        val date = LocalDate.parse("2026-06-01")
        val settings = ExportSettings(
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(date = date, exportTarget = ExportTarget.DEVICE_FOLDER),
                PendingScheduledExportRequest(date = date, exportTarget = ExportTarget.API_ENDPOINT),
            ),
        )

        val updated = ScheduledExportPendingRequests.applyAttemptResult(
            settings = settings,
            attemptedDates = listOf(date),
            failedDateDetails = emptyList(),
            target = ExportTarget.API_ENDPOINT,
        )

        val remaining = ScheduledExportPendingRequests.pendingRequests(updated)
        assertThat(remaining).hasSize(1)
        assertThat(remaining.single().exportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)
    }

    @Test
    fun apiRetriesFromDifferentEndpointsRemainSeparate() {
        val date = LocalDate.parse("2026-06-01")
        val oldFingerprint = "old-endpoint"
        val settings = ExportSettings(
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://new.example.com/ingest",
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = date,
                    exportTarget = ExportTarget.API_ENDPOINT,
                    destinationFingerprint = oldFingerprint,
                )
            ),
        )

        val updated = ScheduledExportPendingRequests.applyAttemptResult(
            settings = settings,
            attemptedDates = listOf(date),
            failedDateDetails = listOf(FailedDateDetail(date, ExportFailureReason.NETWORK_ERROR)),
            target = ExportTarget.API_ENDPOINT,
        )

        val requests = ScheduledExportPendingRequests.pendingRequests(updated)
        assertThat(requests).hasSize(2)
        assertThat(requests.mapNotNull { it.destinationFingerprint }).contains(oldFingerprint)
    }

    @Test
    fun pendingRetryRetainsTheExactOriginalPinAcrossNewAttemptsAndCombines() {
        val date = LocalDate.parse("2026-06-01")
        val originalPin = syntheticExportEnginePin(mode = ExportEngineMode.shadow)
        val newerPin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val settings = ExportSettings(
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = date,
                    enginePin = originalPin,
                    firstFailedAtMillis = 100L,
                    lastAttemptAtMillis = 100L,
                    attemptCount = 1,
                ),
            ),
        )

        val updated = ScheduledExportPendingRequests.applyAttemptResult(
            settings = settings,
            attemptedDates = listOf(date),
            failedDateDetails = listOf(FailedDateDetail(date, ExportFailureReason.NETWORK_ERROR)),
            nowMillis = 500L,
            enginePin = newerPin,
        )

        assertThat(ScheduledExportPendingRequests.pendingRequests(updated).single().enginePin)
            .isEqualTo(originalPin)
        assertThat(
            ScheduledExportPendingRequests.scheduledRunDates(
                settings = updated,
                today = LocalDate.parse("2026-06-02"),
                enginePin = originalPin,
            ),
        ).contains(date)
        assertThat(
            ScheduledExportPendingRequests.scheduledRunDates(
                settings = updated,
                today = LocalDate.parse("2026-06-02"),
                enginePin = newerPin,
            ),
        ).doesNotContain(date)
    }

    @Test
    fun pendingRetryRetainsExactOriginalSnapshotAcrossAttemptsAndMatching() {
        val date = LocalDate.parse("2026-06-01")
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val originalSnapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                ExportSettings(filenameFormat = "original-{date}"),
                pin,
                ZoneId.of("America/Los_Angeles"),
            ),
        )
        val newerSnapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                ExportSettings(
                    filenameFormat = "newer-{date}",
                    exportFormats = setOf(ExportFormat.JSON),
                ),
                pin,
                ZoneId.of("America/Los_Angeles"),
            ),
        )
        val settings = ExportSettings(
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = date,
                    enginePin = pin,
                    settingsSnapshotJson = originalSnapshot,
                    firstFailedAtMillis = 100L,
                    lastAttemptAtMillis = 100L,
                    attemptCount = 1,
                ),
            ),
        )

        val updated = ScheduledExportPendingRequests.applyAttemptResult(
            settings = settings,
            attemptedDates = listOf(date),
            failedDateDetails = listOf(FailedDateDetail(date, ExportFailureReason.NETWORK_ERROR)),
            nowMillis = 500L,
            enginePin = pin,
            settingsSnapshotJson = newerSnapshot,
        )

        val retained = ScheduledExportPendingRequests.pendingRequests(updated).single()
        assertThat(retained.settingsSnapshotJson).isEqualTo(originalSnapshot)
        assertThat(
            ScheduledExportPendingRequests.scheduledRunDates(
                settings = updated,
                today = LocalDate.parse("2026-06-02"),
                enginePin = pin,
                settingsSnapshotJson = originalSnapshot,
            ),
        ).contains(date)
        assertThat(
            ScheduledExportPendingRequests.scheduledRunDates(
                settings = updated,
                today = LocalDate.parse("2026-06-02"),
                enginePin = pin,
                settingsSnapshotJson = newerSnapshot,
            ),
        ).doesNotContain(date)
    }

    @Test
    fun legacyPendingRetryDoesNotInheritANewNonLegacyPinOrSnapshot() {
        val date = LocalDate.parse("2026-06-01")
        val settings = ExportSettings(
            pendingScheduledExportRequests = listOf(PendingScheduledExportRequest(date = date)),
        )

        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                ExportSettings(),
                pin,
                ZoneId.of("America/Los_Angeles"),
            ),
        )
        val updated = ScheduledExportPendingRequests.recordFailedDates(
            settings = settings,
            dates = listOf(date),
            nowMillis = 500L,
            enginePin = pin,
            settingsSnapshotJson = snapshotJson,
        )

        val request = ScheduledExportPendingRequests.pendingRequests(updated).single()
        assertThat(request.enginePin).isNull()
        assertThat(request.settingsSnapshotJson).isNull()
    }

    @Test
    fun unresolvedApiDatesRetainOperationWhileAcknowledgedCaptureFailuresStartFresh() {
        val unresolved = LocalDate.parse("2026-06-01")
        val recapture = unresolved.plusDays(1)
        val operationId = "11111111-2222-3333-4444-555555555555"
        val settings = ExportSettings(
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            pendingScheduledExportRequests = listOf(unresolved, recapture).map {
                PendingScheduledExportRequest(
                    date = it,
                    exportTarget = ExportTarget.API_ENDPOINT,
                    destinationFingerprint = "fingerprint",
                    apiOperationId = operationId,
                )
            },
        )

        val updated = ScheduledExportPendingRequests.applyAttemptResult(
            settings = settings,
            attemptedDates = listOf(unresolved, recapture),
            failedDateDetails = listOf(
                FailedDateDetail(unresolved, ExportFailureReason.NETWORK_ERROR),
                FailedDateDetail(recapture, ExportFailureReason.NO_HEALTH_DATA),
            ),
            target = ExportTarget.API_ENDPOINT,
            destinationFingerprint = "fingerprint",
            apiOperationIds = mapOf(unresolved to operationId),
            freshCaptureRetryDates = setOf(recapture),
        )

        val requests = ScheduledExportPendingRequests.pendingRequests(updated).associateBy { it.date }
        assertThat(requests.getValue(unresolved).apiOperationId).isEqualTo(operationId)
        assertThat(requests.getValue(recapture).apiOperationId).isNull()
    }

    @Test
    fun resumingApiOperationDoesNotMixNewScheduleDatesOrAnotherOperation() {
        val first = LocalDate.parse("2026-06-01")
        val second = LocalDate.parse("2026-06-02")
        val operationId = "11111111-2222-3333-4444-555555555555"
        val settings = ExportSettings(
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            scheduleLookbackDays = 2,
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = first,
                    exportTarget = ExportTarget.API_ENDPOINT,
                    apiOperationId = operationId,
                ),
                PendingScheduledExportRequest(
                    date = second,
                    exportTarget = ExportTarget.API_ENDPOINT,
                    apiOperationId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                ),
            ),
        )

        val dates = ScheduledExportPendingRequests.scheduledRunDates(
            settings = settings,
            intendedRunDates = listOf(LocalDate.parse("2026-06-10")),
            destinationFingerprint = null,
            apiOperationId = operationId,
            resumeExistingApiOperation = true,
        )

        assertThat(dates).containsExactly(first)
    }

    @Test
    fun unresolvedFolderDatesRetainJournalWhileCaptureFailuresStartFresh() {
        val unresolved = LocalDate.parse("2026-06-01")
        val recapture = unresolved.plusDays(1)
        val operationId = "folder-operation-1"
        val settings = ExportSettings(
            scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
            pendingScheduledExportRequests = listOf(unresolved, recapture).map { date ->
                PendingScheduledExportRequest(
                    date = date,
                    exportTarget = ExportTarget.DEVICE_FOLDER,
                    folderOperationId = operationId,
                )
            },
        )

        val updated = ScheduledExportPendingRequests.applyAttemptResult(
            settings = settings,
            attemptedDates = listOf(unresolved, recapture),
            failedDateDetails = listOf(
                FailedDateDetail(unresolved, ExportFailureReason.FILE_WRITE_ERROR),
                FailedDateDetail(recapture, ExportFailureReason.NO_HEALTH_DATA),
            ),
            target = ExportTarget.DEVICE_FOLDER,
            folderOperationIds = mapOf(unresolved to operationId),
            freshCaptureRetryDates = setOf(recapture),
        )

        val requests = ScheduledExportPendingRequests.pendingRequests(updated).associateBy { it.date }
        assertThat(requests.getValue(unresolved).folderOperationId).isEqualTo(operationId)
        assertThat(requests.getValue(recapture).folderOperationId).isNull()
    }

    @Test
    fun resumingFolderOperationDoesNotMixNewDatesOrAnotherJournal() {
        val first = LocalDate.parse("2026-06-01")
        val second = LocalDate.parse("2026-06-02")
        val operationId = "folder-operation-1"
        val settings = ExportSettings(
            scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
            scheduleLookbackDays = 2,
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = first,
                    folderOperationId = operationId,
                ),
                PendingScheduledExportRequest(
                    date = second,
                    folderOperationId = "folder-operation-2",
                ),
            ),
        )

        val dates = ScheduledExportPendingRequests.scheduledRunDates(
            settings = settings,
            intendedRunDates = listOf(LocalDate.parse("2026-06-10")),
            folderOperationId = operationId,
            resumeExistingFolderOperation = true,
        )

        assertThat(dates).containsExactly(first)
    }

    @Test
    fun applyAttemptResult_clearsSuccessfulDatesAndKeepsFailedAndUnattemptedDates() {
        val date1 = LocalDate.parse("2026-06-01")
        val date2 = LocalDate.parse("2026-06-02")
        val date3 = LocalDate.parse("2026-06-03")
        val settings = ExportSettings(
            pendingScheduledExportRequests = listOf(date1, date2, date3).map {
                PendingScheduledExportRequest(date = it, firstFailedAtMillis = 100L, attemptCount = 1)
            },
        )

        val updated = ScheduledExportPendingRequests.applyAttemptResult(
            settings = settings,
            attemptedDates = listOf(date1, date2),
            failedDateDetails = listOf(FailedDateDetail(date2, ExportFailureReason.FILE_WRITE_ERROR)),
            nowMillis = 500L,
        )

        val requests = ScheduledExportPendingRequests.pendingRequests(updated)
        assertThat(requests.map { it.date }).containsExactly(date2, date3).inOrder()
        assertThat(requests.first { it.date == date2 }.lastFailureReason)
            .isEqualTo(ExportFailureReason.FILE_WRITE_ERROR)
        assertThat(requests.first { it.date == date2 }.lastAttemptAtMillis).isEqualTo(500L)
        assertThat(updated.pendingScheduledRetryDates).containsExactly("2026-06-02", "2026-06-03").inOrder()
    }
}
