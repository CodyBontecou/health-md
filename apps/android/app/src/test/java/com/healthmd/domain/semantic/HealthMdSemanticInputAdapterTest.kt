package com.healthmd.domain.semantic

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.CoreRegistryMetric
import com.healthmd.core.CoreRegistryOutput
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.HEALTHMD_CORE_REGISTRY_SHA256
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.UnitConverter
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.VitalsData
import java.io.File
import java.time.LocalDate
import java.time.LocalDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertThrows
import org.junit.Test

class HealthMdSemanticInputAdapterTest {
    @Test
    fun exactTimestampAndBinary64PreserveSourceFidelity() {
        val timestamp = HealthMdSemanticInputAdapter.exactTimestamp(
            ExactSourceTimestamp(1_772_943_300L, 987_654_321, "+05:45"),
            calendarUtcOffsetSeconds = 20_700,
        )
        val withoutOffset = HealthMdSemanticInputAdapter.exactTimestamp(
            ExactSourceTimestamp(1_772_943_301L, 1, null),
            calendarUtcOffsetSeconds = -14_400,
        )
        val negativeZero = HealthMdSemanticInputAdapter.binary64(-0.0, "ratio_0_1")

        assertThat(timestamp["epoch_seconds"].toString().trim('"')).isEqualTo("1772943300")
        assertThat(timestamp["nanoseconds"].toString()).isEqualTo("987654321")
        assertThat(timestamp["source_utc_offset_seconds"].toString()).isEqualTo("20700")
        assertThat(withoutOffset["source_utc_offset_seconds"].toString()).isEqualTo("null")
        assertThat(negativeZero["number"].toString()).contains("8000000000000000")
    }

    @Test
    fun configuredTimezoneMustBeAnIanaIdentifier() {
        listOf("not/an-iana-zone", "+05:00").forEach { invalidZone ->
            assertThrows(HealthMdSemanticInputAdapter.AdapterException::class.java) {
                HealthMdSemanticInputAdapter.sessionConfiguration(
                    sessionId = "bad-timezone",
                    profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
                    selection = MetricSelectionState(),
                    registry = registry("android_frozen_v4", 4u),
                    calendarTimeZone = invalidZone,
                )
            }
        }
    }

    @Test
    fun profileAdaptersAreCanonicalAndDoNotLeakAndroidNativeFieldsIntoFrozenV4() {
        val day = HealthData(
            date = LocalDate.of(2026, 3, 8),
            activity = ActivityData(
                steps = 1,
                totalCalories = 2_200.0,
                stepSamples = listOf(
                    TimestampedSample(
                        time = LocalDateTime.of(2026, 3, 8, 12, 0),
                        value = 1.0,
                        identity = ExactSourceIdentity(nativeId = "native-step-record"),
                    ),
                ),
            ),
            vitals = VitalsData(bloodOxygenAvg = 0.975),
            body = BodyData(bodyFatPercentage = 0.2),
        )
        val converter = UnitConverter(UnitPreference.METRIC)

        val frozen = HealthMdSemanticInputAdapter.batch(
            sessionId = "android-adapter-test",
            profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
            batchIndex = 0u,
            finalBatch = true,
            healthData = listOf(day),
            registry = registry("android_frozen_v4", 4u),
            converter = converter,
            calendarTimeZone = "UTC",
        )
        val multiDay = HealthMdSemanticInputAdapter.batch(
            sessionId = "multi-day-identity",
            profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
            batchIndex = 0u,
            finalBatch = true,
            healthData = listOf(day, day.copy(date = day.date.plusDays(1))),
            registry = registry("android_frozen_v4", 4u),
            converter = converter,
            calendarTimeZone = "UTC",
        )
        assertThat(multiDay.retainedExtensionTokens).hasSize(2)
        assertThat(multiDay.retainedExtensionTokens.toSet()).hasSize(2)
        assertThrows(HealthMdSemanticInputAdapter.AdapterException::class.java) {
            HealthMdSemanticInputAdapter.batch(
                sessionId = "ordinal-overflow",
                profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
                batchIndex = 0u,
                finalBatch = true,
                healthData = listOf(day),
                registry = registry("android_frozen_v4", 4u),
                converter = converter,
                calendarTimeZone = "UTC",
                startingSourceOrdinal = ULong.MAX_VALUE,
            )
        }
        val rechunkedFrozen = HealthMdSemanticInputAdapter.batch(
            sessionId = "android-adapter-test-rechunked",
            profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
            batchIndex = 7u,
            finalBatch = true,
            healthData = listOf(day),
            registry = registry("android_frozen_v4", 4u),
            converter = converter,
            calendarTimeZone = "UTC",
        )
        val bounded = HealthMdSemanticInputAdapter.boundedBatches(
            sessionId = "android-adapter-test-bounded",
            profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
            healthData = listOf(day),
            registry = registry("android_frozen_v4", 4u),
            converter = converter,
            calendarTimeZone = "UTC",
        )
        val analytical = HealthMdSemanticInputAdapter.batch(
            sessionId = "android-adapter-test-v5",
            profile = HealthMdSemanticInputAdapter.Profile.ANALYTICAL_V5,
            batchIndex = 0u,
            finalBatch = true,
            healthData = listOf(day),
            registry = registry("android_analytical_v5", 5u),
            converter = converter,
            calendarTimeZone = "UTC",
        )

        val frozenText = frozen.bytes.decodeToString()
        val analyticalText = analytical.bytes.decodeToString()
        assertThat(frozenText).startsWith("{\"batch_index\":")
        assertThat(Json.parseToJsonElement(frozenText)).isNotNull()
        assertThat(frozenText).contains("ratio_0_1")
        assertThat(frozenText).doesNotContain("total_calories")
        assertThat(analyticalText).contains("total_calories")
        assertThat(frozen.retainedExtensionTokens).hasSize(1)
        assertThat(rechunkedFrozen.retainedExtensionTokens)
            .containsExactlyElementsIn(frozen.retainedExtensionTokens)
            .inOrder()
        assertThat(bounded).hasSize(1)
        assertThat(bounded.single().bytes.size).isAtMost(1_048_576)
        assertThat(bounded.single().bytes.decodeToString()).contains("\"final_batch\":true")
        val frozenIds = Json.parseToJsonElement(frozenText).jsonObject["records"]!!.jsonArray
            .map { it.jsonObject.getValue("record_id") }
        val rechunkedIds = Json.parseToJsonElement(rechunkedFrozen.bytes.decodeToString())
            .jsonObject["records"]!!.jsonArray.map { it.jsonObject.getValue("record_id") }
        assertThat(rechunkedIds).containsExactlyElementsIn(frozenIds).inOrder()
    }

    @Test
    fun sharedDifferentialFixtureCanonicalizesWithoutNumericOrTimestampLoss() {
        val fixtureFile = generateSequence(File(System.getProperty("user.dir") ?: ".")) { it.parentFile }
            .map { File(it, "packages/contracts/semantic-input/v1/fixtures/differential-v1.json") }
            .firstOrNull(File::isFile)
            ?: error("Could not locate semantic differential fixture")
        val fixture = Json.parseToJsonElement(fixtureFile.readText()).jsonObject
        val cases = fixture.getValue("cases").jsonArray
        assertThat(cases).hasSize(3)

        cases.forEach { fixtureCase ->
            val caseObject = fixtureCase.jsonObject
            val config = caseObject.getValue("config")
            val batches = caseObject.getValue("batches").jsonArray
            assertThat(
                Json.parseToJsonElement(HealthMdSemanticInputAdapter.canonicalBytes(config).decodeToString()),
            ).isEqualTo(config)
            batches.forEach { batch ->
                assertThat(
                    Json.parseToJsonElement(HealthMdSemanticInputAdapter.canonicalBytes(batch).decodeToString()),
                ).isEqualTo(batch)
            }
        }
    }

    @Test
    fun shadowComparatorReturnsPathsWithoutValues() {
        val differences = HealthMdSemanticShadowComparator.differences(
            "{\"days\":[{\"value\":1}]}".encodeToByteArray(),
            "{\"days\":[{\"value\":2}]}".encodeToByteArray(),
        )

        assertThat(differences).containsExactly("/days/0/value")
        assertThat(differences.joinToString()).doesNotContain("1")
        assertThat(differences.joinToString()).doesNotContain("2")
    }

    private fun registry(profileId: String, schemaVersion: UInt): CoreMetricRegistrySnapshot =
        CoreMetricRegistrySnapshot(
            registryVersion = 1u,
            registrySha256 = HEALTHMD_CORE_REGISTRY_SHA256,
            profileId = profileId,
            publicProfileId = if (schemaVersion == 4u) "android-frozen-v4" else "android-analytical-v5",
            publicSchema = "healthmd.health_data",
            publicSchemaVersion = schemaVersion,
            profileRevision = 1u,
            categories = emptyList(),
            metrics = listOf(
                metric("blood_oxygen", "blood_oxygen", 0u),
                metric("body_fat", "body_fat", 1u),
                metric("android.total_calories", "total_calories", 2u),
                metric("steps", "steps", 3u),
            ),
            unavailableMetrics = emptyList(),
            outputs = listOf(
                output("blood_oxygen", "blood_oxygen", 0u),
                output("body_fat_percent", "body_fat", 1u),
                output("total_calories", "total_calories", 2u),
                output("steps", "steps", 3u),
            ),
        )

    private fun metric(semanticId: String, selectionId: String, ordinal: UInt) =
        CoreRegistryMetric(
            semanticId = semanticId,
            selectionId = selectionId,
            labelKey = selectionId,
            referenceName = selectionId,
            categoryId = "Vitals",
            unit = "",
            kind = "quantity",
            sourceAggregation = "latest",
            defaultEnabled = true,
            archiveOnly = false,
            availabilityKey = selectionId,
            authorizationKey = selectionId,
            capabilityId = "export.metric-registry",
            sourceSelector = selectionId,
            relatedSemanticIds = emptyList(),
            ordinal = ordinal,
        )

    private fun output(key: String, selectionId: String, ordinal: UInt) =
        CoreRegistryOutput(
            selectionIds = listOf(selectionId),
            surface = "flat",
            key = key,
            unit = "",
            dailyAggregation = "",
            rollup = "",
            aliasKind = "none",
            platformNative = selectionId == "total_calories",
            condition = if (selectionId == "total_calories") "android_native_opt_in" else "default",
            enabledByDefault = selectionId != "total_calories",
            ordinal = ordinal,
        )
}
