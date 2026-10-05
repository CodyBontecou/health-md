package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.CoreRegistryMetric
import com.healthmd.data.export.JsonExporter
import com.healthmd.direct.protocol.*
import com.healthmd.domain.model.*
import java.io.File
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.junit.Test

class AgentBridgeRequestSettingsTest {
    private val clock = Clock.fixed(Instant.parse("2026-05-29T00:00:00Z"), ZoneId.of("UTC"))
    private val json = Json { encodeDefaults = true }

    @Test
    fun explicitJsonUsesNativeSelectionReducersAndYearLayout() {
        val result = resolve(intent(metrics = listOf("heart_rate_avg", "steps")))
        val settings = result.exporterSettings()
        assertThat(settings.exportFormats).containsExactly(ExportFormat.JSON)
        assertThat(settings.subfolder).isEmpty()
        assertThat(settings.folderStructure).isEqualTo("{year}")
        assertThat(settings.filenameFormat).isEqualTo("{date}")
        assertThat(result.predictedRelativePaths).containsExactly("2026/2026-03-07.json", "2026/2026-03-08.json").inOrder()
        assertThat(result.selection.map { it.semanticId }).containsExactly("heart_rate_avg", "steps").inOrder()
        assertThat(result.selection.map { it.nativeMetricId }).containsExactly("avg_hr", "steps").inOrder()
        assertThat(result.selection.map { it.nativeRecordType }).containsExactly(
            "androidx.health.connect.client.records.HeartRateRecord",
            "androidx.health.connect.client.records.StepsRecord",
        ).inOrder()
        assertThat(result.selection.map { it.sourceReducer }).containsExactly("average", "sum").inOrder()
        assertThat(result.selection.map { it.canonicalUnit }).containsExactly("bpm", "steps").inOrder()
        assertThat(settings.metricSelection.enabledMetrics).containsExactly("avg_hr", "steps")
        assertThat(settings.shouldFetchGranularData()).isFalse()
        assertThat(settings.executionEngineAuthorityIsFrozen).isTrue()
        assertThat(settings.executionEnginePin).isNull()
        assertThat(settings.apiEndpointUrl).isEmpty()
        assertThat(settings.scheduleEnabled).isFalse()
        assertThat(settings.pendingScheduledExportRequests).isEmpty()
        assertThat(result.calendarTimezone).isEqualTo("America/Los_Angeles")
        assertThat(result.resolvedAtEpochSecond).isEqualTo(clock.instant().epochSecond)
        assertThat(settings.formatCustomization.unitPreference).isEqualTo(UnitPreference.METRIC)
        assertThat(settings.formatCustomization.compatibilitySchemaProfile).isEqualTo(CompatibilitySchemaProfile.IOS_V4_FROZEN)
    }

    @Test
    fun futureRequestsFailuresDiscardAndResumeLeaveNativeBytesUnchanged() {
        val current = ExportSettings.newInstallDefaults().copy(
            apiEndpointUrl = "https://synthetic.invalid/never-contact",
            scheduleEnabled = true,
            subfolder = "unrelated",
            pendingScheduledRetryDates = listOf("2026-01-01"),
        )
        val before = json.encodeToString(current)
        val first = resolve(intent(), inputs(saved = AgentBridgeRequestSettingsSnapshot(9, current)))
        val durable = json.encodeToString(first)
        val next = resolve(intent(metrics = listOf("heart_rate_min"), folder = "next/{month}", filename = "day-{date}"))
        assertThat(next.exporterSettings().metricSelection.enabledMetrics).containsExactly("min_hr")
        expect(AgentBridgeErrorCode.UNSUPPORTED_METRIC) { resolve(intent(metrics = listOf("unknown.metric"))) }
        val resumed = json.decodeFromString<AgentBridgeRequestSettingsResolution>(durable)
        assertThat(resumed.exporterSettings()).isEqualTo(first.exporterSettings())
        assertThat(resumed.predictedRelativePaths).isEqualTo(first.predictedRelativePaths)
        val discarded = first.exporterSettings().copy(filenameFormat = "discarded", metricSelection = MetricSelectionState(emptySet()))
        assertThat(discarded.filenameFormat).isEqualTo("discarded")
        assertThat(resumed.exporterSettings().filenameFormat).isEqualTo("{date}")
        assertThat(json.encodeToString(current)).isEqualTo(before)
        assertThat(resumed.exporterSettings().apiEndpointUrl).isEmpty()
        assertThat(resumed.exporterSettings().scheduleEnabled).isFalse()
    }

    @Test
    fun configurationReuseRejectsChangedRequestCatalogAndSavedOutput() {
        val request = intent()
        val context = inputs()
        val frozen = resolve(request, context)
        AgentBridgeRequestSettingsResolver.validateForReuse(frozen, request, context)
        expect(AgentBridgeErrorCode.BINDING_CHANGED) {
            AgentBridgeRequestSettingsResolver.validateForReuse(frozen, intent(metrics = listOf("heart_rate_min")), context)
        }
        val changedCatalog = AgentBridgeRequestSettingsCatalog(registry(), setOf("steps"), 4)
        expect(AgentBridgeErrorCode.BINDING_CHANGED) {
            AgentBridgeRequestSettingsResolver.validateForReuse(frozen, request, context.copy(catalog = changedCatalog))
        }
        expect(AgentBridgeErrorCode.BINDING_CHANGED) {
            AgentBridgeRequestSettingsResolver.validateForReuse(frozen, request, inputs(available = setOf("steps", "min_hr")))
        }
        val savedRequest = intent(policy = AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings"))
        val native = frozen.exporterSettings()
        val savedContext = inputs(saved = AgentBridgeRequestSettingsSnapshot(2, native))
        val saved = resolve(savedRequest, savedContext)
        expect(AgentBridgeErrorCode.BINDING_CHANGED) {
            AgentBridgeRequestSettingsResolver.validateForReuse(saved, savedRequest, inputs(saved = AgentBridgeRequestSettingsSnapshot(2, native.copy(folderStructure = "changed/{year}"))))
        }
    }

    @Test
    fun callerOwnedCollectionsCannotMutateFrozenResolution() {
        val metricIds = mutableListOf("steps")
        val formats = mutableListOf(AgentBridgeFormat.JSON)
        val request = intent(output().copy(formats = formats)).let {
            it.copy(captureScope = it.captureScope.copy(selection = it.captureScope.selection.copy(metricIds = metricIds)))
        }
        val frozen = resolve(request)
        metricIds += "heart_rate_min"
        formats.clear()
        assertThat(frozen.exporterSettings().metricSelection.enabledMetrics).containsExactly("steps")
        assertThat(frozen.exporterSettings().exportFormats).containsExactly(ExportFormat.JSON)
        assertThat(frozen.selection.map { it.semanticId }).containsExactly("steps")
    }

    @Test
    fun savedAndProfileOutputIsRevisionBoundAndNeverInheritsDestinations() {
        val native = resolve(intent(folder = "saved/{year}")).exporterSettings().copy(
            includeGranularData = true,
            metricSelection = MetricSelectionState(setOf("hrv")),
            apiEndpointUrl = "https://synthetic.invalid/never-contact",
            exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            scheduleEnabled = true,
        )
        val before = json.encodeToString(native)
        val snapshot = AgentBridgeRequestSettingsSnapshot(7, native)
        val id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        val profile = AgentBridgeRequestSettingsProfile(id, snapshot, executionBlocked = false)
        val context = inputs(saved = snapshot, profiles = listOf(profile))
        val saved = resolve(intent(policy = AgentBridgeSettingsPolicySavedDeviceSettings(7, "saved_device_settings")), context)
        val fromProfile = resolve(intent(policy = AgentBridgeSettingsPolicyProfile(7, id, "profile")), context)
        for (result in listOf(saved, fromProfile)) {
            val settings = result.exporterSettings()
            assertThat(settings.folderStructure).isEqualTo("saved/{year}")
            assertThat(settings.metricSelection.enabledMetrics).containsExactly("steps")
            assertThat(settings.shouldFetchGranularData()).isFalse()
            assertThat(settings.apiEndpointUrl).isEmpty()
            assertThat(settings.exportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)
            assertThat(settings.scheduleEnabled).isFalse()
            assertThat(result.settingsRevision).isEqualTo(7)
        }
        assertThat(saved.settingsOrigin).isEqualTo(AgentBridgeRequestSettingsOrigin.SAVED_DEVICE_SETTINGS)
        assertThat(fromProfile.settingsOrigin).isEqualTo(AgentBridgeRequestSettingsOrigin.PROFILE)
        assertThat(fromProfile.profileId).isEqualTo(id)
        assertThat(json.encodeToString(native)).isEqualTo(before)
        expect(AgentBridgeErrorCode.REVISION_CONFLICT) { resolve(intent(policy = AgentBridgeSettingsPolicySavedDeviceSettings(8, "saved_device_settings")), context) }
        expect(AgentBridgeErrorCode.REVISION_CONFLICT) { resolve(intent(policy = AgentBridgeSettingsPolicyProfile(8, id, "profile")), context) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent(policy = AgentBridgeSettingsPolicySavedDeviceSettings(7, "saved_device_settings"))) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent(policy = AgentBridgeSettingsPolicyProfile(7, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "profile")), context) }
        expect(AgentBridgeErrorCode.NATIVE_REBIND_REQUIRED) { resolve(intent(policy = AgentBridgeSettingsPolicyProfile(7, id, "profile")), inputs(profiles = listOf(profile.copy(executionBlocked = true)))) }
    }

    @Test
    fun unsupportedAxesUnknownAndUnavailableIdsReject() {
        expect(AgentBridgeErrorCode.UNSUPPORTED_METRIC) { resolve(intent(metrics = listOf("hrv"))) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_METRIC) { resolve(intent(metrics = listOf("sleep_total"))) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_METRIC) { resolve(intent(metrics = emptyList())) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent().let { it.copy(captureScope = it.captureScope.copy(selection = it.captureScope.selection.copy(categoryIds = listOf("activity")))) }) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent().let { it.copy(captureScope = it.captureScope.copy(selection = it.captureScope.selection.copy(allMetrics = true))) }) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent().let { it.copy(captureScope = it.captureScope.copy(compatibilityDetail = AgentBridgeCompatibilityDetail.SELECTED_TIME_SERIES)) }) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent().let { it.copy(captureScope = it.captureScope.copy(nativeArchive = AgentBridgeArchiveAndroidProviderNativeSnapshotV1(AgentBridgeArchiveAndroidProviderNativeSnapshotV1Format.NDJSON, false, "health_connect", AgentBridgeArchiveAndroidProviderNativeSnapshotV1RecordScope.SELECTED, "android_provider_native_snapshot_v1"))) }) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent(output().let { it.copy(presentation = it.presentation.copy(displayUnits = AgentBridgePresentationDisplayUnits.IMPERIAL)) })) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent(output().let { it.copy(presentation = it.presentation.copy(locale = "fr-FR")) })) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent(output().copy(formats = listOf(AgentBridgeFormat.MARKDOWN)))) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent(output().copy(writeMode = AgentBridgeWriteMode.APPEND))) }
        expect(AgentBridgeErrorCode.UNSAFE_PATH) { resolve(intent(output().copy(folderTemplate = "../outside"))) }
        expect(AgentBridgeErrorCode.PATH_COLLISION) { resolve(intent(output().copy(filenameTemplate = "constant"))) }
        expect(AgentBridgeErrorCode.UNSUPPORTED_METRIC) { resolve(intent(), inputs(available = emptySet())) }
    }

    @Test
    fun everyUnsupportedOutputFlagAndCompanionFailsExplicitly() {
        val base = output()
        val variants = listOf(
            base.copy(presentation = base.presentation.copy(frontmatter = base.presentation.frontmatter.copy(enabledFieldIds = listOf("steps")))),
            base.copy(presentation = base.presentation.copy(frontmatter = base.presentation.frontmatter.copy(customFields = listOf(AgentBridgeFrontmatterCustomFieldsItem("note", "synthetic"))))),
            base.copy(presentation = base.presentation.copy(frontmatter = base.presentation.frontmatter.copy(includeUnits = false))),
            base.copy(presentation = base.presentation.copy(frontmatter = base.presentation.frontmatter.copy(includeCaptureDiagnostics = true))),
            base.copy(presentation = base.presentation.copy(markdown = base.presentation.markdown.copy(style = AgentBridgeMarkdownStyle.TABLES))),
            base.copy(individualEntries = base.individualEntries.copy(enabled = true)),
            base.copy(dailyNotes = base.dailyNotes.copy(enabled = true)),
            base.copy(packaging = AgentBridgePackagingZip("export", false, "healthmd.agent_artifact_manifest/1", 10, 100, "zip")),
            base.copy(dictionary = AgentBridgeDictionaryProfileDictionaryV1("dictionary", AgentBridgeDictionaryProfileDictionaryV1Format.JSON, "profile_dictionary_v1")),
            base.copy(outputProfile = AgentBridgeOutputProfile.ANDROID_ANALYTICAL_V5),
        )
        for (variant in variants) expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { resolve(intent(variant)) }
        val saved = resolve(intent()).exporterSettings().copy(individualTracking = IndividualTrackingSettings(globalEnabled = true))
        expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) {
            resolve(intent(policy = AgentBridgeSettingsPolicySavedDeviceSettings(1, "saved_device_settings")), inputs(saved = AgentBridgeRequestSettingsSnapshot(1, saved)))
        }
    }

    @Test
    fun civilDateDSTAllAvailableAndProductionPathsAgree() {
        val relative = resolve(intent().copy(dates = AgentBridgeDatesPastCompleteDays("2026-03-09", 2, "past_complete_days")))
        assertThat(relative.requestedDays).containsExactly("2026-03-07", "2026-03-08").inOrder()
        val settings = relative.exporterSettings()
        assertThat(relative.requestedDays.map { settings.aggregateRelativePath(LocalDate.parse(it), ExportFormat.JSON) })
            .isEqualTo(relative.predictedRelativePaths)
        val all = resolve(intent().copy(dates = AgentBridgeDatesAllAvailable("all_available")))
        assertThat(all.dates).isEqualTo(AgentBridgeDatesAllAvailable("all_available"))
        assertThat(all.requestedDays).isEmpty()
        assertThat(all.predictedRelativePaths).isEmpty()
    }

    @Test
    fun skippedCivilDaysRejectWithoutNarrowing() {
        expect(AgentBridgeErrorCode.INVALID_REQUEST) {
            resolve(intent().copy(calendarTimezone = "Pacific/Apia", dates = AgentBridgeDatesExact(AgentBridgeRange("2011-12-31", "2011-12-29"), "exact")))
        }
        expect(AgentBridgeErrorCode.INVALID_REQUEST) {
            resolve(intent().copy(dates = AgentBridgeDatesPastCompleteDays("0001-01-01", 1, "past_complete_days")))
        }
    }

    @Test
    fun nativeHrvAndReducersAreNotAliasesForAppleSdnn() {
        val result = resolve(intent(metrics = listOf("android.hrv_rmssd", "heart_rate_max", "heart_rate_min", "resting_heart_rate")))
        assertThat(result.selection.map { it.sourceReducer }).containsExactly("latest", "maximum", "minimum", "latest").inOrder()
        assertThat(result.selection.first().semanticId).isEqualTo("android.hrv_rmssd")
        assertThat(result.selection.first().nativeMetricId).isEqualTo("hrv")
        assertThat(result.selection.first().nativeRecordType).isEqualTo("androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord")
        val changed = registry().copy(registrySha256 = "0".repeat(64))
        expect(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeRequestSettingsCatalog(changed, setOf("steps"), 1) }
        val reducer = registry().let { it.copy(metrics = it.metrics.map { m -> if (m.selectionId == "steps") m.copy(sourceAggregation = "invented_reducer") else m }) }
        expect(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeRequestSettingsCatalog(reducer, setOf("steps"), 1) }
    }

    @Test
    fun productionJsonOmitsUnselectedAndMissingDataWithoutHiddenSeries() {
        val settings = resolve(intent()).exporterSettings()
        val synthetic = HealthData(LocalDate.of(2026, 3, 7), activity = ActivityData(steps = 123), heart = HeartData(averageHeartRate = 60.0))
        val filtered = synthetic.filtered(settings.effectiveDataTypeSelection()).filtered(settings.metricSelection)
        val bytes = JsonExporter().export(filtered, settings.formatCustomization, settings.shouldFetchGranularData())
        val tree = Json.parseToJsonElement(bytes).jsonObject
        assertThat(tree.getValue("activity").jsonObject.getValue("steps").jsonPrimitive.int).isEqualTo(123)
        assertThat(tree.keys).doesNotContain("heart")
        val empty = HealthData(LocalDate.of(2026, 3, 7)).filtered(settings.metricSelection)
        assertThat(Json.parseToJsonElement(JsonExporter().export(empty, settings.formatCustomization)).jsonObject.keys).doesNotContain("activity")
    }

    private fun resolve(value: AgentBridgeGeneratedIntent, inputs: AgentBridgeRequestSettingsInputs = inputs()): AgentBridgeRequestSettingsResolution =
        resolveDirectAgentBridgeRequestSettings(value, inputs, clock)

    private fun inputs(saved: AgentBridgeRequestSettingsSnapshot? = null, profiles: List<AgentBridgeRequestSettingsProfile> = emptyList(), available: Set<String> = setOf("steps", "avg_hr", "min_hr", "max_hr", "resting_hr", "hrv")) =
        AgentBridgeRequestSettingsInputs(AgentBridgeRequestSettingsCatalog(registry(), available, 3), saved, profiles)

    private fun expect(code: AgentBridgeErrorCode, block: () -> Any?) {
        try {
            block()
            throw AssertionError("Expected fixed failure")
        } catch (failure: AgentBridgeException) {
            assertThat(failure.code).isEqualTo(code)
            assertThat(failure.message).isEqualTo(code.name.lowercase(java.util.Locale.ROOT))
        }
    }

    private fun intent(settings: AgentBridgeOutputSettings = output(), metrics: List<String> = listOf("steps"), folder: String = settings.folderTemplate, filename: String = settings.filenameTemplate, policy: AgentBridgeSettingsPolicy = AgentBridgeSettingsPolicyExplicit(settings.copy(folderTemplate = folder, filenameTemplate = filename), "explicit")): AgentBridgeGeneratedIntent {
        val host = "11111111-1111-4111-8111-111111111111"
        return AgentBridgeGeneratedIntent("America/Los_Angeles", AgentBridgeCapture(AgentBridgeCompatibilityDetail.SUMMARY, AgentBridgeArchiveNone("none"), AgentBridgeSelection(false, emptyList(), metrics.sorted(), emptyList(), listOf("health_connect"))), AgentBridgeDatesExact(AgentBridgeRange("2026-03-08", "2026-03-07"), "exact"), AgentBridgeDestination("44444444-4444-4444-8444-444444444444", host, "a".repeat(64), 1), "22222222-2222-4222-8222-222222222222", AgentBridgePeer(host, AgentBridgePlatform.ANDROID, "33333333-3333-4333-8333-333333333333"), AgentBridgeGeneratedIntentProduct("generated_files"), "healthmd.agent_export_intent", 1, policy, "UTC")
    }

    private fun output() = AgentBridgeOutputSettings(
        AgentBridgeDailyNotes(false, false, "{date}", "", false, emptyList()), AgentBridgeDictionaryNone("none"), "{date}", "{year}", listOf(AgentBridgeFormat.JSON),
        AgentBridgeIndividualEntries(false, false, "{metric}-{date}", "", emptyList()), AgentBridgeOutputProfile.ANDROID_FROZEN_V4, AgentBridgePackagingLooseFiles("loose_files"),
        AgentBridgePresentation(AgentBridgePresentationDisplayUnits.METRIC, AgentBridgeFrontmatter(emptyList(), emptyList(), false, true), true, true, "en-US", "canonical", AgentBridgeMarkdown("", emptyList(), AgentBridgeMarkdownStyle.LISTS)), "", AgentBridgeWriteMode.OVERWRITE,
    )

    /** The actual frozen registry is the fixture authority; no labels or guessed semantic aliases. */
    private fun registry(): CoreMetricRegistrySnapshot {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        var file: File? = null
        while (directory != null && file == null) {
            val candidate = File(directory, "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json")
            if (candidate.isFile) file = candidate else directory = directory.parentFile
        }
        val root = Json.parseToJsonElement(requireNotNull(file).readText()).jsonObject
        val profile = root.getValue("profiles").jsonArray.map { it.jsonObject }.single { it.getValue("id").jsonPrimitive.content == "android_frozen_v4" }
        val metrics = root.getValue("metrics").jsonArray.mapNotNull { element ->
            val row = element.jsonObject
            val native = row.getValue("android").jsonObject
            if (native.getValue("status").jsonPrimitive.content != "backed") return@mapNotNull null
            fun text(key: String) = native.getValue(key).jsonPrimitive.content
            CoreRegistryMetric(row.getValue("semantic_id").jsonPrimitive.content, text("selection_id"), text("label_key"), row.getValue("reference_name").jsonPrimitive.content, text("category_id"), text("unit"), "captured", text("source_aggregation"), text("default_enabled").toBoolean(), false, text("availability_key"), "health_connect", row.getValue("capability_id").jsonPrimitive.content, text("selection_id"), native.getValue("related_semantic_ids").jsonArray.map { it.jsonPrimitive.content }, text("ordinal").toUInt())
        }.sortedBy { it.ordinal }
        fun profileText(key: String) = profile.getValue(key).jsonPrimitive.content
        return CoreMetricRegistrySnapshot(root.getValue("registry_version").jsonPrimitive.content.toUInt(), HEALTHMD_CORE_REGISTRY_SHA256, "android_frozen_v4", profileText("public_profile_id"), profileText("public_schema"), profileText("public_schema_version").toUInt(), profileText("profile_revision").toUInt(), emptyList(), metrics, emptyList(), emptyList())
    }
}
