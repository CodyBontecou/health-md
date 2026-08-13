package com.healthmd.data.scheduler

import android.content.Intent
import androidx.work.Data
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import com.healthmd.testing.syntheticExportEnginePin
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertThrows
import org.junit.Test
import io.mockk.every
import io.mockk.mockk

class ScheduledExportEnginePinMigrationTest {
    @Test
    fun oldConfigurationWorkDataAndIntentKeepExactLegacySignature() {
        val occurrence = occurrence(pin = null)

        assertThat(occurrence.configuration.signature).isEqualTo(
            "e8ac35545896926aae439888b47a4d3a89925092c9f4557e5d190add51772fca",
        )
        assertThat(occurrence.toWorkData().getString(ScheduledExportOccurrence.KEY_ENGINE_PIN_JSON)).isNull()
        assertThat(occurrence.toWorkData().getString(ScheduledExportOccurrence.KEY_GENERATION)).isNull()
        assertThat(ScheduledExportOccurrence.fromWorkData(occurrence.toWorkData()))
            .isEqualTo(occurrence)

        val intent = intentDouble()
        occurrence.putInto(intent)
        val decodedIntent = ScheduledExportOccurrence.fromIntent(intent)
        assertThat(decodedIntent).isEqualTo(occurrence)
        assertThat(decodedIntent?.enginePin).isNull()
    }

    @Test
    fun pinOnlyOccurrenceKeepsItsExactPreSnapshotSignature() {
        val occurrence = occurrence(
            syntheticExportEnginePin(mode = ExportEngineMode.rust),
        )

        assertThat(occurrence.configuration.signature).isEqualTo(
            "99ce6b5a1e07c202f532fdefca3de0d22176d8134ff76bb1182b176a55d2ccee",
        )
        assertThat(
            occurrence.toWorkData().getString(
                ScheduledExportOccurrence.KEY_SETTINGS_SNAPSHOT_JSON,
            ),
        ).isNull()
    }

    @Test
    fun nonLegacyPinUsesBoundedCanonicalJsonAndRoundTripsWithoutReresolution() {
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val occurrence = occurrence(pin)
        val data = occurrence.toWorkData()
        val encoded = data.getString(ScheduledExportOccurrence.KEY_ENGINE_PIN_JSON)

        assertThat(encoded).isNotNull()
        assertThat(encoded!!.toByteArray().size)
            .isAtMost(ExportEnginePinCodec.MAX_CANONICAL_JSON_BYTES)
        assertThat(encoded).startsWith("{\"artifact_plan_version\":")
        assertThat(ScheduledExportOccurrence.fromWorkData(data)).isEqualTo(occurrence)
        assertThat(occurrence.configuration.signature)
            .isNotEqualTo(occurrence(null).configuration.signature)

        val intent = intentDouble()
        occurrence.putInto(intent)
        assertThat(ScheduledExportOccurrence.fromIntent(intent)).isEqualTo(occurrence)
    }

    @Test
    fun queuedOccurrenceRestoresFrozenOutputAfterSettingsMutationAndRoundTripsIntent() {
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val queuedSettings = ExportSettings(
            exportFormats = linkedSetOf(ExportFormat.MARKDOWN, ExportFormat.CSV),
            filenameFormat = "queued-{date}",
            folderStructure = "queued/{year}",
            includeMetadata = false,
            scheduleEnabled = true,
        )
        val snapshot = AndroidExportSettingsSnapshot.capture(queuedSettings, pin, ZoneId.of("America/Los_Angeles"))
        val queued = occurrence(pin, snapshot)

        val decoded = requireNotNull(ScheduledExportOccurrence.fromWorkData(queued.toWorkData()))
        val currentAfterQueue = queuedSettings.copy(
            exportFormats = setOf(ExportFormat.JSON),
            filenameFormat = "changed-{date}",
            folderStructure = "changed",
            includeMetadata = true,
            scheduleHour = 21,
        )
        val restored = requireNotNull(decoded.settingsSnapshot).restoreOnto(currentAfterQueue)

        assertThat(restored.exportFormats)
            .containsExactly(ExportFormat.MARKDOWN, ExportFormat.CSV)
        assertThat(restored.filenameFormat).isEqualTo("queued-{date}")
        assertThat(restored.folderStructure).isEqualTo("queued/{year}")
        assertThat(restored.includeMetadata).isFalse()
        assertThat(restored.scheduleHour).isEqualTo(21)

        val intent = intentDouble()
        queued.putInto(intent)
        assertThat(ScheduledExportOccurrence.fromIntent(intent)).isEqualTo(queued)
    }

    @Test
    fun scheduleGenerationRoundTripsThroughWorkDataAndAlarmIntent() {
        val occurrence = occurrence(pin = null).copy(generation = "generation-roundtrip")

        val data = occurrence.toWorkData()
        assertThat(data.getString(ScheduledExportOccurrence.KEY_GENERATION))
            .isEqualTo("generation-roundtrip")
        assertThat(ScheduledExportOccurrence.fromWorkData(data)).isEqualTo(occurrence)

        val intent = intentDouble()
        occurrence.putInto(intent)
        assertThat(ScheduledExportOccurrence.fromIntent(intent)).isEqualTo(occurrence)
    }

    @Test
    fun presentCorruptSnapshotFailsClosedInsteadOfDecodingAsLegacy() {
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val snapshot = AndroidExportSettingsSnapshot.capture(
            ExportSettings(),
            pin,
            ZoneId.of("America/Los_Angeles"),
        )
        val valid = occurrence(pin, snapshot).toWorkData()
        val corrupt = Data.Builder().putAll(valid)
            .putString(ScheduledExportOccurrence.KEY_SETTINGS_SNAPSHOT_JSON, "{not-json")
            .build()

        assertThat(ScheduledExportOccurrence.hasDurableSettingsSnapshot(corrupt)).isTrue()
        assertThat(ScheduledExportOccurrence.fromWorkData(corrupt)).isNull()
    }

    @Test
    fun snapshotPinAndTimezoneMustMatchOccurrenceMetadata() {
        val rustPin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val snapshot = AndroidExportSettingsSnapshot.capture(
            ExportSettings(),
            rustPin,
            ZoneId.of("America/Los_Angeles"),
        )

        assertThrows(IllegalArgumentException::class.java) {
            occurrence(syntheticExportEnginePin(mode = ExportEngineMode.shadow), snapshot)
        }
        assertThrows(IllegalArgumentException::class.java) {
            ScheduledExportConfiguration(
                cadenceValue = 1,
                cadenceUnit = ScheduleCadenceUnit.DAYS,
                hour = 6,
                minute = 0,
                lookbackDays = 1,
                dateWindow = ScheduleDateWindow.PAST_COMPLETE_DAYS,
                target = ExportTarget.DEVICE_FOLDER,
                destinationFingerprint = null,
                zoneId = "America/New_York",
                enginePin = rustPin.copy(ianaTimeZone = "America/New_York"),
                settingsSnapshot = snapshot,
            )
        }
    }

    @Test
    fun unknownCorruptAndTimezoneMismatchedPinsAreRejectedBeforeCapture() {
        val occurrence = occurrence(syntheticExportEnginePin(mode = ExportEngineMode.rust))
        val validData = occurrence.toWorkData()
        val validJson = requireNotNull(
            validData.getString(ScheduledExportOccurrence.KEY_ENGINE_PIN_JSON),
        )
        val unknownEngine = validJson.replace("\"engine\":\"rust\"", "\"engine\":\"future\"")
        val unknownData = Data.Builder().putAll(validData)
            .putString(ScheduledExportOccurrence.KEY_ENGINE_PIN_JSON, unknownEngine)
            .build()
        val corruptData = Data.Builder().putAll(validData)
            .putString(ScheduledExportOccurrence.KEY_ENGINE_PIN_JSON, "{" + "x".repeat(4_096))
            .build()
        val strippedPinData = Data.Builder().putAll(occurrence(null).toWorkData())
            .putString(ScheduledExportOccurrence.KEY_SIGNATURE, occurrence.configuration.signature)
            .build()

        assertThat(ScheduledExportOccurrence.hasDurableEnginePin(unknownData)).isTrue()
        assertThat(ScheduledExportOccurrence.fromWorkData(unknownData)).isNull()
        assertThat(ScheduledExportOccurrence.fromWorkData(corruptData)).isNull()
        assertThat(ScheduledExportOccurrence.fromWorkData(strippedPinData)).isNull()
        assertThrows(IllegalArgumentException::class.java) {
            occurrence(syntheticExportEnginePin(zoneId = "America/New_York"))
        }
    }

    private fun occurrence(
        pin: com.healthmd.domain.exportengine.ExportEnginePin?,
        settingsSnapshot: AndroidExportSettingsSnapshot? = null,
    ) = ScheduledExportOccurrence(
            configuration = ScheduledExportConfiguration(
                cadenceValue = 1,
                cadenceUnit = ScheduleCadenceUnit.DAYS,
                hour = 6,
                minute = 0,
                lookbackDays = 1,
                dateWindow = ScheduleDateWindow.PAST_COMPLETE_DAYS,
                target = ExportTarget.DEVICE_FOLDER,
                destinationFingerprint = null,
                zoneId = settingsSnapshot?.ianaTimeZone
                    ?: "America/Los_Angeles".takeIf { pin != null }
                    ?: "UTC",
                enginePin = pin,
                settingsSnapshot = settingsSnapshot,
            ),
            triggerAtMillis = 1_800_000_000_000L,
            intendedLocalDate = LocalDate.parse("2027-01-15"),
        )

    private fun intentDouble(): Intent {
        val strings = mutableMapOf<String, String?>()
        val longs = mutableMapOf<String, Long>()
        val ints = mutableMapOf<String, Int>()
        val intent = mockk<Intent>(relaxed = true)
        every { intent.putExtra(any<String>(), any<String>()) } answers {
            strings[firstArg()] = secondArg()
            intent
        }
        every { intent.putExtra(any<String>(), any<Long>()) } answers {
            longs[firstArg()] = secondArg()
            intent
        }
        every { intent.putExtra(any<String>(), any<Int>()) } answers {
            ints[firstArg()] = secondArg()
            intent
        }
        every { intent.removeExtra(any()) } answers {
            strings.remove(firstArg())
            Unit
        }
        every { intent.getStringExtra(any()) } answers { strings[firstArg()] }
        every { intent.getLongExtra(any(), any()) } answers { longs[firstArg()] ?: secondArg() }
        every { intent.getIntExtra(any(), any()) } answers { ints[firstArg()] ?: secondArg() }
        return intent
    }
}
