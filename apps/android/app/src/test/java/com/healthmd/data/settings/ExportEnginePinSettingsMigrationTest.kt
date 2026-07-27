package com.healthmd.data.settings

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.testing.syntheticExportEnginePin
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.domain.model.ExportTarget
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Test

class ExportEnginePinSettingsMigrationTest {
    private val json = Json { encodeDefaults = true; explicitNulls = false }

    @Test
    fun oldDataStorePendingRequestDecodesAsLegacyNilPin() {
        val decoded = decodePersistedExportSettings(
            """{"pendingScheduledExportRequests":[{"date":"2026-06-01","attemptCount":2}]}""",
        )

        assertThat(decoded.pendingScheduledExportRequests).hasSize(1)
        assertThat(decoded.pendingScheduledExportRequests.single().enginePin).isNull()
        assertThat(decoded.pendingScheduledExportRequests.single().settingsSnapshotJson).isNull()
        assertThat(decoded.pendingScheduledExportRequests.single().apiOperationId).isNull()
    }

    @Test
    fun durableApiOperationIdentityRoundTripsWithoutAffectingOldData() {
        val operationId = "11111111-2222-3333-4444-555555555555"
        val encoded = json.encodeToString(
            ExportSettings(
                pendingScheduledExportRequests = listOf(
                    PendingScheduledExportRequest(
                        date = LocalDate.parse("2026-06-01"),
                        exportTarget = ExportTarget.API_ENDPOINT,
                        destinationFingerprint = "a".repeat(64),
                        apiOperationId = operationId,
                    ),
                ),
            ),
        )

        val decoded = decodePersistedExportSettings(encoded)

        assertThat(decoded.pendingScheduledExportRequests.single().apiOperationId)
            .isEqualTo(operationId)
    }

    @Test
    fun presentNonStringOrNullSnapshotRemainsDetectablyInvalidInsteadOfBecomingLegacy() {
        listOf(
            "null",
            "{\"unexpected\":true}",
        ).forEach { corruptSnapshot ->
            val decoded = decodePersistedExportSettings(
                """{"pendingScheduledExportRequests":[{"date":"2026-06-01","settingsSnapshotJson":$corruptSnapshot}]}""",
            )
            val retained = decoded.pendingScheduledExportRequests.single().settingsSnapshotJson

            assertThat(retained).isNotNull()
            assertThat(AndroidExportSettingsSnapshotCodec.decodeOrNull(retained)).isNull()
        }
    }

    @Test
    fun validPersistedRustPinIsRetainedExactly() {
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                ExportSettings(),
                pin,
                ZoneId.of("America/Los_Angeles"),
            ),
        )
        val encoded = json.encodeToString(
            ExportSettings(
                pendingScheduledExportRequests = listOf(
                    PendingScheduledExportRequest(
                        date = LocalDate.parse("2026-06-01"),
                        enginePin = pin,
                        settingsSnapshotJson = snapshotJson,
                    ),
                ),
            ),
        )

        val decoded = decodePersistedExportSettings(encoded)
        val request = decoded.pendingScheduledExportRequests.single()

        assertThat(request.enginePin).isEqualTo(pin)
        assertThat(request.settingsSnapshotJson).isEqualTo(snapshotJson)
    }

    @Test
    fun unknownOrCorruptPersistedPinFailsClosedBeforeRetryCapture() {
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.shadow)
        val encoded = json.encodeToString(
            ExportSettings(
                pendingScheduledExportRequests = listOf(
                    PendingScheduledExportRequest(
                        date = LocalDate.parse("2026-06-01"),
                        enginePin = pin,
                    ),
                ),
            ),
        )
        val unknown = encoded.replace("\"engine\":\"shadow\"", "\"engine\":\"future\"")
        val corrupt = encoded.replace(
            Regex("\"enginePin\":\\{[^}]+}"),
            "\"enginePin\":{\"engine\":7}",
        )

        assertThat(
            decodePersistedExportSettings(unknown)
                .pendingScheduledExportRequests.single().enginePin,
        ).isNull()
        assertThat(
            decodePersistedExportSettings(corrupt)
                .pendingScheduledExportRequests.single().enginePin,
        ).isNull()
    }
}
