package com.healthmd.diagnostics

import com.google.common.truth.Truth.assertThat
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import java.util.zip.ZipFile
import kotlinx.serialization.json.*
import org.junit.After
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

class DiagnosticStoreTest {
    private lateinit var root: File
    private val stores = mutableListOf<DiagnosticStore>()
    @Before fun setup() { root = Files.createTempDirectory("healthmd-diagnostics-test-").toFile() }
    @After fun cleanup() { stores.forEach { it.close() }; root.deleteRecursively() }
    private fun store(limit: Long = DiagnosticStore.DEFAULT_BYTE_LIMIT, clock: () -> Long = System::currentTimeMillis) = DiagnosticStore(File(root, UUID.randomUUID().toString()), limit, clock).also { stores += it }

    @Test fun sharedPrivacyFixtureRejectsUnknownFieldsAndRootData() {
        val repository = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.first { File(it, "packages/contracts").isDirectory }
        val fixture = Json.parseToJsonElement(File(repository, "packages/contracts/diagnostics/v1/fixtures/privacy.json").readText()).jsonObject
        val input = DiagnosticEvent(fixture.getValue("input").jsonObject)
        assertThat(input.filtered(false)?.document).isEqualTo(fixture["expected_operational"])
        assertThat(input.filtered(true)?.document).isEqualTo(fixture["expected_private"])
        listOf(false, true).forEach { include ->
            assertThat(input.filtered(include).toString()).doesNotContain("SYNTHETIC_HEALTH_SENTINEL")
            assertThat(input.filtered(include).toString()).doesNotContain("SYNTHETIC_SECRET_SENTINEL")
        }
    }
    @Test fun withoutConsentPrivateValuesNeverReachDisk() {
        val store = store()
        store.record(DiagnosticEventID.PEER_DISCOVERED, mapOf(DiagnosticField.PEER_NAME to DiagnosticValue.Text("SYNTHETIC_PRIVATE_PEER"), DiagnosticField.STATE to DiagnosticValue.Text("SYNTHETIC_SECRET_SENTINEL")))
        val events = store.snapshot(true).events
        assertThat(events).hasSize(1)
        assertThat(events.single().document.getValue("omitted_fields").jsonObject["peer_name"]?.jsonPrimitive?.content).isEqualTo("not_recorded")
        val disk = store.directory.listFiles().orEmpty().filter { it.extension == "jsonl" }.joinToString { it.readText() }
        assertThat(disk).doesNotContain("SYNTHETIC_PRIVATE_PEER")
        assertThat(disk).doesNotContain("SYNTHETIC_SECRET_SENTINEL")
    }
    @Test fun recordingAndSharingConsentAreIndependent() {
        val store = store()
        store.startPrivateContextRecording()
        store.record(DiagnosticEventID.PEER_DISCOVERED, mapOf(DiagnosticField.PEER_NAME to DiagnosticValue.Text("SYNTHETIC_PRIVATE_PEER")))
        store.stopPrivateContextRecording()
        store.record(DiagnosticEventID.PEER_LOST, mapOf(DiagnosticField.PEER_NAME to DiagnosticValue.Text("SYNTHETIC_NOT_RECORDED")))
        assertThat(store.snapshot(true).events.toString()).contains("SYNTHETIC_PRIVATE_PEER")
        assertThat(store.snapshot(false).events.toString()).doesNotContain("SYNTHETIC_PRIVATE_PEER")
        assertThat(store.snapshot(true).events.toString()).doesNotContain("SYNTHETIC_NOT_RECORDED")
        assertThat(store.snapshot(false).events.toString()).contains("redacted")
    }
    @Test fun recordingExpiresAndPrivateSegmentsHaveShorterRetention() {
        val now = AtomicLong(System.currentTimeMillis())
        val store = store(clock = now::get)
        store.startPrivateContextRecording()
        store.record(DiagnosticEventID.PEER_DISCOVERED, mapOf(DiagnosticField.PEER_NAME to DiagnosticValue.Text("SYNTHETIC_PRIVATE_PEER")))
        store.snapshot(true)
        now.addAndGet(16 * 60 * 1000)
        store.record(DiagnosticEventID.PEER_LOST, mapOf(DiagnosticField.PEER_NAME to DiagnosticValue.Text("SYNTHETIC_NOT_RECORDED")))
        assertThat(store.snapshot(true).events.toString()).doesNotContain("SYNTHETIC_NOT_RECORDED")
        now.addAndGet(DiagnosticStore.PRIVATE_RETENTION_MS)
        assertThat(store.snapshot(true).events.toString()).doesNotContain("SYNTHETIC_PRIVATE_PEER")
        assertThat(store.snapshot().events).isNotEmpty()
    }
    @Test fun disableClearAndSettingsSurviveRelaunch() {
        val store = store()
        store.record(DiagnosticEventID.APP_STARTED)
        assertThat(store.snapshot().events).hasSize(1)
        val bundle = DiagnosticBundleBuilder.prepare(store)
        store.configure(false, DiagnosticVerbosity.TRACE)
        store.record(DiagnosticEventID.NATIVE_LIFECYCLE)
        assertThat(store.snapshot().events).hasSize(1)
        store.clear()
        assertThat(store.snapshot().events).isEmpty()
        assertThat(bundle.directory.exists()).isFalse()
        val relaunched = DiagnosticStore(store.directory).also { stores += it }
        assertThat(relaunched.settings.enabled).isFalse()
    }
    @Test fun verbosityAndByteBudgetStayBounded() {
        val store = store(limit = 2048)
        store.configure(true, DiagnosticVerbosity.INFO)
        store.record(DiagnosticEventID.MESSAGE_SENT)
        assertThat(store.snapshot().events).isEmpty()
        repeat(40) { store.record(DiagnosticEventID.APP_STARTED) }
        assertThat(store.snapshot().events).isNotEmpty()
        assertThat(store.directory.listFiles().orEmpty().filter { it.extension == "jsonl" }.sumOf(File::length)).isAtMost(2048)
    }
    @Test fun expiredAndSymlinkedSegmentsAreNotRead() {
        val store = store()
        store.record(DiagnosticEventID.APP_STARTED)
        store.snapshot()
        val expired = File(store.directory, "operational-1-${UUID.randomUUID()}.jsonl")
        expired.writeText("SYNTHETIC_HEALTH_SENTINEL")
        val outside = File(root, "outside.txt").apply { writeText("SYNTHETIC_SECRET_SENTINEL") }
        val link = File(store.directory, "operational-${System.currentTimeMillis()}-${UUID.randomUUID()}.jsonl")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        assertThat(store.snapshot().events).hasSize(1)
        assertThat(expired.exists()).isFalse()
        assertThat(outside.readText()).isEqualTo("SYNTHETIC_SECRET_SENTINEL")
    }
    @Test fun arbitraryAttachmentIsFrozenExactlyAndDisclosed() {
        val store = store()
        val original = "{\"synthetic\":\"EXPLICIT_ATTACHMENT_SENTINEL\"}".toByteArray()
        val bundle = DiagnosticBundleBuilder.prepare(store, attachments = listOf(DiagnosticAttachment("../synthetic-original.json") { ByteArrayInputStream(original) }))
        assertThat(bundle.manifest["health_content"]?.jsonPrimitive?.content).isEqualTo("possible")
        assertThat(bundle.manifest["contains_private_context"]?.jsonPrimitive?.boolean).isTrue()
        assertThat(File(bundle.directory, "attachments/attachment-1.json").readBytes()).isEqualTo(original)
        ZipFile(bundle.verifiedFile()).use { zip ->
            assertThat(zip.getInputStream(zip.getEntry("attachments/attachment-1.json")).readBytes()).isEqualTo(original)
            assertThat(zip.entries().asSequence().map { it.name }.toList()).containsExactly("manifest.json", "README.txt", "events.jsonl", "events.txt", "attachments/attachment-1.json")
            assertThat(zip.getInputStream(zip.getEntry("manifest.json")).readBytes()).isEqualTo(File(bundle.directory, "manifest.json").readBytes())
        }
        bundle.zip.writeText("modified zip")
        assertThrows(DiagnosticBundleException::class.java) { bundle.verifiedFile() }
    }
    @Test fun operationalBundleAndPreviewDoNotCollectExtraData() {
        val store = store()
        store.record(DiagnosticEventID.APP_STARTED)
        val bundle = DiagnosticBundleBuilder.prepare(store)
        assertThat(bundle.manifest["health_content"]?.jsonPrimitive?.content).isEqualTo("not_included")
        assertThat(bundle.manifest["contains_private_context"]?.jsonPrimitive?.boolean).isFalse()
        assertThat(bundle.files.any { it.privacy == "user_attachment" }).isFalse()
        assertThat(bundle.preview("manifest.json").first).contains("healthmd.diagnostic_bundle")
        assertThrows(DiagnosticBundleException::class.java) { bundle.preview("../../settings.json") }
    }
    @Test fun previewTamperingRefusesBothPreviewAndSharing() {
        val store = store()
        store.record(DiagnosticEventID.APP_STARTED)
        val bundle = DiagnosticBundleBuilder.prepare(store)
        File(bundle.directory, "events.jsonl").writeText("SYNTHETIC_MODIFIED_REVIEW")
        assertThrows(DiagnosticBundleException::class.java) { bundle.preview("events.jsonl") }
        assertThrows(DiagnosticBundleException::class.java) { bundle.verifiedFile() }
    }
    @Test fun duplicateAndUnsupportedFieldShapesAreRestricted() {
        val store = store()
        store.record(DiagnosticEventID.CONNECTION_CHANGED, mapOf(DiagnosticField.STATE to DiagnosticValue.Text("connected")), unavailable = setOf(DiagnosticField.TRANSPORT))
        val event = store.snapshot().events.single()
        assertThat(event.document.getValue("omitted_fields").jsonObject["transport"]?.jsonPrimitive?.content).isEqualTo("unavailable")
        File(store.directory, "operational-${System.currentTimeMillis()}-${UUID.randomUUID()}.jsonl").writeText(event.document.toString() + "\n")
        assertThat(store.snapshot().events).hasSize(1)
        assertThat(store.snapshot().invalidEventCount).isEqualTo(1)
        val nested = DiagnosticEvent(JsonObject(event.document + ("fields" to buildJsonObject { put("state", buildJsonObject { put("nested", "SYNTHETIC_HEALTH_SENTINEL") }) })))
        assertThat(nested.filtered(false)?.document?.getValue("omitted_fields")?.jsonObject?.get("state")?.jsonPrimitive?.content).isEqualTo("invalid")
        val badVersion = DiagnosticEvent(JsonObject(event.document + ("schema_version" to JsonPrimitive("1"))))
        assertThat(badVersion.filtered(false)).isNull()
    }
    @Test fun storageFailureIsDisclosedWithoutThrowingFromRecord() {
        val blocked = File(root, "file-not-directory").apply { writeText("") }
        val store = DiagnosticStore(blocked).also { stores += it }
        store.record(DiagnosticEventID.APP_STARTED)
        assertThat(store.snapshot().events).isEmpty()
        assertThat(store.snapshot().droppedEventCount).isGreaterThan(0)
    }
    @Test fun concurrentRecordingAndPreparationDoNotRevokeDirectoryAccess() {
        val store = store()
        repeat(30) {
            store.record(DiagnosticEventID.APP_STARTED)
            val bundle = DiagnosticBundleBuilder.prepare(store)
            assertThat(bundle.verifiedFile().isFile).isTrue()
            bundle.delete()
        }
    }
    @Test fun failedAttachmentLeavesNoPartialBundle() {
        val store = store()
        assertThrows(IllegalStateException::class.java) { DiagnosticBundleBuilder.prepare(store, attachments = listOf(DiagnosticAttachment("missing.txt") { throw IllegalStateException("synthetic unavailable file") })) }
        assertThat(File(store.directory, "bundles").listFiles().orEmpty()).isEmpty()
    }
}
