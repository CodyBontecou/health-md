package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.export.APIExportUploadResult
import com.healthmd.data.export.APIExportUploader
import com.healthmd.data.export.JsonExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.HealthRepository
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Test
import java.time.LocalDate

class APIEndpointExportRunnerTest {
    @Test
    fun postsOneEnvelopeWithReadableDatesAndReportsEmptyDates() = runTest {
        val first = LocalDate.of(2026, 7, 10)
        val second = LocalDate.of(2026, 7, 11)
        val uploader = CapturingUploader()
        val runner = runner(
            dataByDate = mapOf(
                first to HealthData(first, activity = ActivityData(steps = 100)),
                second to HealthData(second),
            ),
            uploader = uploader,
        )

        val result = runner.exportDates(
            dates = listOf(second, first),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
            ),
        )

        assertThat(result.successCount).isEqualTo(1)
        assertThat(result.totalCount).isEqualTo(2)
        assertThat(result.failedDateDetails.map { it.reason }).containsExactly(ExportFailureReason.NO_HEALTH_DATA)
        assertThat(result.httpStatusCode).isEqualTo(202)
        assertThat(uploader.calls).isEqualTo(1)
        assertThat(uploader.authorization).isEqualTo("Bearer test-token")
        assertThat(uploader.requestHeaders)
            .containsExactly(APIExportRequestHeader("X-API-Key", "test-api-key"))

        val envelope = Json.parseToJsonElement(requireNotNull(uploader.payload)).jsonObject
        assertThat(envelope.getValue("records").jsonArray).hasSize(1)
        assertThat(envelope.getValue("failed_date_details").jsonArray).hasSize(1)
    }

    @Test
    fun changedDestinationFingerprintAbortsBeforeUpload() = runTest {
        val date = LocalDate.of(2026, 7, 10)
        val uploader = CapturingUploader()
        val runner = runner(
            dataByDate = mapOf(date to HealthData(date, activity = ActivityData(steps = 100))),
            uploader = uploader,
        )

        val result = runner.exportDates(
            dates = listOf(date),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
            ),
            expectedDestinationFingerprint = "stale-fingerprint",
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.single().reason)
            .isEqualTo(ExportFailureReason.INVALID_API_ENDPOINT)
        assertThat(uploader.calls).isEqualTo(0)
    }

    @Test
    fun uploadFailureDoesNotCountPreparedRecordsAsSuccess() = runTest {
        val date = LocalDate.of(2026, 7, 10)
        val uploader = CapturingUploader(throwOnUpload = true)
        val runner = runner(
            dataByDate = mapOf(date to HealthData(date, activity = ActivityData(steps = 100))),
            uploader = uploader,
        )

        val result = runner.exportDates(
            dates = listOf(date),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
            ),
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails).hasSize(1)
        assertThat(result.failedDateDetails.single().reason).isEqualTo(ExportFailureReason.NETWORK_ERROR)
    }

    private fun runner(
        dataByDate: Map<LocalDate, HealthData>,
        uploader: APIExportUploader,
    ): APIEndpointExportRunner {
        val healthRepository = object : HealthRepository {
            override suspend fun fetchHealthData(date: LocalDate): HealthData = dataByDate.getValue(date)
            override suspend fun isAvailable(): Boolean = true
            override suspend fun hasPermissions(): Boolean = true
            override suspend fun hasHistoricalReadPermission(): Boolean = true
            override suspend fun hasBackgroundReadPermission(): Boolean = true
            override suspend fun getEarliestDataDate(): LocalDate? = dataByDate.keys.minOrNull()
            override fun isBeforeFirstUnlock(): Boolean = false
        }
        val credentials = object : APIExportCredentialStore {
            override suspend fun authorizationHeader(): String = "Bearer test-token"
            override suspend fun hasAuthorization(): Boolean = true
            override suspend fun saveAuthorization(value: String) = Unit
            override suspend fun clearAuthorization() = Unit
            override suspend fun requestHeaders(): List<APIExportRequestHeader> =
                listOf(APIExportRequestHeader("X-API-Key", "test-api-key"))
        }
        val jsonExporter = JsonExporter()
        return APIEndpointExportRunner(
            healthRepository = healthRepository,
            envelopeBuilder = APIExportEnvelopeBuilder(jsonExporter),
            jsonExporter = jsonExporter,
            uploader = uploader,
            credentialStore = credentials,
        )
    }

    private class CapturingUploader(
        private val throwOnUpload: Boolean = false,
    ) : APIExportUploader {
        var calls = 0
        var payload: String? = null
        var authorization: String? = null
        var requestHeaders: List<APIExportRequestHeader> = emptyList()

        override suspend fun upload(
            endpointUrl: String,
            payload: String,
            authorizationHeader: String?,
            requestHeaders: List<APIExportRequestHeader>,
        ): APIExportUploadResult {
            calls++
            this.payload = payload
            authorization = authorizationHeader
            this.requestHeaders = requestHeaders
            if (throwOnUpload) throw IllegalStateException("offline")
            return APIExportUploadResult(statusCode = 202)
        }
    }
}
