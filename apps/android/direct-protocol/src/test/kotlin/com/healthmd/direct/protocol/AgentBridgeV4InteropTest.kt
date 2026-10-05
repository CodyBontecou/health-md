package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import java.util.Base64
import java.nio.file.Files
import java.nio.file.Path
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class AgentBridgeV4InteropTest {
    // Fixture loading is not the production boundary. Each candidate is passed as raw bytes below.
    private val fixture by lazy {
        Json.parseToJsonElement(requireNotNull(javaClass.getResource("/conformance.json")).readText()).jsonObject
    }

    @Test
    fun genericCanonicalAgreementIsNotTypedConformance() {
        val vectors = fixture.getValue("canonical_vectors").jsonArray
        assertThat(vectors.size).isEqualTo(58)
        for ((index, entry) in vectors.withIndex()) {
            val vector = entry.jsonObject
            val actual = AgentBridgeCodec.canonicalize(vector.getValue("value").toString().toByteArray())
            com.google.common.truth.Truth.assertWithMessage("generic vector $index").that(actual).isEqualTo(
                Base64.getDecoder().decode(vector.getValue("canonical_base64").jsonPrimitive.content),
            )
            assertThat(AgentBridgeCodec.sha256(actual)).isEqualTo(vector.getValue("sha256").jsonPrimitive.content)
        }
    }

    private val supportedSchemas = setOf(
        "healthmd.agent_discovery_request", "healthmd.agent_discovery", "healthmd.agent_export_intent",
        "healthmd.agent_plan_request", "healthmd.agent_export_plan", "healthmd.agent_approval_request",
        "healthmd.agent_approval", "healthmd.agent_execute_request", "healthmd.agent_execution_receipt",
        "healthmd.agent_cancel_request", "healthmd.agent_resume_request", "healthmd.agent_artifact_manifest",
        "healthmd.agent_commit_receipt", "healthmd.agent_authority", "healthmd.agent_export_delegation", "healthmd.agent_error",
        "healthmd.source_query_catalog", "healthmd.source_query_request", "healthmd.source_query_response",
        "healthmd.source_query_cursor_claims", "healthmd.source_query_cancel", "healthmd.source_query_cancelled",
        "healthmd.source_projection_request", "healthmd.source_projection_catalog", "healthmd.source_data_projection",
    )
    private val cases get() = fixture.getValue("cases").jsonArray.map { it.jsonObject }
    private fun supported(value: kotlinx.serialization.json.JsonElement): Boolean =
        value is JsonObject && value["schema"]?.jsonPrimitive?.content in supportedSchemas

    @Test
    fun typedFixtureRoundTripsAreDistinctFromStoredContextConformance() {
        val positive = cases.filter { it.getValue("expected") == JsonPrimitive("valid") && supported(it.getValue("value")) }
        assertThat(positive).isNotEmpty()
        for (case in positive) {
            val value = case.getValue("value")
            val raw = value.toString().toByteArray()
            val document = AgentBridgeCodec.decode(raw)
            com.google.common.truth.Truth.assertWithMessage("typed fixture %s", case.getValue("id")).that(AgentBridgeCodec.encode(document))
                .isEqualTo(AgentBridgeCodec.canonicalize(raw))
        }
        // A fixture with a stored-context oracle remains round-trip-only here, never evidence of
        // issued authority, current consent/revisions, cursor MAC, artifact bytes, or native resume.
    }

    @Test
    fun standaloneFixtureNegativeCasesUseProductionValidation() {
        for (case in cases.filter { "context" !in it && it.getValue("expected") != JsonPrimitive("valid") && supported(it.getValue("value")) }) {
            val error = org.junit.Assert.assertThrows(case.getValue("id").toString(), AgentBridgeException::class.java) {
                AgentBridgeCodec.decode(case.getValue("value").toString().toByteArray())
            }
            com.google.common.truth.Truth.assertWithMessage("negative %s", case.getValue("id")).that(error.message)
                .isEqualTo(case.getValue("expected").jsonPrimitive.content)
            assertThat(error.cause).isNull()
        }
    }

    @Test
    fun lexicalPathChecksDoNotReplaceNativeFilesystemGates() {
        for (case in cases.filter { it.getValue("family") == JsonPrimitive("path") || it.getValue("family") == JsonPrimitive("collision") }) {
            val action = {
                if (case.getValue("family") == JsonPrimitive("path")) AgentBridgeValidation.safePath(case.getValue("value").jsonPrimitive.content, templates = true)
                else AgentBridgeValidation.collisions(case.getValue("value").jsonArray.map { it.jsonPrimitive.content })
            }
            if (case.getValue("expected") == JsonPrimitive("valid")) action()
            else assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) { action() }.message)
                .isEqualTo(case.getValue("expected").jsonPrimitive.content)
        }
    }

    @Test
    fun unsupportedUnicodeFilesystemFoldingFailsClosedWithoutChangingJson() {
        assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
            AgentBridgeValidation.collisions(listOf("Straße.md", "STRAẞE.md"))
        }.message).isEqualTo("path_collision")
        assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
            AgentBridgeValidation.collisions(listOf("é/synthetic.json"))
        }.message).isEqualTo("unsupported_capability")
        // NFC is used only for collision keys. Canonical JSON retains both distinct scalar strings.
        assertThat(AgentBridgeCodec.canonicalize("{\"é\":1,\"é\":2}".toByteArray()).decodeToString())
            .isEqualTo("{\"é\":1,\"é\":2}")
    }

    private val unsupportedDocumentCases get() = cases.filter {
        it.getValue("value") is JsonObject && "schema" in it.getValue("value").jsonObject && !supported(it.getValue("value"))
    }
    private val wireCases get() = cases.filter { it.getValue("family") == JsonPrimitive("wire") }

    @Test
    fun unsupportedDomainsHaveNoUntypedForwardingEscapeHatch() {
        for (case in unsupportedDocumentCases) assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
            AgentBridgeCodec.decode(case.getValue("value").toString().toByteArray())
        }.message).isEqualTo("unsupported_capability")
        assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
            AgentBridgeCodec.decode("{\"schema\":\"healthmd.future_grant\",\"schema_version\":1}".toByteArray())
        }.message).isEqualTo("unsupported_capability")
    }

    @Test
    fun fixtureWireChecksAreEnvelopeOnlyAndUnsupportedControlRejections() {
        for (case in wireCases) {
            val context = case.getValue("context").jsonObject
            // The reserved standalone-projection negatives have versions but no peer context.
            val platform = if (context["peer"]?.jsonObject?.get("platform") == JsonPrimitive("apple")) AgentBridgePlatform.APPLE else AgentBridgePlatform.ANDROID
            val negotiated = AgentBridgeNegotiation.negotiate(platform,
                context.getValue("host_versions").jsonArray.map { it.jsonPrimitive.content.toInt() },
                context.getValue("source_versions").jsonArray.map { it.jsonPrimitive.content.toInt() })
            val value = case.getValue("value").jsonObject
            // The reviewed grammar permits controls, but this bounded implementation explicitly doesn't.
            val expected = if (value.getValue("type").jsonPrimitive.content.startsWith("control_")) "unsupported_capability"
                else case.getValue("expected").jsonPrimitive.content
            if (expected == "valid") {
                val bytes = value.toString().toByteArray()
                val message = AgentBridgeCodec.decodeEnvelope(bytes, negotiated)
                assertThat(AgentBridgeCodec.encodeEnvelope(message, negotiated)).isEqualTo(AgentBridgeCodec.canonicalize(bytes))
            } else com.google.common.truth.Truth.assertWithMessage("wire %s", case.getValue("id")).that(
                org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
                    AgentBridgeCodec.decodeEnvelope(value.toString().toByteArray(), negotiated)
                }.message,
            ).isEqualTo(expected)
        }
    }

    private val queryBindingCases get() = cases.filter {
        "context" in it && it.getValue("value") is JsonObject &&
            it.getValue("value").jsonObject["schema"]?.jsonPrimitive?.content in
            setOf("healthmd.source_query_request", "healthmd.source_query_response")
    }

    @Test
    fun queryCatalogAndResponseBindingChecksArePureNotNativeAuthority() {
        for (case in queryBindingCases) {
            val action = {
                val document = AgentBridgeCodec.decode(case.getValue("value").toString().toByteArray())
                val context = case.getValue("context").jsonObject
                val catalog = AgentBridgeCodec.decode(context.getValue("catalog").toString().toByteArray()) as AgentBridgeQueryCatalog
                when (document) {
                    is AgentBridgeQueryRequest -> AgentBridgeValidation.validateQueryCatalogBinding(document, catalog)
                    is AgentBridgeQueryResponse -> {
                        val request = AgentBridgeCodec.decode(context.getValue("request").toString().toByteArray()) as AgentBridgeQueryRequest
                        AgentBridgeValidation.validateQueryResponseBinding(document, request, catalog)
                    }
                    else -> error("unexpected test branch")
                }
            }
            if (case.getValue("expected") == JsonPrimitive("valid")) action()
            else com.google.common.truth.Truth.assertWithMessage("query invariant %s", case.getValue("id")).that(
                org.junit.Assert.assertThrows(AgentBridgeException::class.java) { action() }.message,
            ).isEqualTo(case.getValue("expected").jsonPrimitive.content)
        }
        // Context's JSON authority is deliberately NOT supplied to these helpers; it cannot be
        // installed consent, entitlement, revocation state, a cursor MAC, or a captured dataset.
    }

    @Test
    fun sharedSummaryIntentHasIndependentConstructorProvenance() {
        val shared = AgentBridgeSharedIntent.construct()
        val bytes = AgentBridgeCodec.encode(shared)
        // Fixture is only the expected assertion. The constructor above consumes no fixture value.
        val expected = cases.single { it.getValue("id") == JsonPrimitive("intent-request-owned-summary") }.getValue("value")
        assertThat(Json.parseToJsonElement(bytes.decodeToString())).isEqualTo(expected)
        assertThat(bytes).isEqualTo(AgentBridgeCodec.canonicalize(expected.toString().toByteArray()))
        assertThat(AgentBridgeCodec.decode(bytes)).isEqualTo(shared)
    }

    @Test
    fun independentNativeConstructorsAndExplicitCandidateOutput() {
        val shared = AgentBridgeSharedIntent.construct()
        val expected = cases.single { it.getValue("id") == JsonPrimitive("intent-request-owned-summary") }.getValue("value")
        assertThat(Json.parseToJsonElement(AgentBridgeCodec.encode(shared).decodeToString())).isEqualTo(expected)
        val documents = AgentBridgeSynthetic.documents + shared
        val native = documents.mapIndexed { index, document ->
            val bytes = AgentBridgeCodec.encode(document)
            assertThat(AgentBridgeCodec.decode(bytes)).isEqualTo(document)
            JsonObject(mapOf("value" to Json.parseToJsonElement(bytes.decodeToString()),
                "canonical_base64" to JsonPrimitive(Base64.getEncoder().encodeToString(bytes)),
                "sha256" to JsonPrimitive(AgentBridgeCodec.sha256(bytes)), "provenance" to JsonPrimitive("typed-constructor")) +
                if (index == documents.lastIndex) mapOf("id" to JsonPrimitive("intent-request-owned-summary")) else emptyMap())
        }
        val generic = fixture.getValue("canonical_vectors").jsonArray.map { entry ->
            val value = entry.jsonObject.getValue("value")
            val bytes = AgentBridgeCodec.canonicalize(value.toString().toByteArray())
            JsonObject(mapOf("value" to value, "canonical_base64" to JsonPrimitive(Base64.getEncoder().encodeToString(bytes)),
                "sha256" to JsonPrimitive(AgentBridgeCodec.sha256(bytes)), "provenance" to JsonPrimitive("generic-codec-only")))
        }
        if (System.getenv("HEALTHMD_GENERATE_AGENT_BRIDGE_V4") != "1") return
        val output = requireNotNull(System.getenv("HEALTHMD_AGENT_BRIDGE_CANDIDATES")) { "explicit scratch output required" }
        val path = Path.of(output)
        val repository = generateSequence(Path.of("").toAbsolutePath().normalize()) { it.parent }
            .first { Files.exists(it.resolve(".git")) }
        require(path.isAbsolute && !path.normalize().startsWith(repository) &&
            !path.parent.toRealPath().startsWith(repository.toRealPath()) && !Files.isSymbolicLink(path)) { "external scratch output required" }
        val roundTripIds = cases.filter { it.getValue("expected") == JsonPrimitive("valid") && supported(it.getValue("value")) }.map { it.getValue("id") }
        val selfCheckedIds = cases.filter { "context" !in it && supported(it.getValue("value")) }.map { it.getValue("id") }
        val lexicalIds = cases.filter { it.getValue("family").jsonPrimitive.content in setOf("path", "collision") }.map { it.getValue("id") }
        val queryIds = queryBindingCases.map { it.getValue("id") }
        val unsupportedIds = unsupportedDocumentCases.map { it.getValue("id") }
        val wireIds = wireCases.map { it.getValue("id") }
        val tested = (roundTripIds + selfCheckedIds + lexicalIds + queryIds + unsupportedIds + wireIds).toSet()
        val coverage = JsonObject(mapOf(
            "generic_codec_vectors" to JsonPrimitive(generic.size), "typed_constructor_vectors" to JsonPrimitive(native.size),
            "shared_typed_constructor_case_ids" to JsonArray(listOf(JsonPrimitive("intent-request-owned-summary"))),
            "typed_positive_roundtrip_only_case_ids" to JsonArray(roundTripIds),
            "standalone_document_case_ids" to JsonArray(selfCheckedIds), "lexical_path_only_case_ids" to JsonArray(lexicalIds),
            "query_catalog_response_document_binding_only_case_ids" to JsonArray(queryIds),
            "unsupported_document_rejection_case_ids" to JsonArray(unsupportedIds),
            "wire_envelope_only_or_unsupported_control_case_ids" to JsonArray(wireIds),
            "unexercised_case_ids" to JsonArray(cases.map { it.getValue("id") }.filter { it !in tested }),
            "runtime_context_not_proven_case_ids" to JsonArray(cases.filter { "context" in it && it.getValue("family") != JsonPrimitive("path") }.map { it.getValue("id") }),
            "unsupported_schemas" to JsonArray(listOf("control", "control_plan", "control_approval", "control_receipt", "projection_job", "profile_dictionary").map(::JsonPrimitive)),
            "runtime_gates" to JsonPrimitive("not implemented: issued authority/approval, provider reads, native storage, cursor MAC, transfer/artifact-byte binding, filesystem transactions"),
        ))
        Files.write(path, AgentBridgeCodec.canonical(JsonObject(mapOf("language" to JsonPrimitive("kotlin"),
            "coverage" to coverage, "vectors" to JsonArray(native + generic)))),
            java.nio.file.StandardOpenOption.CREATE, java.nio.file.StandardOpenOption.TRUNCATE_EXISTING,
            java.nio.file.StandardOpenOption.WRITE, java.nio.file.LinkOption.NOFOLLOW_LINKS)
    }

    @Test
    fun unicodeScalarOrderAndNoNormalization() {
        val raw = "{\"\uD800\uDC00\":1,\"\uFFFF\":2,\"é\":3,\"é\":4,\"slash\":\"a/b\"}".toByteArray()
        val expected = "{\"é\":4,\"slash\":\"a/b\",\"é\":3,\"\uFFFF\":2,\"\uD800\uDC00\":1}".toByteArray()
        assertThat(AgentBridgeCodec.canonicalize(raw)).isEqualTo(expected)
        assertThat(AgentBridgeCodec.canonicalize("{\"n\":9223372036854775807}".toByteArray()).decodeToString())
            .isEqualTo("{\"n\":9223372036854775807}")
    }

    @Test
    fun rawBoundaryRejectsBeforeJsonCanEraseEvidence() {
        val invalid = listOf(
            "{\"a\":1,\"a\":2}",
            "{\"a\":{\"x\":1,\"\\u0078\":2}}",
            "{\"x\":\"\\ud800\"}",
            "{\"x\":\"\\udc00\"}",
            "{\"x\":\"\\ud800x\\udc00\"}",
            "{\"x\":1.0}", "{\"x\":1e0}", "{\"x\":NaN}", "{\"x\":01}", "{\"x\":-01}", "{\"x\":+1}",
            "{\"x\":9223372036854775808}", "{\"x\":-9223372036854775809}",
            "[" + List(4097) { "0" }.joinToString(",") + "]",
            "{" + (0 until 513).joinToString(",") { "\"k$it\":0" } + "}",
            "[" + List(4096) { "[" + List(64) { "0" }.joinToString(",") + "]" }.joinToString(",") + "]",
            "[".repeat(25) + "0" + "]".repeat(25),
            "{\"x\":\"" + "a".repeat(65537) + "\"}",
        ).map { it.toByteArray() } + listOf(
            byteArrayOf(0xc0.toByte(), 0xaf.toByte()),
            byteArrayOf(0xed.toByte(), 0xa0.toByte(), 0x80.toByte()),
            byteArrayOf(0xf4.toByte(), 0x90.toByte(), 0x80.toByte(), 0x80.toByte()),
            ByteArray(2097153) { 32 },
        )
        for (raw in invalid) {
            val error = org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
                AgentBridgeCodec.canonicalize(raw)
            }
            assertThat(error.message).isEqualTo("invalid_request")
            assertThat(error.cause).isNull()
        }
    }

    @Test
    fun standaloneNegotiationAndRawEnvelopesPreserveBaseApplications() {
        for ((platform, base) in listOf(AgentBridgePlatform.APPLE to 1, AgentBridgePlatform.ANDROID to 2)) {
            val legacy = AgentBridgeNegotiation.negotiate(platform, listOf(base, 3, 4), listOf(base))
            assertThat(legacy.baseApplication).isEqualTo(base)
            assertThat(legacy.agentExtension).isFalse()
            assertThat(legacy.appleQueryExtension).isFalse()
            val current = AgentBridgeNegotiation.negotiate(platform, listOf(base, 3, 4), listOf(base, 3, 4))
            assertThat(current.baseApplication).isEqualTo(base)
            assertThat(current.appleQueryExtension).isEqualTo(platform == AgentBridgePlatform.APPLE)
            val message = AgentBridgeMessage("discovery_request", AgentBridgeSynthetic.discoveryRequest)
            val bytes = AgentBridgeCodec.encodeEnvelope(message, current)
            assertThat(AgentBridgeCodec.decodeEnvelope(bytes, current)).isEqualTo(message)
            assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
                AgentBridgeCodec.decodeEnvelope(bytes, legacy)
            }.message).isEqualTo("unsupported_capability")
            for (raw in listOf(
                bytes.decodeToString().replace("\"protocol_version\":4", "\"protocol_version\":4,\"protocol_version\":4"),
                bytes.decodeToString().replace("\"protocol_version\":4", "\"protocol_version\":true"),
                bytes.decodeToString().replace("\"protocol_version\":4", "\"protocol_version\":\"4\""),
                bytes.decodeToString().replace("discovery_request", "projection_request"),
            )) org.junit.Assert.assertThrows(AgentBridgeException::class.java) { AgentBridgeCodec.decodeEnvelope(raw.toByteArray(), current) }
            val unsupported = bytes.decodeToString().replace("\"type\":\"discovery_request\"", "\"type\":\"control_request\"")
            assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) { AgentBridgeCodec.decodeEnvelope(unsupported.toByteArray(), current) }.message)
                .isEqualTo("unsupported_capability")
        }
        org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
            AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, listOf(4), listOf(4))
        }
    }

    @Test
    fun exactDecimalsDatesAndZeroHealthSideEffectsAreCheckedAtByteBoundary() {
        val n = AgentBridgeSynthetic
        val metric = AgentBridgeMetricItem(AgentBridgeMetricItemAvailability.AVAILABLE, emptyList(), "heart_rate_avg",
            "2000-01-01", AgentBridgeCatalogItemStatisticsItem.AVERAGE, "metric", "bpm", AgentBridgeValueDecimal("decimal", "60.1250"))
        val response = n.sourceResponse.copy(items = listOf(n.sourceResponse.items.single().copy(values = listOf(metric))))
        val bytes = AgentBridgeCodec.encode(response)
        assertThat(AgentBridgeCodec.decode(bytes)).isEqualTo(response)
        assertThat(bytes.decodeToString()).contains("\"value\":\"60.1250\"")
        for (bad in listOf("60.125", "true", "null")) {
            org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
                AgentBridgeCodec.decode(bytes.decodeToString().replace("\"60.1250\"", bad).toByteArray())
            }
        }
        val planBytes = AgentBridgeCodec.encode(n.plan).decodeToString()
        for (field in listOf("content_preview_reads", "credential_enrollments", "earliest_date_reads", "health_reads",
                "output_writes", "quota_consumed", "settings_mutations", "wake_enrollments")) {
            assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
                AgentBridgeCodec.decode(planBytes.replace("\"$field\":0", "\"$field\":1").toByteArray())
            }.message).isEqualTo("invalid_request")
        }
        for (date in listOf("0000-01-01", "2000-02-30")) {
            val invalid = AgentBridgeCodec.encode(n.intent).decodeToString().replace("2000-01-01", date)
            val error = org.junit.Assert.assertThrows(AgentBridgeException::class.java) { AgentBridgeCodec.decode(invalid.toByteArray()) }
            assertThat(error.message).isEqualTo("invalid_request"); assertThat(error.cause).isNull()
        }
        val discovery = AgentBridgeCodec.encode(n.discovery).decodeToString()
        for (instant in listOf("2000-01-03T23:59:60Z", "2000-01-03T24:00:00Z")) {
            assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
                AgentBridgeCodec.decode(discovery.replace(n.issued, instant).toByteArray())
            }.message).isEqualTo("invalid_request")
        }
        assertThat(AgentBridgeValidation.resolveDates(AgentBridgeDatesPastCompleteDays("2024-03-11", 2, "past_complete_days"), "America/New_York"))
            .isEqualTo(AgentBridgeDatesExact(AgentBridgeRange("2024-03-10", "2024-03-09"), "exact"))
        assertThat(AgentBridgeValidation.predictedPaths(n.intent.copy(dates = AgentBridgeDatesAllAvailable("all_available")), n.settings)).isEmpty()
    }

    @Test
    fun nativeSourcePrecisionAndMetadataAreNotFabricated() {
        val native = AgentBridgeSynthetic.sourceResponse
        val bytes = AgentBridgeCodec.encode(native)
        assertThat(bytes.decodeToString()).contains("\"client_record_version\":9223372036854775807")
        assertThat(bytes.decodeToString()).contains("\"nanosecond\":123456789")
        assertThat(bytes.decodeToString()).contains("\"source_offset_seconds\":null")
        assertThat(bytes.decodeToString()).doesNotContain("next_cursor")
        val decoded = AgentBridgeCodec.decode(bytes) as AgentBridgeQueryResponseSourceRecordListing
        assertThat((decoded.items.single().identity as AgentBridgeNativeIdentityHealthConnect).clientRecordVersion).isEqualTo(Long.MAX_VALUE)
        for (bad in listOf(
            bytes.decodeToString().replace("9223372036854775807", "9223372036854775808"),
            bytes.decodeToString().replace("9223372036854775807", "\"9223372036854775807\""),
            bytes.decodeToString().replace("9223372036854775807", "null"),
            bytes.decodeToString().replace("\"source_offset_seconds\":null", "\"source_offset_seconds\":true"),
            bytes.decodeToString().replace("\"source_offset_seconds\":null", "\"source_offset_seconds\":null,\"source_offset_seconds\":null"),
            bytes.decodeToString().replace("\"source_nanoseconds\"", "\"future_precision\""),
        )) {
            val error = org.junit.Assert.assertThrows(AgentBridgeException::class.java) { AgentBridgeCodec.decode(bad.toByteArray()) }
            assertThat(error.message).isEqualTo("invalid_request"); assertThat(error.cause).isNull()
        }
        val unavailable = AgentBridgeSynthetic.hcIdentity.copy(clientRecordId = null, clientRecordVersion = null,
            lastModified = null, metadataStatus = AgentBridgeNativeIdentityHealthConnectMetadataStatus(
                AgentBridgeClientIdAvailability.ABSENT, AgentBridgeMetadataAvailability.NOT_CAPTURED, AgentBridgeMetadataAvailability.NOT_CAPTURED))
        val partial = native.copy(coverage = native.coverage.copy(status = AgentBridgeCoverageStatus.PARTIAL),
            items = listOf(native.items.single().copy(identity = unavailable)))
        val partialBytes = AgentBridgeCodec.encode(partial)
        assertThat(partialBytes.decodeToString()).doesNotContain("\"client_record_id\":null")
        assertThat(partialBytes.decodeToString()).doesNotContain("\"client_record_version\":null")
        assertThat(partialBytes.decodeToString()).doesNotContain("\"last_modified\":null")
        assertThat(AgentBridgeCodec.decode(partialBytes)).isEqualTo(partial)
        org.junit.Assert.assertThrows(AgentBridgeException::class.java) { AgentBridgeCodec.encode(partial.copy(coverage = native.coverage)) }
    }

    @Test
    fun binary64RationalTiesEvenSignedZeroAndRawTimeRejection() {
        val cases = listOf(
            Triple("3ff8000000000000", 1L, 500000000), Triple("bff8000000000000", -2L, 500000000),
            Triple("8000000000000000", 0L, 0), Triple("0000000000000001", 0L, 0),
            Triple("3f50000000000000", 0L, 976562), Triple("3f68000000000000", 0L, 2929688),
            Triple("bf50000000000000", -1L, 999023438),
        )
        for ((bits, seconds, nanos) in cases) {
            val time = AgentBridgeValidation.fromBinary64Bits(bits)
            assertThat(time.epochSecond).isEqualTo(seconds); assertThat(time.nanosecond).isEqualTo(nanos)
            assertThat(time.sourceBinary64Bits).isEqualTo(bits)
            val identity = AgentBridgeNativeIdentityAppleHealth(AgentBridgeNativeIdentityAppleHealthIdentityKind.NATIVE,
                AgentBridgeNativeIdentityAppleHealthMetadataStatus("not_exposed_by_source", "not_exposed_by_source", "not_exposed_by_source"),
                providerId = "apple_health", recordId = "00000000-0000-0000-0000-000000000001",
                recordType = "HKQuantityTypeIdentifierStepCount", sourceId = "apple_health")
            val response = AgentBridgeSynthetic.sourceResponse.copy(peer = AgentBridgeSynthetic.peer.copy(platform = AgentBridgePlatform.APPLE),
                sourceId = AgentBridgeQueryCatalogSourceId.APPLE_HEALTH, providerId = "apple_health",
                items = listOf(AgentBridgeSynthetic.sourceResponse.items.single().copy(start = time, end = time, identity = identity)))
            val raw = AgentBridgeCodec.encode(response)
            assertThat(AgentBridgeCodec.decode(raw)).isEqualTo(response)
            val bad = raw.decodeToString().replace("\"nanosecond\":$nanos", "\"nanosecond\":${nanos + 1}")
            assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) { AgentBridgeCodec.decode(bad.toByteArray()) }.message).isEqualTo("invalid_request")
        }
        for (bits in listOf("7ff0000000000000", "fff0000000000000", "7ff8000000000001", "7fefffffffffffff")) {
            val error = org.junit.Assert.assertThrows(AgentBridgeException::class.java) { AgentBridgeValidation.fromBinary64Bits(bits) }
            assertThat(error.message).isEqualTo("invalid_request"); assertThat(error.cause).isNull()
        }
    }

    @Test
    fun approvalAndResumeComparisonsNeverMintStoredDecisions() {
        val n = AgentBridgeSynthetic
        AgentBridgeValidation.validateApprovalBinding(n.approvalRequest, n.plan)
        AgentBridgeValidation.validateResumeAgainst(n.resume, n.resume)
        for (changed in listOf(n.resume.copy(requestSha256 = n.zero), n.resume.copy(frontierSha256 = n.zero),
            n.resume.copy(committedPartitionCount = 0), n.resume.copy(manifestSha256 = n.zero))) {
            assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
                AgentBridgeValidation.validateResumeAgainst(changed, n.resume)
            }.message).isEqualTo("binding_changed")
        }
        org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
            AgentBridgeValidation.validateApprovalBinding(n.approvalRequest.copy(binding = n.binding.copy(scopeSha256 = n.zero)), n.plan)
        }
        val stale = n.plan.copy(intent = n.intent.copy(settingsPolicy = AgentBridgeSettingsPolicyProfile(2, n.id(99), "profile")),
            revisions = listOf(AgentBridgeRevision(AgentBridgeRevisionDomain.NATIVE_PROFILE, n.id(99), 1, n.one)))
            .let { it.copy(planSha256 = AgentBridgeValidation.planDigest(it)) }
        assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) { AgentBridgeCodec.encode(stale) }.message)
            .isEqualTo("revision_conflict")
        // Correct hash/JSON still supplies no issuance evidence; no persistence/execution API exists.
        org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
            AgentBridgeCodec.encode(n.execute.copy(approval = n.approval.copy(binding = n.binding.copy(settingsSha256 = n.zero))))
        }
    }

    @Test
    fun independentDiscoveryRequestUsesClosedProductionDto() {
        val document = AgentBridgeDiscoveryRequest(
            schema = "healthmd.agent_discovery_request", schemaVersion = 1,
            requestId = "00000000-0000-4000-8000-000000000064",
            peer = AgentBridgePeer(
                hostInstallationId = "00000000-0000-4000-8000-000000000001",
                sourceInstallationId = "00000000-0000-4000-8000-000000000002", platform = AgentBridgePlatform.ANDROID,
            ),
        )
        val encoded = AgentBridgeCodec.encode(document)
        assertThat(AgentBridgeCodec.decode(encoded)).isEqualTo(document)
        val json = encoded.decodeToString()
        for (bad in listOf(
            json.replace("\"schema_version\":1", "\"schema_version\":true"),
            json.replace("\"schema_version\":1", "\"schema_version\":1.0"),
            json.replace("\"schema_version\":1", "\"schema_version\":\"1\""),
            json.replace("\"schema_version\":1", "\"schema_version\":4294967297"),
            json.replace("\"schema_version\":1", "\"schema_version\":-4294967295"),
            json.replace(",\"schema_version\":1", ""),
            json.replace("\"schema_version\":1", "\"schema_version\":null"),
            json.replace("\"schema_version\":1", "\"schema_version\":1,\"secret\":\"rejected-value\""),
        )) {
            assertThat(org.junit.Assert.assertThrows(AgentBridgeException::class.java) {
                AgentBridgeCodec.decode(bad.toByteArray())
            }.message).isEqualTo("invalid_request")
        }
    }
}
