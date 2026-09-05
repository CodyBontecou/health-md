package com.healthmd.sharedsetup

import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfilePendingExport
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MarkdownTemplateConfig
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.MetricTrackingConfig
import com.healthmd.domain.model.RawSnapshotSettings
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawSnapshotScope
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedSetupV2CodecMapperTest {
    private val registry = FixtureRegistry
    private val codec = SharedSetupV2Codec(registry)
    private val mapper = SharedSetupV2Mapper(registry)
    private val json = Json { explicitNulls = true }

    @Test
    fun `all ordered profiles map both modes raw options legacy filters and active profile deterministically`() {
        val fixture = mappedFixture()
        val document = fixture.document

        assertEquals(listOf("profile-001", "profile-002"), document.profiles.map { it.bundleId })
        assertEquals(listOf("Alpha", "Beta"), document.profiles.map { it.name })
        assertEquals("profile-002", document.activeProfile)
        assertEquals(
            listOf(
                "android.hrv_rmssd",
                "blood_pressure_diastolic",
                "blood_pressure_systolic",
                "heart_rate_avg",
                "steps",
            ),
            document.metricAliases.map { it.semanticId },
        )

        val compatibility = document.profiles[0]
        val compatibilityExtension = requireNotNull(compatibility.platformExtensions.android).export
        assertEquals("compatibility", compatibilityExtension.mode)
        assertEquals("markdown", compatibilityExtension.legacyPrimaryFormat)
        assertEquals("frozen_v4", compatibilityExtension.compatibilityProfile)
        assertFalse(compatibilityExtension.includeLegacyAliases)
        assertFalse(compatibilityExtension.includeAndroidNativeFields)
        assertEquals("ndjson", compatibilityExtension.rawSnapshot.format)
        assertEquals("selected_record_types", compatibilityExtension.rawSnapshot.scope)
        assertTrue(compatibilityExtension.rawSnapshot.includeExerciseRoutes)
        assertEquals(1, compatibilityExtension.rawSnapshot.pageSize)
        assertEquals("by_year_month", compatibilityExtension.folderOrganization)
        assertEquals("health/compatibility", compatibilityExtension.subfolder)
        assertEquals(DataTypeSelection(), compatibilityExtension.legacyDataTypes.toNativeSelection())
        assertEquals("summary", compatibility.export.compatibilityDetail)
        assertEquals("device_folder", compatibility.destination.kind)
        assertNull(compatibility.destination.apiEndpoint)
        assertEquals("2025-02-03", compatibility.schedule?.cadence?.anchorDate)
        assertEquals("months", compatibility.schedule?.cadence?.unit)
        assertEquals(2, compatibility.schedule?.cadence?.value)
        assertFalse(requireNotNull(compatibility.schedule).activationRequested)
        assertEquals(4, compatibility.schedule.localTime.hour)
        assertEquals(35, compatibility.schedule.localTime.minute)
        assertEquals(5, compatibility.schedule.weekday)
        assertEquals(7, compatibility.schedule.lookbackDays)

        val raw = document.profiles[1]
        val rawExtension = requireNotNull(raw.platformExtensions.android).export
        assertEquals("raw_snapshot", rawExtension.mode)
        assertEquals("csv", rawExtension.legacyPrimaryFormat)
        assertEquals("analytical_v5", rawExtension.compatibilityProfile)
        assertTrue(rawExtension.includeLegacyAliases)
        assertTrue(rawExtension.includeAndroidNativeFields)
        assertEquals("json", rawExtension.rawSnapshot.format)
        assertEquals("all_authorized_supported_data", rawExtension.rawSnapshot.scope)
        assertFalse(rawExtension.rawSnapshot.includeExerciseRoutes)
        assertEquals(5_000, rawExtension.rawSnapshot.pageSize)
        assertEquals("by_month", rawExtension.folderOrganization)
        assertEquals("raw", rawExtension.subfolder)
        assertEquals(fixture.alternatingDataTypes, rawExtension.legacyDataTypes.toNativeSelection())
        assertEquals("selected_time_series", raw.export.compatibilityDetail)
        assertEquals("api_endpoint", raw.destination.kind)
        assertEquals("setup.invalid", raw.destination.apiEndpoint?.host)
        assertEquals(8_443, raw.destination.apiEndpoint?.port)
        assertEquals("/upload", raw.destination.apiEndpoint?.path)
        assertTrue(raw.destination.apiEndpoint?.queryOmitted == true)
        assertNull(raw.platformExtensions.apple)

        // Every per-metric row participates in the alias union even when disabled.
        assertFalse(requireNotNull(compatibility.individualEntries.metrics["heart_rate_avg"]).enabled)
        assertTrue(requireNotNull(compatibility.individualEntries.metrics["blood_pressure_systolic"]).enabled)
        assertTrue(requireNotNull(compatibility.individualEntries.metrics["blood_pressure_diastolic"]).enabled)
        assertEquals(
            "entries/vitals",
            compatibility.individualEntries.metrics["blood_pressure_systolic"]?.customFolder,
        )
        assertTrue("heart_rate_avg" in document.metricAliases.map { it.semanticId })

        val encoded = codec.encode(document)
        assertTrue(encoded.last() == '\n'.code.toByte())
        assertFalse(encoded.dropLast(1).last() == '\n'.code.toByte())
        val second = mapper.export(
            profiles = fixture.profiles,
            activeProfileId = fixture.profiles[1].id,
            schedules = fixture.schedules.reversed(),
            appVersion = APP_VERSION,
            preservedAppleExtensionsByProfileId = mapOf(fixture.profiles[0].id to APPLE_ARCHIVE_EXTENSION),
        )
        assertArrayEquals(encoded, codec.encode(second))
        assertCanonicalObjectKeys(json.parseToJsonElement(encoded.decodeToString()))

        // Nulls are explicit and typed decoding never re-exports unknown input.
        val encodedRoot = json.parseToJsonElement(encoded.decodeToString()).jsonObject
        val encodedProfiles = encodedRoot.getValue("profiles") as JsonArray
        assertEquals(JsonNull, encodedProfiles[0].jsonObject.getValue("destination").jsonObject["api_endpoint"])
        assertEquals(JsonNull, encodedProfiles[1].jsonObject.getValue("platform_extensions").jsonObject["apple"])
        val decoded = requireV2(codec.decode(encoded))
        assertArrayEquals(encoded, codec.encode(decoded))

        val text = encoded.decodeToString()
        listOf(
            PROFILE_ALPHA_ID,
            PROFILE_BETA_ID,
            "content://com.android.externalstorage.documents/tree/primary%3AHealth",
            "Family Health folder",
            "pending-native-operation",
            "America/Los_Angeles",
            "tenant=private",
            "settingsSnapshotJson",
            "destination_fingerprint",
            "engine_pin",
            "folder_uri",
            "createdAtEpochMillis",
        ).forEach { prohibited ->
            assertFalse("v2 output leaked prohibited state: $prohibited", text.contains(prohibited))
        }
        assertFalse(text.contains("cloud"))
    }

    @Test
    fun `raw mode never becomes Apple archive and foreign Apple meaning is preserved exactly`() {
        val fixture = mappedFixture()
        val document = fixture.document
        val archiveOnly = document.profiles[0]
        val raw = document.profiles[1]

        assertEquals("summary", archiveOnly.export.compatibilityDetail)
        assertEquals(
            "canonical_v1",
            archiveOnly.platformExtensions.apple?.export?.healthkitSourceArchive,
        )
        assertEquals("selected_time_series", raw.export.compatibilityDetail)
        assertNull(raw.platformExtensions.apple)

        val withoutPreservation = mapper.export(
            profiles = fixture.profiles,
            activeProfileId = fixture.profiles[1].id,
            schedules = fixture.schedules,
            appVersion = APP_VERSION,
        )
        assertTrue(withoutPreservation.profiles.all { it.platformExtensions.apple == null })
        assertEquals(
            "raw_snapshot",
            withoutPreservation.profiles[1].platformExtensions.android?.export?.mode,
        )

        val plan = mapper.planImport(document)
        val plannedArchive = plan.profiles[0]
        assertEquals(APPLE_ARCHIVE_EXTENSION, plannedArchive.preservedAppleExtension)
        assertFalse(requireNotNull(plannedArchive.scheduleIntent).importedEnabled)
        assertTrue(plannedArchive.destinationIntent.requiresLocalRebinding)
        assertTrue(plannedArchive.compatibility.any {
            it.status == SharedSetupV2CompatibilityStatus.UNSUPPORTED &&
                it.field.endsWith("platform_extensions.apple") &&
                it.detail.contains("canonical_v1")
        })
    }

    @Test
    fun `dispatch is lexical integer strict fails closed on v1 and never reexports bounded unknown fields`() {
        val document = mappedFixture().document
        val encoded = codec.encode(document)
        val root = json.parseToJsonElement(encoded.decodeToString()).jsonObject

        assertTrue(codec.decode(encoded) is SharedSetupVersionedDecodeResult.Valid)
        listOf<JsonElement>(
            JsonPrimitive("1"),
            JsonPrimitive(2.0),
            JsonPrimitive(true),
            JsonNull,
            JsonPrimitive(3),
        ).forEach { invalidVersion ->
            val candidate = root.replacing("schema_version", invalidVersion).encoded()
            assertTrue(codec.decode(candidate) is SharedSetupVersionedDecodeResult.Invalid)
        }
        assertTrue(
            codec.decode(root.replacing("schema", JsonPrimitive(2)).encoded())
                is SharedSetupVersionedDecodeResult.Invalid,
        )

        // The pre-canonical v1 contract is gone: minimal v1-shaped bytes (synthesized inline,
        // never read from the deleted v1 contract fixtures) must fail closed with the bounded
        // unsupported-version message before any typed decoding occurs — including padded v1
        // payloads of any size under the public 4 MiB bound.
        val minimalV1 = """{"schema":"healthmd.shared_setup","schema_version":1}"""
            .encodeToByteArray()
        val minimalV1Result = codec.decode(minimalV1)
        assertTrue(minimalV1Result is SharedSetupVersionedDecodeResult.Invalid)
        assertEquals(
            "This shared setup version is not supported.",
            (minimalV1Result as SharedSetupVersionedDecodeResult.Invalid).message,
        )
        val paddedV1 = ByteArray(SHARED_SETUP_V2_MAX_BYTES) { ' '.code.toByte() }.also {
            minimalV1.copyInto(it)
        }
        assertTrue(codec.decode(paddedV1) is SharedSetupVersionedDecodeResult.Invalid)

        val boundedUnknown = JsonObject(
            root + (
                "future_optional" to JsonObject(
                    mapOf("bounded_meaning" to JsonPrimitive("ignored")),
                )
                ),
        ).encoded()
        val decodedWithUnknown = requireV2(codec.decode(boundedUnknown))
        val reencoded = codec.encode(decodedWithUnknown).decodeToString()
        assertFalse(reencoded.contains("future_optional"))
        assertFalse(reencoded.contains("bounded_meaning"))
    }

    @Test
    fun `generic preflight enforces depth container scalar node and profile bounds before typed decode`() {
        val document = mappedFixture().document
        val encoded = codec.encode(document)
        val root = json.parseToJsonElement(encoded.decodeToString()).jsonObject

        var nested: JsonElement = JsonPrimitive(true)
        repeat(SharedSetupV2Codec.MAX_JSON_DEPTH + 1) {
            nested = JsonObject(mapOf("next" to nested))
        }
        assertTrue(
            codec.decode(JsonObject(root + ("future_optional" to nested)).encoded())
                is SharedSetupVersionedDecodeResult.Invalid,
        )

        val tooManyItems = JsonArray(
            List(SharedSetupV2Codec.MAX_JSON_CONTAINER_SIZE + 1) { JsonPrimitive(it) },
        )
        assertTrue(
            codec.decode(JsonObject(root + ("future_optional" to tooManyItems)).encoded())
                is SharedSetupVersionedDecodeResult.Invalid,
        )

        val tooLong = JsonPrimitive("x".repeat(SharedSetupV2Codec.MAX_JSON_STRING_SCALARS + 1))
        assertTrue(
            codec.decode(JsonObject(root + ("future_optional" to tooLong)).encoded())
                is SharedSetupVersionedDecodeResult.Invalid,
        )

        val nodeDense = JsonArray(
            List(SharedSetupV2Codec.MAX_JSON_CONTAINER_SIZE) {
                JsonArray(List(SharedSetupV2Codec.MAX_JSON_CONTAINER_SIZE) { JsonNull })
            },
        )
        val nodeDenseBytes = JsonObject(root + ("future_optional" to nodeDense)).encoded()
        assertTrue(nodeDenseBytes.size < SHARED_SETUP_V2_MAX_BYTES)
        assertTrue(codec.decode(nodeDenseBytes) is SharedSetupVersionedDecodeResult.Invalid)

        val base = document.profiles.first().copy(schedule = null)
        val hundredProfiles = List(SHARED_SETUP_V2_MAX_PROFILES) { index ->
            base.copy(
                bundleId = SharedSetupV2Codec.bundleIdForIndex(index),
                name = "Profile ${index + 1}",
            )
        }
        val hundred = document.copy(
            profiles = hundredProfiles,
            activeProfile = "profile-100",
            metricAliases = document.metricAliases.filter {
                it.semanticId in (base.metrics.enabledIds + base.individualEntries.metrics.keys)
            },
        )
        codec.encode(hundred)
        assertThrows(IllegalArgumentException::class.java) {
            codec.encode(
                hundred.copy(
                    profiles = hundred.profiles + base.copy(
                        bundleId = "profile-101",
                        name = "Profile 101",
                    ),
                ),
            )
        }
    }

    @Test
    fun `security and structural validation reject prohibited state paths aliases identities and contradictions`() {
        val document = mappedFixture().document
        val encoded = codec.encode(document)
        val root = json.parseToJsonElement(encoded.decodeToString()).jsonObject

        listOf(
            JsonObject(root + ("operation_id" to JsonPrimitive("native-work"))),
            JsonObject(root + ("headers" to JsonObject(mapOf("X-Secret" to JsonPrimitive("value"))))),
            JsonObject(root + ("future_optional" to JsonPrimitive("content://provider/private"))),
            JsonObject(root + ("future_optional" to JsonPrimitive("Bearer synthetic-secret"))),
            JsonObject(root + ("future_optional" to JsonPrimitive(PROFILE_ALPHA_ID))),
            JsonObject(root + ("future_optional" to JsonPrimitive("/Users/example/Health"))),
        ).forEach { unsafe ->
            assertTrue(codec.decode(unsafe.encoded()) is SharedSetupVersionedDecodeResult.Invalid)
        }

        assertRejects(document.copy(activeProfile = "profile-099"))
        assertRejects(
            document.copy(
                profiles = document.profiles.mapIndexed { index, profile ->
                    if (index == 0) profile.copy(bundleId = "profile-002") else profile
                },
            ),
        )
        assertRejects(
            document.copy(
                profiles = listOf(
                    document.profiles[0].copy(name = "Duplicate"),
                    document.profiles[1].copy(name = "duplicate"),
                ),
            ),
        )
        assertRejects(document.copy(metricAliases = document.metricAliases.dropLast(1)))
        assertRejects(
            document.copy(
                profiles = document.profiles.mapIndexed { index, profile ->
                    if (index == 0) {
                        profile.copy(export = profile.export.copy(folderTemplate = "../escape"))
                    } else {
                        profile
                    }
                },
            ),
        )
        assertRejects(
            document.copy(
                profiles = document.profiles.mapIndexed { index, profile ->
                    if (index == 0) {
                        profile.copy(
                            destination = SharedSetupV2Destination(
                                kind = "device_folder",
                                apiEndpoint = document.profiles[1].destination.apiEndpoint,
                            ),
                        )
                    } else {
                        profile
                    }
                },
            ),
        )
        assertRejects(
            document.copy(
                profiles = document.profiles.mapIndexed { index, profile ->
                    if (index == 0) {
                        profile.copy(
                            platformExtensions = profile.platformExtensions.copy(android = null),
                        )
                    } else {
                        profile
                    }
                },
            ),
        )

        val appleAuthored = document.copy(
            createdBy = document.createdBy.copy(platform = "apple"),
            profiles = document.profiles.mapIndexed { index, profile ->
                val apple = if (index == 0) {
                    APPLE_ARCHIVE_EXTENSION
                } else {
                    APPLE_ARCHIVE_EXTENSION.copy(schedule = null)
                }
                profile.copy(
                    platformExtensions = profile.platformExtensions.copy(apple = apple),
                )
            },
        )
        codec.encode(appleAuthored)
        val contradictoryApple = appleAuthored.copy(
            profiles = appleAuthored.profiles.mapIndexed { index, profile ->
                if (index == 0) {
                    profile.copy(
                        platformExtensions = profile.platformExtensions.copy(
                            apple = requireNotNull(profile.platformExtensions.apple).copy(
                                schedule = SharedSetupV2AppleSchedule(
                                    frequency = "weekly",
                                    customUnit = "weeks",
                                    todayRefreshRequested = false,
                                    todayRefreshIntervalHours = 3,
                                ),
                            ),
                        ),
                    )
                } else {
                    profile
                }
            },
        )
        assertRejects(contradictoryApple)
    }

    @Test
    fun `import plan reports unavailable semantics and preserves typed unsupported extensions without approximation`() {
        val original = mappedFixture().document
        val first = original.profiles.first()
        val withAppleOnlyMetric = original.copy(
            profiles = listOf(
                first.copy(
                    metrics = SharedSetupV2Metrics(
                        (first.metrics.enabledIds + "hrv").distinct().sorted(),
                    ),
                ),
                original.profiles[1],
            ),
            metricAliases = (original.metricAliases + FixtureRegistry.alias("hrv"))
                .sortedBy { it.semanticId },
        )
        val decoded = requireV2(codec.decode(codec.encode(withAppleOnlyMetric)))

        val plan = mapper.planImport(decoded)

        assertEquals("profile-002", plan.activeProfile)
        assertEquals(listOf("hrv"), plan.profiles.first().unavailableMetricIds)
        assertFalse("hrv" in plan.profiles.first().supportedMetricIds)
        assertEquals(APPLE_ARCHIVE_EXTENSION, plan.profiles.first().preservedAppleExtension)
        assertTrue(plan.profiles.first().compatibility.any {
            it.status == SharedSetupV2CompatibilityStatus.REQUIRES_ACTION &&
                it.field.endsWith("metrics")
        })
        assertTrue(plan.profiles.all { profile ->
            profile.scheduleIntent?.importedEnabled != true &&
                profile.destinationIntent.requiresLocalRebinding
        })
    }

    @Test
    fun `eventual canonical v2 fixture paths decode when contract fixtures are present`() {
        val paths = listOf(
            "packages/contracts/shared-setup/v2/fixtures/apple-shared-setup-v2.json",
            "packages/contracts/shared-setup/v2/fixtures/android-shared-setup-v2.json",
        )
        paths.forEach { path ->
            val fixture = requireNotNull(contractFileOrNull(path)) {
                "Canonical Shared Setup v2 fixture is missing: $path"
            }
            val fixtureBytes = fixture.readBytes()
            val decoded = codec.decode(fixtureBytes)
            assertTrue("Canonical fixture failed to decode: $fixture", decoded is SharedSetupVersionedDecodeResult.Valid)
            val valid = decoded as SharedSetupVersionedDecodeResult.Valid
            assertEquals(
                "Canonical fixture was not v2: $fixture",
                SHARED_SETUP_V2_VERSION,
                valid.document.schemaVersion,
            )
            val document = valid.document
            assertArrayEquals(fixtureBytes, codec.encode(document))
        }
        assertTrue(codec.decode(codec.encode(mappedFixture().document)) is SharedSetupVersionedDecodeResult.Valid)
    }

    private fun mappedFixture(): MappedFixture {
        val minimalFrontmatter = FrontmatterConfiguration(
            fields = emptyList(),
            customFields = mapOf("profile_label" to "Synthetic"),
            placeholderFields = listOf("reflection"),
        )
        val compatibilityCustomization = FormatCustomization(
            includeLegacyAndroidAliases = false,
            includeAndroidNativeFields = false,
            compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
            frontmatterConfig = minimalFrontmatter,
            markdownTemplate = MarkdownTemplateConfig(
                style = MarkdownTemplateStyle.CUSTOM,
                customTemplate = "# Health — {{date}}\n{{#activity}}{{activity_metrics}}{{/activity}}",
            ),
        )
        val compatibilitySettings = ExportSettings.newInstallDefaults().copy(
            exportMode = ExportMode.COMPATIBILITY,
            rawSnapshot = RawSnapshotSettings(
                format = RawExportFormat.NDJSON,
                scope = RawSnapshotScope.SELECTED_RECORD_TYPES,
                includeExerciseRoutes = true,
                pageSize = 1,
            ),
            dataTypes = DataTypeSelection(),
            exportFormat = ExportFormat.MARKDOWN,
            exportFormats = setOf(ExportFormat.MARKDOWN, ExportFormat.JSON),
            filenameFormat = "health-{date}",
            folderStructure = "Health/{year}/{month}",
            formatCustomization = compatibilityCustomization,
            metricSelection = MetricSelectionState(setOf("steps")),
            individualTracking = IndividualTrackingSettings(
                globalEnabled = true,
                enabledMetrics = setOf("blood_pressure"),
                metricConfigs = mapOf(
                    "avg_hr" to MetricTrackingConfig(
                        trackIndividually = false,
                        customFolder = "entries/heart",
                    ),
                    "blood_pressure" to MetricTrackingConfig(
                        trackIndividually = true,
                        customFolder = "entries/vitals",
                    ),
                ),
                entriesFolder = "entries",
                organizeByCategory = true,
                filenameTemplate = "{metric}-{date}-{time}",
            ),
            includeGranularData = false,
            subfolder = "health/compatibility",
            folderOrganization = FolderOrganization.BY_YEAR_MONTH,
        )
        val alternating = DataTypeSelection(
            sleep = false,
            activity = true,
            heart = false,
            vitals = true,
            body = false,
            nutrition = true,
            mobility = false,
            reproductiveHealth = true,
            mindfulness = false,
            workouts = true,
            plannedWorkouts = false,
            medicalResources = true,
        )
        val rawCustomization = compatibilityCustomization.copy(
            includeLegacyAndroidAliases = true,
            includeAndroidNativeFields = true,
            compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
        )
        val rawSettings = compatibilitySettings.copy(
            exportMode = ExportMode.RAW_SNAPSHOT,
            rawSnapshot = RawSnapshotSettings(
                format = RawExportFormat.JSON,
                scope = RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA,
                includeExerciseRoutes = false,
                pageSize = 5_000,
            ),
            dataTypes = alternating,
            exportFormat = ExportFormat.CSV,
            exportFormats = setOf(ExportFormat.CSV),
            formatCustomization = rawCustomization,
            metricSelection = MetricSelectionState(setOf("hrv")),
            individualTracking = IndividualTrackingSettings(),
            includeGranularData = true,
            subfolder = "raw",
            folderOrganization = FolderOrganization.BY_MONTH,
        )
        val alpha = profile(
            id = PROFILE_ALPHA_ID,
            name = "  Alpha  ",
            settings = compatibilitySettings,
            target = ExportTarget.DEVICE_FOLDER,
            folderUri = "content://com.android.externalstorage.documents/tree/primary%3AHealth",
            folderDisplayName = "Family Health folder",
        )
        val beta = profile(
            id = PROFILE_BETA_ID,
            name = "Beta",
            settings = rawSettings,
            target = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://setup.invalid:8443/upload?tenant=private",
        )
        val schedule = ScheduledProfileEntry(
            profileId = PROFILE_ALPHA_ID,
            isEnabled = false,
            anchorEpochDay = LocalDate.parse("2025-02-03").toEpochDay(),
            weekdayIso = 5,
            hour = 4,
            minute = 35,
            cadenceValue = 2,
            cadenceUnit = ScheduledProfileCadenceUnit.MONTH,
            lookbackDays = 7,
            zoneId = "America/Los_Angeles",
            lastSuccessEpochMillis = 1_712_345_678_901,
            lastRefreshSuccessEpochMillis = 1_712_345_678_902,
            pendingExports = listOf(
                ScheduledProfilePendingExport(
                    id = "pending-native-identity",
                    ownerEpochDays = listOf(LocalDate.parse("2025-02-01").toEpochDay()),
                    fireAtMillis = 1_712_345_678_903,
                    settingsSnapshotJson = alpha.settingsSnapshotJson,
                    target = ExportTarget.DEVICE_FOLDER,
                    profileName = "Alpha",
                    folderUri = alpha.folderUri,
                    folderDisplayName = alpha.folderDisplayName,
                    durableOperationId = "pending-native-operation",
                ),
            ),
        )
        val profiles = listOf(alpha, beta)
        val schedules = listOf(schedule)
        val document = mapper.export(
            profiles = profiles,
            activeProfileId = PROFILE_BETA_ID,
            schedules = schedules,
            appVersion = APP_VERSION,
            preservedAppleExtensionsByProfileId = mapOf(PROFILE_ALPHA_ID to APPLE_ARCHIVE_EXTENSION),
        )
        return MappedFixture(document, profiles, schedules, alternating)
    }

    private fun profile(
        id: String,
        name: String,
        settings: ExportSettings,
        target: ExportTarget,
        apiEndpointUrl: String? = null,
        folderUri: String? = null,
        folderDisplayName: String? = null,
    ): ExportProfile {
        val scoped = settings.copy(
            exportTarget = target,
            scheduledExportTarget = target,
            apiEndpointUrl = apiEndpointUrl.orEmpty(),
        )
        val snapshot = AndroidExportSettingsSnapshot.capture(
            settings = scoped,
            pin = null,
            zone = ZoneId.of("America/Los_Angeles"),
        )
        return ExportProfile(
            id = id,
            name = name,
            settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot),
            target = target,
            apiEndpointUrl = apiEndpointUrl,
            folderUri = folderUri,
            folderDisplayName = folderDisplayName,
            isMigrationDefault = true,
            createdAtEpochMillis = 1_700_000_000_001,
            updatedAtEpochMillis = 1_700_000_000_002,
        )
    }

    private fun SharedSetupV2AndroidLegacyDataTypes.toNativeSelection(): DataTypeSelection =
        DataTypeSelection(
            sleep = sleep,
            activity = activity,
            heart = heart,
            vitals = vitals,
            body = body,
            nutrition = nutrition,
            mobility = mobility,
            reproductiveHealth = reproductiveHealth,
            mindfulness = mindfulness,
            workouts = workouts,
            plannedWorkouts = plannedWorkouts,
            medicalResources = medicalResources,
        )

    private fun requireV2(result: SharedSetupVersionedDecodeResult): SharedSetupV2 {
        assertTrue(result is SharedSetupVersionedDecodeResult.Valid)
        return (result as SharedSetupVersionedDecodeResult.Valid).document
    }

    private fun assertRejects(document: SharedSetupV2) {
        assertThrows(IllegalArgumentException::class.java) { codec.encode(document) }
    }

    private fun JsonObject.replacing(key: String, value: JsonElement): JsonObject =
        JsonObject(toMutableMap().apply { this[key] = value })

    private fun JsonObject.encoded(): ByteArray = toString().encodeToByteArray()

    private fun assertCanonicalObjectKeys(element: JsonElement) {
        when (element) {
            is JsonObject -> {
                assertEquals(element.keys.sorted(), element.keys.toList())
                element.values.forEach(::assertCanonicalObjectKeys)
            }
            is JsonArray -> element.forEach(::assertCanonicalObjectKeys)
            else -> Unit
        }
    }

    private fun contractFile(path: String): File = contractFileOrNull(path)
        ?: error("Could not locate $path")

    private fun contractFileOrNull(path: String): File? {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (true) {
            val candidate = File(directory, path)
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: return null
        }
    }

    private data class MappedFixture(
        val document: SharedSetupV2,
        val profiles: List<ExportProfile>,
        val schedules: List<ScheduledProfileEntry>,
        val alternatingDataTypes: DataTypeSelection,
    )

    private object FixtureRegistry : SharedSetupMetricRegistry {
        override val version: Int = 1
        override val sha256: String = "a".repeat(64)
        private val bindings = listOf(
            SharedSetupRegistryBinding(
                semanticId = "android.hrv_rmssd",
                appleSelectionId = null,
                androidSelectionId = "hrv",
                equivalence = "platform_distinct",
            ),
            SharedSetupRegistryBinding(
                semanticId = "blood_pressure_diastolic",
                appleSelectionId = "blood_pressure_diastolic",
                androidSelectionId = "bp_diastolic",
                equivalence = "mapped_alias",
            ),
            SharedSetupRegistryBinding(
                semanticId = "blood_pressure_systolic",
                appleSelectionId = "blood_pressure_systolic",
                androidSelectionId = "bp_systolic",
                equivalence = "mapped_alias",
            ),
            SharedSetupRegistryBinding(
                semanticId = "heart_rate_avg",
                appleSelectionId = "heart_rate_avg",
                androidSelectionId = "avg_hr",
                equivalence = "mapped_alias",
            ),
            SharedSetupRegistryBinding(
                semanticId = "hrv",
                appleSelectionId = "hrv",
                androidSelectionId = null,
                equivalence = "platform_exact_or_unavailable",
            ),
            SharedSetupRegistryBinding(
                semanticId = "steps",
                appleSelectionId = "steps",
                androidSelectionId = "steps",
                equivalence = "platform_exact_or_unavailable",
            ),
        )
        override val bySemanticId: Map<String, SharedSetupRegistryBinding> =
            bindings.associateBy { it.semanticId }
        override val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding> =
            bindings.mapNotNull { binding ->
                binding.androidSelectionId?.let { it to binding }
            }.toMap()

        fun alias(semanticId: String): SharedSetupV2MetricAlias {
            val binding = requireNotNull(bySemanticId[semanticId])
            return SharedSetupV2MetricAlias(
                semanticId = binding.semanticId,
                equivalence = binding.equivalence,
                appleSelectionId = binding.appleSelectionId,
                androidSelectionId = binding.androidSelectionId,
            )
        }
    }

    companion object {
        private const val PROFILE_ALPHA_ID = "123e4567-e89b-42d3-a456-426614174000"
        private const val PROFILE_BETA_ID = "123e4567-e89b-42d3-a456-426614174001"
        private const val APP_VERSION = "1.8.8-synthetic"
        private val APPLE_ARCHIVE_EXTENSION = SharedSetupV2AppleExtension(
            extensionVersion = SHARED_SETUP_V2_VERSION,
            export = SharedSetupV2AppleExport(
                organizeFormatsIntoFolders = true,
                archiveFiles = false,
                includeDataDictionary = true,
                summaryOnly = false,
                healthkitSourceArchive = "canonical_v1",
                generateRangeSummary = true,
            ),
            dailyNotes = SharedSetupV2AppleDailyNotes(only = false),
            schedule = SharedSetupV2AppleSchedule(
                frequency = "custom",
                customUnit = "months",
                todayRefreshRequested = false,
                todayRefreshIntervalHours = 6,
            ),
        )
    }
}
