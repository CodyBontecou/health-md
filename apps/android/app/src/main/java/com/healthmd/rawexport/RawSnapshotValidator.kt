package com.healthmd.rawexport

import java.io.BufferedReader
import java.security.DigestInputStream
import java.io.InputStream
import java.io.InputStreamReader
import java.io.Reader
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/** Out-of-band integrity evidence. Sidecars are optional; claims are explicit in the result. */
data class RawValidationOptions(
    val expectedArtifactChecksumSha256: String? = null,
    val sidecarText: String? = null,
    val artifactFileName: String? = null,
)

data class RawValidationIssue(
    val code: String,
    val severity: RawIssueSeverity,
    val location: String,
    /** Fixed diagnostic text. It never interpolates source data. */
    val message: String,
)

data class RawSnapshotValidationResult(
    val valid: Boolean,
    val schema: String?,
    val majorVersion: Int?,
    val format: RawExportFormat,
    val recordCount: Long,
    val issueCount: Long,
    val artifactChecksumSha256: String?,
    val artifactChecksumVerified: Boolean,
    val sidecarChecksumVerified: Boolean,
    val additiveUnknownFieldCount: Long,
    val issues: List<RawValidationIssue>,
)

/**
 * Streaming semantic validator for raw-snapshot v1. It retains only header/manifest/accounting state
 * and one record or issue at a time. Public failures are structured and sanitized; record values are
 * delivered only through the opt-in callback.
 */
class RawSnapshotValidator(
    private val decoder: (JsonObject) -> DecodedRawRecord = RawRecordDecoder::decode,
) {
    fun validate(
        input: InputStream,
        format: RawExportFormat,
        options: RawValidationOptions = RawValidationOptions(),
        onRecord: (DecodedRawRecord) -> Unit = {},
    ): RawSnapshotValidationResult {
        val state = State(format, options, onRecord)
        val digest = MessageDigest.getInstance("SHA-256")
        val stream = DigestInputStream(input, digest)
        try {
            when (format) {
                RawExportFormat.JSON -> validateJson(stream, state)
                RawExportFormat.NDJSON -> validateNdjson(stream, state)
            }
            state.finishedReading = true
            state.artifactChecksum = digest.digest().hex()
            state.finish()
        } catch (unsupported: UnsupportedMajorVersion) {
            state.schema = unsupported.schema
            state.majorVersion = unsupported.major
            state.error("unsupported_major_version", "header", "The raw snapshot major version is newer than this validator supports.")
        } catch (decode: RawDecodeException) {
            state.error("record_${decode.code}", state.currentLocation + decode.structuralPath, "A raw record has an invalid v1 field shape.")
        } catch (_: SerializationException) {
            state.error("invalid_json_shape", state.currentLocation, "The artifact contains an invalid v1 JSON shape.")
        } catch (_: StreamSyntaxException) {
            state.error("invalid_stream_shape", state.currentLocation, "The artifact stream is malformed or truncated.")
        } catch (_: java.nio.charset.CharacterCodingException) {
            state.error("invalid_utf8", state.currentLocation, "The artifact is not valid UTF-8.")
        } catch (_: Throwable) {
            state.error("validation_failed", state.currentLocation, "Validation could not complete safely.")
        }
        return state.result()
    }

    private fun validateJson(input: InputStream, state: State) {
        val cursor = JsonCursor(strictUtf8Reader(input))
        cursor.expect('{')
        cursor.expectKey("header")
        state.readHeader(parseObject(cursor.readValue()), RawExportFormat.JSON)
        cursor.expect(',')
        cursor.expectKey("records")
        cursor.readArray { raw -> state.readRecord(parseObject(raw)) }
        cursor.expect(',')
        cursor.expectKey("issues")
        cursor.readArray { raw -> state.readIssue(parseObject(raw)) }
        cursor.expect(',')
        cursor.expectKey("manifest")
        state.readManifest(parseObject(cursor.readValue()))
        cursor.expect('}')
        cursor.requireEnd()
    }

    private fun validateNdjson(input: InputStream, state: State) {
        val reader = BufferedReader(strictUtf8Reader(input), 64 * 1024)
        var lineNumber = 0L
        var phase = 0 // header, records, issues, manifest
        while (true) {
            val line = reader.readLine() ?: break
            lineNumber++
            state.currentLocation = "line[$lineNumber]"
            if (line.isEmpty() || line.isBlank()) throw StreamSyntaxException()
            val envelope = parseObject(line)
            val kind = (envelope["kind"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw StreamSyntaxException()
            when (kind) {
                "header" -> {
                    if (lineNumber != 1L || phase != 0 || envelope["header"] !is JsonObject) throw StreamSyntaxException()
                    state.readHeader(envelope.getValue("header").jsonObject, RawExportFormat.NDJSON)
                    phase = 1
                }
                "record" -> {
                    if (phase != 1 || envelope["record"] !is JsonObject) throw StreamSyntaxException()
                    state.readRecord(envelope.getValue("record").jsonObject)
                }
                "issue" -> {
                    if (phase !in 1..2 || envelope["issue"] !is JsonObject) throw StreamSyntaxException()
                    phase = 2
                    state.readIssue(envelope.getValue("issue").jsonObject)
                }
                "manifest" -> {
                    if (phase !in 1..2 || envelope["manifest"] !is JsonObject) throw StreamSyntaxException()
                    state.readManifest(envelope.getValue("manifest").jsonObject)
                    phase = 3
                }
                else -> throw StreamSyntaxException()
            }
            if (phase == 3) {
                // The manifest is last, including blank/trailing lines.
                if (reader.readLine() != null) {
                    state.error("content_after_manifest", "line[${lineNumber + 1}]", "NDJSON contains content after its final manifest.")
                }
                break
            }
        }
        if (lineNumber == 0L) throw StreamSyntaxException()
        if (phase != 3) state.error("manifest_missing", "manifest", "The artifact has no final manifest and is incomplete.")
    }

    private inner class State(
        val format: RawExportFormat,
        val options: RawValidationOptions,
        val onRecord: (DecodedRawRecord) -> Unit,
    ) {
        val validationIssues = mutableListOf<RawValidationIssue>()
        var schema: String? = null
        var majorVersion: Int? = null
        var header: RawSnapshotHeader? = null
        var manifest: RawSnapshotManifest? = null
        var currentLocation = "header"
        var recordCount = 0L
        var sourceIssueCount = 0L
        var unknownCount = 0L
        var finishedReading = false
        var artifactChecksum: String? = null
        var artifactVerified = false
        var sidecarVerified = false
        private val logical = MessageDigest.getInstance("SHA-256")
        private val typeCounts = linkedMapOf<String, Long>()
        private val reportRecordCounts = linkedMapOf<String, Long>()
        private val reportWireTypes = linkedMapOf<String, String>()
        private val reportIssueCounts = linkedMapOf<String, Long>()
        private val identities = hashSetOf<String>()
        private var previousOrder: RecordOrder? = null

        fun readHeader(o: JsonObject, actualFormat: RawExportFormat) {
            currentLocation = "header"
            if (header != null) { error("duplicate_header", "header", "The artifact contains more than one header."); return }
            REQUIRED_HEADER_KEYS.forEach { if (it !in o) error("header_shape", "header", "The header is missing a required v1 member.") }
            val requestObject = o["request"] as? JsonObject ?: throw StreamSyntaxException()
            REQUIRED_REQUEST_KEYS.forEach { if (it !in requestObject) error("header_shape", "header.request", "The request is missing a required v1 member.") }
            val capabilitiesObject = o["capabilities"] as? JsonObject ?: throw StreamSyntaxException()
            REQUIRED_CAPABILITY_KEYS.forEach { if (it !in capabilitiesObject) error("header_shape", "header.capabilities", "Capabilities are missing a required v1 member.") }
            val actualSchema = string(o, "schema") ?: return
            val version = integer(o, "version") ?: return
            schema = actualSchema; majorVersion = version
            if (actualSchema != "healthmd.raw-snapshot") {
                error("unsupported_schema", "header", "The artifact schema identifier is unsupported.")
                return
            }
            if (version > SUPPORTED_MAJOR) throw UnsupportedMajorVersion(actualSchema, version)
            if (version != SUPPORTED_MAJOR) { error("unsupported_major_version", "header", "The raw snapshot major version is unsupported."); return }
            val decoded = lenient.decodeFromJsonElement(RawSnapshotHeader.serializer(), o)
            if (decoded.schema != actualSchema || decoded.version != version) throw StreamSyntaxException()
            if (decoded.request.format != actualFormat) error("format_mismatch", "header.request.format", "The declared and physical artifact formats differ.")
            if (!decoded.capabilities.nonTransactional) error("transactional_claim", "header.capabilities", "Raw snapshot v1 must declare its non-transactional source semantics.")
            if (decoded.request.selectedMetricIds.toList() != decoded.request.selectedMetricIds.sorted()) error("set_order", "header.request.selectedMetricIds", "A set-valued header field is not lexically ordered.")
            if (decoded.capabilities.grantedPermissions.toList() != decoded.capabilities.grantedPermissions.sorted() || decoded.capabilities.availableFeatures.toList() != decoded.capabilities.availableFeatures.sorted()) error("set_order", "header.capabilities", "A set-valued capability field is not lexically ordered.")
            val expectedId = snapshotId(decoded)
            if (decoded.snapshotId != expectedId) error("snapshot_id", "header.snapshotId", "The snapshot identifier does not match the v1 derivation.")
            header = decoded
            unknownCount += countUnknownHeader(o)
            val logicalHeader = decoded.copy(request = decoded.request.copy(format = RawExportFormat.JSON))
            logical("header", RawJson.canonical(lenient.encodeToJsonElement(RawSnapshotHeader.serializer(), logicalHeader)))
        }

        fun readRecord(o: JsonObject) {
            currentLocation = "record[$recordCount]"
            if (header == null) throw StreamSyntaxException()
            val decoded = try { decoder(o) } catch (failure: RawDecodeException) {
                error("record_${failure.code}", currentLocation + failure.structuralPath, "A raw record has an invalid v1 field shape.")
                return
            }
            if (decoded.source.providerId != header?.capabilities?.providerId) {
                error("record_source", currentLocation, "A record source does not match the snapshot provider.")
            }
            if (decoded.fields is DecodedFields.Exercise) {
                val routeRequired = header?.request?.includeExerciseRoutes == true
                if (routeRequired != (decoded.fields.route != null)) {
                    error("route_inclusion", currentLocation + "/fields/route", "Exercise route inclusion does not match the snapshot request.")
                }
            }
            val expectedHash = if (decoded.recordKind == RawRecordKind.PROVIDER_PAYLOAD) {
                (decoded.fields as DecodedFields.Provider).payload.responseSha256
            } else {
                RawJson.sha256(RawJson.canonical(JsonObject(o.filterKeys { it != "hash" })))
            }
            if (decoded.hash != expectedHash) error("record_checksum", currentLocation, "A record checksum does not match its canonical v1 content.")
            validateIdentity(decoded, o)
            val order = RecordOrder(decoded.wireType, decoded.startTime, decoded.endTime, decoded.nativeIdentity, decoded.hash)
            previousOrder?.let { if (it > order) error("record_order", currentLocation, "Records are not in canonical v1 order.") }
            previousOrder = order
            if (!identities.add(decoded.nativeIdentity)) error("duplicate_identity", currentLocation, "A promoted snapshot contains a duplicate native identity.")
            recordCount++
            typeCounts[decoded.wireType] = (typeCounts[decoded.wireType] ?: 0L) + 1
            val reportKey = when (val fields = decoded.fields) {
                is DecodedFields.Provider -> fields.payload.endpointKey
                is DecodedFields.Medical -> "medical_resource/${fields.payload.medicalResourceType.label}"
                else -> decoded.wireType
            }
            reportRecordCounts[reportKey] = (reportRecordCounts[reportKey] ?: 0L) + 1
            reportWireTypes[reportKey] = decoded.wireType
            unknownCount += decoded.additiveUnknownFields.size
            logical("record", RawJson.canonical(o))
            try { onRecord(decoded) } catch (_: Throwable) { error("record_callback_failed", currentLocation, "The record consumer rejected a decoded record.") }
        }

        fun readIssue(o: JsonObject) {
            currentLocation = "issue[$sourceIssueCount]"
            REQUIRED_ISSUE_KEYS.forEach { if (it !in o) error("issue_shape", currentLocation, "A source issue has an invalid v1 shape.") }
            val decoded = lenient.decodeFromJsonElement(RawIssue.serializer(), o)
            sourceIssueCount++
            decoded.recordType?.let { reportIssueCounts[it] = (reportIssueCounts[it] ?: 0L) + 1 }
            logical("issue", RawJson.canonical(o))
        }

        fun readManifest(o: JsonObject) {
            currentLocation = "manifest"
            if (manifest != null) { error("duplicate_manifest", "manifest", "The artifact contains more than one final manifest."); return }
            val manifestSchema = string(o, "schema") ?: return
            val version = integer(o, "version") ?: return
            if (manifestSchema != "healthmd.raw-snapshot.manifest" || version != SUPPORTED_MAJOR) {
                error("manifest_version", "manifest", "The final manifest schema or major version is unsupported.")
                return
            }
            REQUIRED_MANIFEST_KEYS.forEach { if (it !in o) error("manifest_shape", "manifest", "The final manifest is missing a required v1 member.") }
            (o["typeCounts"] as? kotlinx.serialization.json.JsonArray)?.forEachIndexed { index, element ->
                val count = element as? JsonObject ?: throw StreamSyntaxException()
                setOf("wireType", "count").forEach { if (it !in count) error("manifest_shape", "manifest.typeCounts[$index]", "A type count is missing a required member.") }
            }
            (o["typeReports"] as? kotlinx.serialization.json.JsonArray)?.forEachIndexed { index, element ->
                val report = element as? JsonObject ?: throw StreamSyntaxException()
                REQUIRED_TYPE_REPORT_KEYS.forEach { if (it !in report) error("manifest_shape", "manifest.typeReports[$index]", "A type report is missing a required v1 member.") }
            }
            manifest = lenient.decodeFromJsonElement(RawSnapshotManifest.serializer(), o)
        }

        fun finish() {
            val h = header
            val m = manifest
            if (h == null) error("header_missing", "header", "The artifact has no valid header.")
            if (m == null) { error("manifest_missing", "manifest", "The artifact has no final manifest and is incomplete."); verifyArtifact(null); return }
            if (h != null && m.snapshotId != h.snapshotId) error("snapshot_mismatch", "manifest.snapshotId", "Header and manifest snapshot identifiers differ.")
            if (m.recordCount != recordCount) error("record_count", "manifest.recordCount", "The manifest record count does not match the stream.")
            if (m.issueCount != sourceIssueCount) error("issue_count", "manifest.issueCount", "The manifest issue count does not match the stream.")
            if (m.duplicateCount < 0 || m.identityCollisionCount < 0) error("negative_count", "manifest", "A manifest count is negative.")
            if (m.typeCounts.map { it.wireType } != m.typeCounts.map { it.wireType }.sorted() || m.typeCounts.map { it.wireType }.distinct().size != m.typeCounts.size) error("type_count_order", "manifest.typeCounts", "Type counts are not unique and lexically ordered.")
            val expectedCounts = typeCounts.entries.sortedBy { it.key }.map { RawTypeCount(it.key, it.value) }
            if (m.typeCounts != expectedCounts) error("type_counts", "manifest.typeCounts", "Manifest type counts do not match decoded records.")
            validateReports(m, h)
            val logicalHash = logical.digest().hex()
            if (m.logicalChecksumSha256 != logicalHash) error("logical_checksum", "manifest.logicalChecksumSha256", "The logical snapshot checksum does not match the stream.")
            val expectedManifestHash = RawJson.sha256(RawJson.canonical(JsonObject(lenient.encodeToJsonElement(RawSnapshotManifest.serializer(), m).jsonObject.filterKeys { it != "manifestChecksumSha256" && it != "artifactChecksumSha256" })))
            if (m.manifestChecksumSha256 != expectedManifestHash) error("manifest_checksum", "manifest.manifestChecksumSha256", "The manifest checksum is invalid.")
            verifyArtifact(m)
        }

        private fun validateReports(m: RawSnapshotManifest, h: RawSnapshotHeader?) {
            val reports = m.typeReports
            if (reports.map { it.typeKey } != reports.map { it.typeKey }.sorted() || reports.map { it.typeKey }.distinct().size != reports.size) error("type_report_order", "manifest.typeReports", "Type reports are not unique and lexically ordered.")
            if (h?.capabilities?.providerId == "health_connect") {
                val expected = RawExportTypeCatalog.definitions.map { it.typeKey }.sorted()
                if (reports.map { it.typeKey } != expected) error("type_report_inventory", "manifest.typeReports", "The Health Connect v1 type-report inventory is incomplete.")
            }
            reports.forEachIndexed { index, report ->
                if (report.recordCount < 0 || report.issueCount < 0) error("negative_count", "manifest.typeReports[$index]", "A type report count is negative.")
                if (report.recordCount != (reportRecordCounts[report.typeKey] ?: 0L)) error("type_report_record_count", "manifest.typeReports[$index]", "A type report record count is inconsistent.")
                reportWireTypes[report.typeKey]?.let { if (report.wireType != it) error("type_report_wire_type", "manifest.typeReports[$index]", "A type report wire type is inconsistent.") }
                if (report.issueCount != (reportIssueCounts[report.typeKey] ?: 0L)) error("type_report_issue_count", "manifest.typeReports[$index]", "A type report issue count is inconsistent.")
                if (report.status != RawTypeStatus.EXPORTED && report.status != RawTypeStatus.NOT_SELECTED && report.issueCount == 0L) error("type_report_issue_missing", "manifest.typeReports[$index]", "A non-exported type report has no matching structured issue.")
            }
            if (h?.capabilities?.providerId == "health_connect") {
                reports.forEachIndexed { index, report ->
                    RawExportTypeCatalog.byKey[report.typeKey]?.let { definition ->
                        if (report.wireType != definition.wireType || report.rangeBehavior != definition.rangeBehavior ||
                            report.permission != definition.permission || report.feature != definition.feature
                        ) error("type_report_contract", "manifest.typeReports[$index]", "A Health Connect type report does not match the closed v1 catalog.")
                    }
                }
            }
            val known = reports.map { it.typeKey }.toSet()
            if ((reportRecordCounts.keys + reportIssueCounts.keys).any { it !in known }) error("type_report_unaccounted", "manifest.typeReports", "A record or issue has no matching type report.")
        }

        private fun verifyArtifact(m: RawSnapshotManifest?) {
            val checksum = artifactChecksum ?: return
            val expected = options.expectedArtifactChecksumSha256
            if (expected != null) {
                if (!SHA.matches(expected) || checksum != expected) error("artifact_checksum", "artifact", "The out-of-band artifact checksum does not match exact bytes.") else artifactVerified = true
            }
            m?.artifactChecksumSha256?.let { embedded ->
                if (embedded != checksum) error("artifact_checksum", "manifest.artifactChecksumSha256", "The embedded artifact checksum does not match exact bytes.") else artifactVerified = true
            }
            options.sidecarText?.let { text ->
                val name = options.artifactFileName
                if (name == null || name.contains('\n') || name.contains('\r')) {
                    error("sidecar_context", "sidecar", "Sidecar validation requires a safe artifact filename.")
                } else {
                    val match = Regex("^([0-9a-f]{64})  ${Regex.escape(name)}\\n$").matchEntire(text)
                    if (match == null || match.groupValues[1] != checksum) {
                        error("sidecar_checksum", "sidecar", "The checksum sidecar is malformed or does not match exact artifact bytes.")
                    } else {
                        sidecarVerified = true
                    }
                }
            }
        }

        private fun validateIdentity(record: DecodedRawRecord, o: JsonObject) {
            if (record.recordKind == RawRecordKind.PROVIDER_PAYLOAD) return
            val metadata = record.metadata
            val expected = when {
                metadata != null && metadata.nonRestorable.serverAssignedId.isNotBlank() -> "hc:${metadata.nonRestorable.serverAssignedId}"
                metadata != null && !metadata.restorable.clientRecordId.isNullOrBlank() -> "client:${metadata.nonRestorable.dataOriginPackageName}:${metadata.restorable.clientRecordId}:${metadata.restorable.clientRecordVersion}"
                record.wireType == "medical_resource" -> {
                    val medical = (record.fields as DecodedFields.Medical).payload
                    "medical:${medical.medicalResourceDataSourceId}:${medical.fhirResourceType.raw}:${medical.fhirResourceId}"
                }
                else -> {
                    val seed = o.toMutableMap().apply { put("nativeIdentity", JsonPrimitive("")); remove("hash") }
                    "synthetic:${RawJson.sha256(RawJson.canonical(JsonObject(seed)))}"
                }
            }
            if (record.nativeIdentity != expected) error("native_identity", currentLocation, "A record native identity does not match v1 precedence.")
        }

        private fun logical(kind: String, canonical: String) {
            logical.update(kind.toByteArray(StandardCharsets.UTF_8)); logical.update(0)
            logical.update(canonical.toByteArray(StandardCharsets.UTF_8)); logical.update('\n'.code.toByte())
        }

        fun error(code: String, location: String, message: String) {
            validationIssues += RawValidationIssue(code, RawIssueSeverity.ERROR, sanitizeLocation(location), message)
        }

        fun result() = RawSnapshotValidationResult(
            valid = validationIssues.none { it.severity == RawIssueSeverity.ERROR },
            schema = schema,
            majorVersion = majorVersion,
            format = format,
            recordCount = recordCount,
            issueCount = sourceIssueCount,
            artifactChecksumSha256 = artifactChecksum,
            artifactChecksumVerified = artifactVerified,
            sidecarChecksumVerified = sidecarVerified,
            additiveUnknownFieldCount = unknownCount,
            issues = validationIssues.toList(),
        )
    }

    private data class RecordOrder(val wire: String, val start: DecodedInstant?, val end: DecodedInstant?, val identity: String, val hash: String) : Comparable<RecordOrder> {
        override fun compareTo(other: RecordOrder): Int {
            compareValues(wire, other.wire).takeIf { it != 0 }?.let { return it }
            nullableInstant(start, other.start).takeIf { it != 0 }?.let { return it }
            nullableInstant(end, other.end).takeIf { it != 0 }?.let { return it }
            compareValues(identity, other.identity).takeIf { it != 0 }?.let { return it }
            return compareValues(hash, other.hash)
        }
        private fun nullableInstant(a: DecodedInstant?, b: DecodedInstant?): Int = when { a == null && b == null -> 0; a == null -> -1; b == null -> 1; else -> a.compareTo(b) }
    }

    /** Small root tokenizer: arrays stream one raw JSON value at a time. */
    private class JsonCursor(private val reader: Reader) {
        private var pushed = -2
        fun expect(char: Char) { skipWhitespace(); if (read() != char.code) throw StreamSyntaxException() }
        fun expectKey(key: String) {
            skipWhitespace(); val raw = readValue(); val parsed = RawJson.codec.parseToJsonElement(raw)
            if ((parsed as? JsonPrimitive)?.takeIf { it.isString }?.content != key) throw StreamSyntaxException()
            expect(':')
        }
        fun readArray(item: (String) -> Unit) {
            expect('['); skipWhitespace(); var c = read()
            if (c == ']'.code) return
            push(c)
            while (true) {
                item(readValue())
                skipWhitespace(); c = read()
                if (c == ']'.code) return
                if (c != ','.code) throw StreamSyntaxException()
            }
        }
        fun readValue(): String {
            skipWhitespace(); val first = read(); if (first < 0) throw StreamSyntaxException()
            val out = StringBuilder(); out.append(first.toChar())
            if (first == '"'.code) { readStringBody(out); return out.toString() }
            if (first == '{'.code || first == '['.code) {
                var depth = 1; var inString = false; var escaped = false
                while (depth > 0) {
                    val c = read(); if (c < 0) throw StreamSyntaxException(); val ch = c.toChar(); out.append(ch)
                    if (inString) {
                        if (escaped) escaped = false else if (ch == '\\') escaped = true else if (ch == '"') inString = false
                    } else when (ch) { '"' -> inString = true; '{', '[' -> depth++; '}', ']' -> depth-- }
                }
                return out.toString()
            }
            while (true) {
                val c = read(); if (c < 0) break
                if (c.toChar().isWhitespace() || c == ','.code || c == ']'.code || c == '}'.code) { push(c); break }
                out.append(c.toChar())
            }
            return out.toString()
        }
        private fun readStringBody(out: StringBuilder) { var escaped = false; while (true) { val c = read(); if (c < 0) throw StreamSyntaxException(); val ch = c.toChar(); out.append(ch); if (escaped) escaped = false else if (ch == '\\') escaped = true else if (ch == '"') return } }
        fun requireEnd() { skipWhitespace(); if (read() >= 0) throw StreamSyntaxException() }
        private fun skipWhitespace() { while (true) { val c = read(); if (c < 0) return; if (!c.toChar().isWhitespace()) { push(c); return } } }
        private fun read(): Int = if (pushed != -2) pushed.also { pushed = -2 } else reader.read()
        private fun push(c: Int) { if (pushed != -2) throw StreamSyntaxException(); pushed = c }
    }

    private fun strictUtf8Reader(input: InputStream): Reader = InputStreamReader(
        input,
        StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT),
    )

    private fun parseObject(raw: String): JsonObject = RawJson.codec.parseToJsonElement(raw) as? JsonObject ?: throw StreamSyntaxException()
    private fun string(o: JsonObject, key: String): String? = (o[key] as? JsonPrimitive)?.takeIf { it.isString }?.content.also { if (it == null) throw StreamSyntaxException() }
    private fun integer(o: JsonObject, key: String): Int? = (o[key] as? JsonPrimitive)?.intOrNull.also { if (it == null) throw StreamSyntaxException() }
    private fun snapshotId(header: RawSnapshotHeader): String {
        val logical = header.request.copy(format = RawExportFormat.JSON)
        val requestJson = RawJson.canonical(lenient.encodeToJsonElement(RawSnapshotRequest.serializer(), logical))
        val providerLine = if (header.capabilities.providerId == "health_connect") "" else "provider:${header.capabilities.providerId}\n"
        return RawJson.sha256("v1\n$providerLine${header.createdAt.epochSecond}:${header.createdAt.nano}\n$requestJson").take(32)
    }
    private fun countUnknownHeader(o: JsonObject): Long {
        var count = o.keys.count { it !in setOf("schema", "version", "snapshotId", "createdAt", "request", "capabilities") }.toLong()
        val request = o["request"] as? JsonObject
        if (request != null) count += request.keys.count { it !in setOf("format", "scope", "startTime", "endTime", "selectedMetricIds", "pageSize", "includeExerciseRoutes", "calendarZoneId") }
        val capabilities = o["capabilities"] as? JsonObject
        if (capabilities != null) count += capabilities.keys.count { it !in setOf("sdkVersion", "available", "providerId", "fidelityLevel", "grantedPermissions", "availableFeatures", "historicalReadGranted", "nonTransactional", "preservesSourceUnits", "preservesUnknownSdkFields") }
        return count
    }
    private fun sanitizeLocation(value: String): String = value.take(160).replace(Regex("[^A-Za-z0-9_./\\[\\]-]"), "_")
    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

    private class StreamSyntaxException : Exception()
    private data class UnsupportedMajorVersion(val schema: String, val major: Int) : Exception()

    companion object {
        const val SUPPORTED_MAJOR = 1
        private val SHA = Regex("[0-9a-f]{64}")
        private val REQUIRED_HEADER_KEYS = setOf("schema", "version", "snapshotId", "createdAt", "request", "capabilities")
        private val REQUIRED_REQUEST_KEYS = setOf("format", "scope", "startTime", "endTime", "selectedMetricIds", "pageSize", "includeExerciseRoutes")
        private val REQUIRED_CAPABILITY_KEYS = setOf("sdkVersion", "available", "grantedPermissions", "availableFeatures", "historicalReadGranted", "nonTransactional", "preservesSourceUnits", "preservesUnknownSdkFields")
        private val REQUIRED_ISSUE_KEYS = setOf("code", "message", "severity", "recordType", "retryable")
        private val REQUIRED_MANIFEST_KEYS = setOf("schema", "version", "snapshotId", "status", "completedAt", "recordCount", "issueCount", "duplicateCount", "identityCollisionCount", "typeCounts", "typeReports", "logicalChecksumSha256", "manifestChecksumSha256", "artifactChecksumSha256")
        private val REQUIRED_TYPE_REPORT_KEYS = setOf("typeKey", "wireType", "status", "recordCount", "issueCount", "permission", "feature", "rangeBehavior", "message")
        private val lenient = Json {
            encodeDefaults = true
            explicitNulls = true
            ignoreUnknownKeys = true
            prettyPrint = false
            classDiscriminator = "kind"
        }
    }
}
