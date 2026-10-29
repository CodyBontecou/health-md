package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.DateFormatPreference
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.FrontmatterKeyStyle
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MarkdownTemplateConfig
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.MetricTrackingConfig
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WriteMode
import com.healthmd.testing.syntheticExportEnginePin
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertThrows
import org.junit.Test

class AndroidExportSettingsSnapshotTest {
    @Test
    fun euDotSurvivesFrozenProfilePersistenceAndFormatsCalendarDates() {
        val settings = ExportSettings().let { it.copy(
            formatCustomization = it.formatCustomization.copy(dateFormat = DateFormatPreference.EU_DOT),
        ) }
        val snapshot = AndroidExportSettingsSnapshot.capture(settings, syntheticExportEnginePin(zoneId = "UTC"), ZoneId.of("UTC"))
        val decoded = AndroidExportSettingsSnapshotCodec.decode(AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot))
        val restored = decoded.restoreOnto(ExportSettings())
        assertThat(restored.formatCustomization.dateFormat).isEqualTo(DateFormatPreference.EU_DOT)
        for ((date, expected) in listOf(
            "2026-01-13" to "13.01.2026",
            "2024-02-29" to "29.02.2024",
            "2025-12-31" to "31.12.2025",
            "2026-01-01" to "01.01.2026",
        )) {
            assertThat(restored.formatCustomization.dateFormat.format(LocalDate.parse(date))).isEqualTo(expected)
        }
    }

    @Test
    fun historicalSnapshotRestorationKeepsExactFrozenAuthority() {
        for (profile in listOf(AndroidExportProfile.android_frozen_v4, AndroidExportProfile.android_analytical_v5)) {
            for (mode in listOf(ExportEngineMode.rust, ExportEngineMode.shadow)) {
                val original = syntheticExportEnginePin(mode = mode, profile = profile).copy(
                    registrySha256 = ExportEnginePin.HISTORICAL_REGISTRY_SHA256,
                    renderProfileRevision = 2u,
                )
                val settings = ExportSettings().let { it.copy(formatCustomization = it.formatCustomization.copy(
                    compatibilitySchemaProfile = if (profile == AndroidExportProfile.android_frozen_v4) CompatibilitySchemaProfile.IOS_V4_FROZEN else CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
                )) }
                val snapshot = AndroidExportSettingsSnapshot.capture(settings, original, ZoneId.of(original.ianaTimeZone))
                val encoded = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot)
                val decoded = AndroidExportSettingsSnapshotCodec.decode(encoded)
                assertThat(decoded.restoreOnto(ExportSettings()).executionEnginePin).isNull()
                val restored = requireNotNull(ScheduledProfileSnapshotFactory(ExportEnginePinPlanner(),
                    io.mockk.mockk<com.healthmd.domain.repository.SettingsRepository>()).restoreForRun(
                    profile = ExportProfile(
                        id = "historical-profile", name = "Synthetic historical profile",
                        settingsSnapshotJson = encoded, target = settings.exportTarget,
                        createdAtEpochMillis = 0L, updatedAtEpochMillis = 0L,
                    ),
                    current = ExportSettings(), lookbackDays = 1,
                ))
                assertThat(decoded.enginePin).isEqualTo(original)
                assertThat(restored.executionEnginePin).isEqualTo(original)
                assertThat(restored.executionEngineAuthorityIsFrozen).isTrue()
            }
        }
    }

    @Test
    fun wakeDateSnapshotRetainsExactAuthorityAcrossPreferenceAndPresentationChanges() {
        val context = AndroidCaptureContext(ZoneId.of("Asia/Kathmandu"), SleepDayAttribution.MORNING_ENDS)
        val pin = ExportEnginePin.create(
            engine = ExportEngineMode.rust,
            profile = AndroidExportProfile.android_sleep_v6,
            ianaTimeZone = context.zoneId.id,
            readiness = testReadiness(),
            registry = testRegistry(AndroidExportProfile.android_sleep_v6).copy(
                registryVersion = 2u, registrySha256 = com.healthmd.core.HEALTHMD_SLEEP_REGISTRY_SHA256,
            ),
        )
        for (presentation in CompatibilitySchemaProfile.entries) {
            val accepted = ExportSettings(executionSleepCaptureContext = context,
                executionSleepCaptureAuthorityIsFrozen = true,
                formatCustomization = FormatCustomization(compatibilitySchemaProfile = presentation))
            val snapshot = AndroidExportSettingsSnapshot.capture(accepted, pin, context.zoneId)
            val bytes = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot)
            val decoded = AndroidExportSettingsSnapshotCodec.decode(bytes)
            val current = ExportSettings(executionSleepCaptureContext = AndroidCaptureContext(
                ZoneId.of("Europe/Berlin"), SleepDayAttribution.NIGHT_BEGINS))
            val factory = ScheduledProfileSnapshotFactory(ExportEnginePinPlanner(), io.mockk.mockk())
            val restored = requireNotNull(factory.restoreForRun(ExportProfile(
                id = "wake-date", name = "Synthetic wake date", settingsSnapshotJson = bytes,
                target = ExportTarget.DEVICE_FOLDER, createdAtEpochMillis = 0L, updatedAtEpochMillis = 0L,
            ), current, 2))
            assertThat(decoded.exportProfile).isEqualTo(AndroidExportProfile.android_sleep_v6)
            assertThat(restored.executionSleepCaptureContext).isEqualTo(context)
            assertThat(restored.executionEnginePin).isEqualTo(pin)
            assertThat(restored.executionEngineAuthorityIsFrozen).isTrue()
            assertThat(AndroidExportSettingsSnapshotCodec.encodeCanonical(decoded)).isEqualTo(bytes)
            for (invalid in listOf(
                decoded.copy(enginePin = null),
                decoded.copy(enginePin = pin.copy(registrySha256 = "0".repeat(64))),
                decoded.copy(enginePin = pin.copy(semanticProfileRevision = 2u)),
                decoded.copy(enginePin = pin.copy(renderProfileRevision = 1u)),
                decoded.copy(enginePin = pin.copy(semanticInputVersion = 1u)),
                decoded.copy(enginePin = pin.copy(engine = ExportEngineMode.shadow)),
                decoded.copy(sleepCaptureContext = context.copy(exportProfileID = null)),
                decoded.copy(exportProfile = AndroidExportProfile.android_frozen_v4),
                decoded.copy(sleepCaptureContext = AndroidCaptureContext(context.zoneId, SleepDayAttribution.NIGHT_BEGINS)),
            )) {
                assertThat(AndroidExportSettingsSnapshotCodec.isStructurallyValid(invalid)).isFalse()
            }
        }
    }

    private val zone = ZoneId.of("America/Los_Angeles")

    @Test
    fun explicitNightCaptureAuthoritySurvivesCanonicalStorage() {
        val settings = ExportSettings()
        val original = AndroidCaptureContext(zone, SleepDayAttribution.NIGHT_BEGINS)
        val snapshot = AndroidExportSettingsSnapshot.capture(settings, pin = null, zone = zone,
            captureContext = original)
        val encoded = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot)
        assertThat(snapshot.version).isEqualTo(2)
        assertThat(encoded).contains("\"sleepDayAttribution\":\"night_begins\"")
        val restored = AndroidExportSettingsSnapshotCodec.decode(encoded).restoreOnto(settings)
        assertThat(restored.executionSleepCaptureContext).isEqualTo(original)
        assertThat(restored.executionSleepCaptureAuthorityIsFrozen).isTrue()
        assertThat(restored.executionSleepCaptureContext!!.zoneId.id).isEqualTo("America/Los_Angeles")
        assertThat(AndroidExportSettingsSnapshotCodec.encodeCanonical(AndroidExportSettingsSnapshotCodec.decode(encoded)))
            .isEqualTo(encoded)
    }

    @Test
    fun legacySnapshotBytesRemainAuthoritativeButMissingCaptureNeverUsesCurrentPreferences() {
        val legacy = AndroidExportSettingsSnapshot.capture(ExportSettings(), null, zone)
        val originalBytes = AndroidExportSettingsSnapshotCodec.encodeCanonical(legacy)
        assertThat(legacy.version).isEqualTo(1)
        assertThat(originalBytes).doesNotContain("sleepCaptureContext")
        val decoded = AndroidExportSettingsSnapshotCodec.decode(originalBytes)
        assertThat(AndroidExportSettingsSnapshotCodec.encodeCanonical(decoded)).isEqualTo(originalBytes)
        val current = ExportSettings(executionSleepCaptureContext = AndroidCaptureContext(
            ZoneId.of("Europe/Berlin"), SleepDayAttribution.MORNING_ENDS))
        val restored = decoded.restoreOnto(current)
        assertThat(restored.executionSleepCaptureContext).isNull()
        assertThat(restored.executionSleepCaptureAuthorityIsFrozen).isTrue()
        val error = assertThrows(com.healthmd.domain.model.SleepAttributionUnavailableException::class.java) {
            AndroidCaptureContext.recovered(restored.executionSleepCaptureContext)
        }
        assertThat(error.reason).isEqualTo(com.healthmd.domain.model.SleepCaptureAuthorityError.MISSING_DURABLE_ATTRIBUTION)
    }

    @Test
    fun snapshotVersionProfileAndCapturedClockMustRemainAtomic() {
        val context = AndroidCaptureContext(zone, SleepDayAttribution.NIGHT_BEGINS)
        val valid = AndroidExportSettingsSnapshot.capture(ExportSettings(), null, zone, context)
        for (invalid in listOf(
            valid.copy(version = 1),
            valid.copy(sleepCaptureContext = null),
            valid.copy(ianaTimeZone = "Europe/Berlin"),
            valid.copy(sleepCaptureContext = AndroidCaptureContext(zone, SleepDayAttribution.MORNING_ENDS)),
        )) {
            val error = assertThrows(AndroidExportSettingsSnapshotException::class.java) {
                AndroidExportSettingsSnapshotCodec.encodeCanonical(invalid)
            }
            assertThat(error.reason).isEqualTo(AndroidExportSettingsSnapshotError.INVALID_STRUCTURE)
        }
        val operational = ExportSettings(executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true)
        val settingsBytes = kotlinx.serialization.json.Json.encodeToString(ExportSettings.serializer(), operational)
        assertThat(settingsBytes).doesNotContain("executionSleepCapture")
    }

    @Test
    fun deepCanonicalRoundTripRestoresOutputAndPreservesMutablePlumbing() {
        val mutableFormats = linkedSetOf(ExportFormat.CSV, ExportFormat.MARKDOWN)
        val mutableCustomFields = linkedMapOf("clinic" to "west", "source" to "watch")
        val mutableMetricConfigs = linkedMapOf(
            "steps" to MetricTrackingConfig(true, "custom-steps"),
        )
        val pin = syntheticExportEnginePin(
            mode = ExportEngineMode.rust,
            profile = AndroidExportProfile.android_analytical_v5,
        )
        val accepted = ExportSettings(
            dataTypes = DataTypeSelection(sleep = false, nutrition = false),
            exportFormat = ExportFormat.CSV,
            exportFormats = mutableFormats,
            includeMetadata = false,
            groupByCategory = false,
            filenameFormat = "health-{date}-{weekday}",
            folderStructure = "{year}/{monthName}",
            writeMode = WriteMode.UPDATE,
            formatCustomization = FormatCustomization(
                dateFormat = DateFormatPreference.US_LONG,
                timeFormat = TimeFormatPreference.HOUR_12_SECONDS,
                unitPreference = UnitPreference.IMPERIAL,
                includeLegacyAndroidAliases = true,
                includeAndroidNativeFields = true,
                compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
                frontmatterConfig = FrontmatterConfiguration(
                    fields = mutableListOf(CustomFrontmatterField("steps", "step_count", false)),
                    customFields = mutableCustomFields,
                    placeholderFields = mutableListOf("clinic", "source"),
                    includeDate = false,
                    includeType = false,
                    customDateKey = "day",
                    customTypeKey = "kind",
                    customTypeValue = "daily-health",
                    keyStyle = FrontmatterKeyStyle.CAMEL_CASE,
                ),
                markdownTemplate = MarkdownTemplateConfig(
                    style = MarkdownTemplateStyle.CUSTOM,
                    customTemplate = "# {{date}}\n{{activity_metrics}}",
                    sectionHeaderLevel = 3,
                    useEmoji = true,
                    includeSummary = false,
                ),
            ),
            metricSelection = MetricSelectionState(linkedSetOf("steps", "avg_hr")),
            dailyNoteInjection = DailyNoteInjectionSettings(
                enabled = true,
                folderPath = "Journal",
                filenamePattern = "day-{date}",
                createIfMissing = false,
                injectMarkdownSections = true,
                enabledMetrics = linkedSetOf("steps"),
            ),
            individualTracking = IndividualTrackingSettings(
                globalEnabled = true,
                enabledMetrics = linkedSetOf("steps"),
                metricConfigs = mutableMetricConfigs,
                entriesFolder = "measurements",
                organizeByCategory = false,
                filenameTemplate = "{date}-{metric}-{time}",
            ),
            includeGranularData = true,
            exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
            apiEndpointUrl = "https://accepted.example.test/upload?token=not-snapshotted",
            subfolder = "frozen-health",
            folderOrganization = FolderOrganization.BY_YEAR_MONTH,
            scheduleEnabled = true,
            scheduleCadenceValue = 2,
            scheduleCadenceUnit = ScheduleCadenceUnit.DAYS,
        )

        val captured = AndroidExportSettingsSnapshot.capture(accepted, pin, zone)
        val canonical = AndroidExportSettingsSnapshotCodec.encodeCanonical(captured)
        val decoded = AndroidExportSettingsSnapshotCodec.decode(canonical)

        mutableFormats.clear()
        mutableCustomFields.clear()
        mutableMetricConfigs.clear()

        assertThat(decoded).isEqualTo(captured)
        assertThat(canonical.toByteArray().size)
            .isAtMost(AndroidExportSettingsSnapshotCodec.MAX_CANONICAL_JSON_BYTES)
        assertThat(decoded.exportFormats).containsExactly(ExportFormat.CSV, ExportFormat.MARKDOWN)
        assertThat(decoded.formatCustomization.frontmatterConfig.customFields)
            .containsExactly("clinic", "west", "source", "watch")
        assertThat(decoded.individualTracking.metricConfigs).containsKey("steps")
        assertThat(canonical).doesNotContain("accepted.example.test")
        assertThat(canonical).doesNotContain("not-snapshotted")

        val pending = PendingScheduledExportRequest(
            date = LocalDate.parse("2026-07-01"),
            lastFailureReason = ExportFailureReason.NETWORK_ERROR,
        )
        val current = ExportSettings(
            exportFormats = setOf(ExportFormat.JSON),
            apiEndpointUrl = "https://current.example.test/destination",
            scheduleEnabled = false,
            scheduleCadenceValue = 9,
            scheduleCadenceUnit = ScheduleCadenceUnit.WEEKS,
            pendingScheduledRetryDates = listOf("2026-07-01"),
            pendingScheduledExportRequests = listOf(pending),
        )

        val restored = decoded.restoreOnto(current)

        assertThat(restored.exportFormats).containsExactly(ExportFormat.CSV, ExportFormat.MARKDOWN)
        assertThat(restored.filenameFormat).isEqualTo("health-{date}-{weekday}")
        assertThat(restored.formatCustomization).isEqualTo(decoded.formatCustomization)
        assertThat(restored.metricSelection).isEqualTo(decoded.metricSelection)
        assertThat(restored.dailyNoteInjection).isEqualTo(decoded.dailyNoteInjection)
        assertThat(restored.individualTracking).isEqualTo(decoded.individualTracking)
        assertThat(restored.apiEndpointUrl).isEqualTo(current.apiEndpointUrl)
        assertThat(restored.scheduleEnabled).isFalse()
        assertThat(restored.scheduleCadenceValue).isEqualTo(9)
        assertThat(restored.scheduleCadenceUnit).isEqualTo(ScheduleCadenceUnit.WEEKS)
        assertThat(restored.pendingScheduledRetryDates).isEqualTo(current.pendingScheduledRetryDates)
        assertThat(restored.pendingScheduledExportRequests)
            .isEqualTo(current.pendingScheduledExportRequests)
        assertThat(restored.executionEnginePin).isNull()
        assertThat(restored.executionEngineAuthorityIsFrozen).isTrue()
    }

    @Test
    fun apiIdentityMustStillMatchBeforeCurrentEndpointPlumbingIsRetained() {
        val pin = syntheticExportEnginePin(
            mode = ExportEngineMode.shadow,
            profile = AndroidExportProfile.android_frozen_v4,
        )
        val accepted = ExportSettings(
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://api.example.test/v1/health",
        )
        val snapshot = AndroidExportSettingsSnapshot.capture(accepted, pin, zone)

        val matchingCurrent = accepted.copy(
            apiEndpointUrl = "  https://api.example.test/v1/health  ",
            filenameFormat = "changed-{date}",
        )
        assertThat(snapshot.restoreOnto(matchingCurrent).apiEndpointUrl)
            .isEqualTo(matchingCurrent.apiEndpointUrl)

        val mismatch = assertThrows(AndroidExportSettingsSnapshotException::class.java) {
            snapshot.restoreOnto(
                matchingCurrent.copy(apiEndpointUrl = "https://other.example.test/v1/health"),
            )
        }
        assertThat(mismatch.reason)
            .isEqualTo(AndroidExportSettingsSnapshotError.DESTINATION_MISMATCH)
    }

    @Test
    fun canonicalSizeBoundAndErrorsNeverEchoCapturedContent() {
        val marker = "private-template-marker"
        val oversized = ExportSettings(
            formatCustomization = FormatCustomization(
                markdownTemplate = MarkdownTemplateConfig(
                    style = MarkdownTemplateStyle.CUSTOM,
                    customTemplate = marker + "x".repeat(
                        AndroidExportSettingsSnapshotCodec.MAX_CANONICAL_JSON_BYTES,
                    ),
                ),
            ),
        )

        val error = assertThrows(AndroidExportSettingsSnapshotException::class.java) {
            AndroidExportSettingsSnapshot.capture(oversized, pin = null, zone = ZoneId.of("UTC"))
        }

        assertThat(error.reason)
            .isEqualTo(AndroidExportSettingsSnapshotError.SIZE_LIMIT_EXCEEDED)
        assertThat(error.message).doesNotContain(marker)
    }

    @Test
    fun structuralPinTimezoneAndProfileMismatchesFailClosed() {
        val frozenPin = syntheticExportEnginePin(
            mode = ExportEngineMode.rust,
            profile = AndroidExportProfile.android_frozen_v4,
        )
        val analyticalSettings = ExportSettings(
            formatCustomization = FormatCustomization.analyticalDefault(),
            scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
        )

        assertThrows(AndroidExportSettingsSnapshotException::class.java) {
            AndroidExportSettingsSnapshot.capture(analyticalSettings, frozenPin, zone)
        }
        assertThrows(AndroidExportSettingsSnapshotException::class.java) {
            AndroidExportSettingsSnapshot.capture(
                ExportSettings(),
                syntheticExportEnginePin(zoneId = "America/New_York"),
                zone,
            )
        }

        val valid = AndroidExportSettingsSnapshot.capture(
            ExportSettings(),
            syntheticExportEnginePin(),
            zone,
        )
        assertThat(
            AndroidExportSettingsSnapshotCodec.decodeOrNull(
                AndroidExportSettingsSnapshotCodec.encodeCanonical(valid)
                    .replace(
                        "\"ianaTimeZone\":\"America/Los_Angeles\"",
                        "\"ianaTimeZone\":\"America/New_York\"",
                    ),
            ),
        ).isNull()
        assertThat(
            AndroidExportSettingsSnapshotCodec.decodeOrNull(
                AndroidExportSettingsSnapshotCodec.encodeCanonical(valid)
                    .replace(
                        "\"exportProfile\":\"android_frozen_v4\"",
                        "\"exportProfile\":\"android_analytical_v5\"",
                    ),
            ),
        ).isNull()
    }
}
