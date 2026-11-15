package com.healthmd.data.settings

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportRequestConfiguration
import com.healthmd.data.export.APIRecoveryAuthorities
import com.healthmd.domain.model.APIRecoveryExecution
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.PendingScheduledExportRequest
import java.time.LocalDate
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Test

class APIRecoveryAuthoritySettingsTest {
    @Test
    fun privatePendingEvidenceRoundTripsWhileExecutionGuardNeverPersists() {
        val evidence = APIRecoveryAuthorities.create(APIExportRequestConfiguration(
            "https://synthetic.example.test", "Bearer synthetic", emptyList(), "a".repeat(64)), "synthetic-profile")
        val pending = PendingScheduledExportRequest(LocalDate.ofEpochDay(10_000), ExportTarget.API_ENDPOINT,
            apiAuthorityJson = evidence, apiOperationId = "operation", apiJournalRequired = true)
        val settings = ExportSettings(pendingScheduledExportRequests = listOf(pending),
            executionAPIRecoveryRequired = true,
            executionAPIRecovery = APIRecoveryExecution(evidence, "synthetic-profile", "operation", "snapshot") { true })
        val encoded = Json.encodeToString(settings)
        assertThat(encoded).doesNotContain("executionAPIRecovery")
        assertThat(encoded).doesNotContain("synthetic-profile")
        assertThat(encoded).doesNotContain("Bearer synthetic")
        val restored = decodePersistedExportSettings(encoded)
        assertThat(restored.pendingScheduledExportRequests.single()).isEqualTo(pending)
        assertThat(restored.executionAPIRecovery).isNull()
        assertThat(restored.executionAPIRecoveryRequired).isFalse()
    }

    @Test
    fun corruptOrOversizedEvidenceStaysDetectablyInvalidWithoutDroppingOtherPendingState() {
        for (evidence in listOf("null", "{}", "7", "\"${"x".repeat(500)}\"")) {
            val decoded = decodePersistedExportSettings(
                """{"pendingScheduledExportRequests":[{"date":"1997-05-19","exportTarget":"API_ENDPOINT","apiAuthorityJson":$evidence,"apiOperationId":"original","attemptCount":3}]}""")
            val pending = decoded.pendingScheduledExportRequests.single()
            assertThat(pending.apiOperationId).isEqualTo("original")
            assertThat(pending.attemptCount).isEqualTo(3)
            assertThat(pending.apiAuthorityJson).isEqualTo("invalid-api-recovery-authority")
            assertThat(APIRecoveryAuthorities.isValid(pending.apiAuthorityJson)).isFalse()
        }
        val legacy = decodePersistedExportSettings(
            """{"pendingScheduledExportRequests":[{"date":"1997-05-19","exportTarget":"API_ENDPOINT"}]}""")
        assertThat(legacy.pendingScheduledExportRequests.single().apiAuthorityJson).isNull()
    }
}
