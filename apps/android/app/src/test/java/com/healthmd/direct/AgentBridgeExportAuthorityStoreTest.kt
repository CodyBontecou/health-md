package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.*
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import java.time.Instant
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.json.*
import org.junit.Test

class AgentBridgeExportAuthorityStoreTest {
    @Test
    fun initializedEmptyLedgerStaysEmptyAfterRemoteRequestsWithoutNativeEnrollment() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val before = bytes(f)
            val discovery = f.service.discover(f.peerContext, f.discoveryRequest())
            assertThat(discovery.authorityReferences).isEmpty()
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.plan(f.peerContext, f.request(discovery)) }
            assertThat(bytes(f)).isEqualTo(before)
            assertThat(f.native.decisions).containsExactly(AgentBridgeExportNativeDecision.InitializeStore)
            assertThat(f.keys.calls).isAtLeast(2) // Actual load-only provider, not an unused enrollment mock.
        }
    }

    @Test
    fun deniedNativeSessionAndAbsentProtectedKeyCannotInitializeOrEnroll() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.native.allowed = false
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.store.initialize(f.native) }
            assertThat(Files.exists(ledger(f).parent)).isFalse()
            f.native.allowed = true
            f.keys.key = null
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.store.initialize(f.native) }
            assertThat(Files.exists(ledger(f).parent)).isFalse()
            f.keys.key = SecretKeySpec(ByteArray(32) { 0x37 }, "HmacSHA256")
            f.store.initialize(f.native)
            val before = bytes(f)
            f.native.allowed = false
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.store.putDelegation(f.native, f.delegation(), 0) }
            assertThat(bytes(f)).isEqualTo(before)
        }
    }

    @Test
    fun sourceIssuerCannotRegisterForeignHostDescriptionsOrSubstitutePeerAtCas() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val foreign = f.delegation().let { it.copy(issuer = AgentBridgeIssuer.AUTHORIZED_HOST,
                bounds = it.bounds.copy(destinationPolicy = AgentBridgeExportDelegationBoundsDestinationPolicyRegisteredHostBindings(listOf(f.intent().destination.bindingId), "registered_host_bindings"))) }
            val before = bytes(f)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.store.putDelegation(f.native, foreign, 0) }
            assertThat(bytes(f)).isEqualTo(before)
            assertThat(f.native.decisions).hasSize(1)
            f.store.putDelegation(f.native, f.delegation(), 0)
            val other = f.delegation().copy(grantRevision = 2, peer = f.peer.copy(hostInstallationId = AgentBridgeExportPlanningFixture.id(999)))
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.store.putDelegation(f.native, other, 1) }
            assertThat(f.service.discover(f.peerContext, f.discoveryRequest()).authorityReferences.single().grantRevision).isEqualTo(1)
        }
    }

    @Test
    fun lostOrRotatedKeyNeverRegeneratesExistingIssuerState() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val before = bytes(f)
            f.keys.key = null
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.restart().discover(f.peerContext, f.discoveryRequest()) }
            f.keys.key = SecretKeySpec(ByteArray(32) { 0x55 }, "HmacSHA256")
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.restart().discover(f.peerContext, f.discoveryRequest()) }
            assertThat(bytes(f)).isEqualTo(before)
            assertThat(f.native.decisions).hasSize(2)
        }
    }

    @Test
    fun invalidUtf8UnknownFieldsOversizeAndMacCorruptionAreReadOnlyFailures() {
        val mutations: List<(ByteArray) -> ByteArray> = listOf(
            { byteArrayOf(0xc3.toByte(), 0x28) },
            { it.decodeToString().replaceFirst("{", "{\"unknown\":1,").toByteArray() },
            { ByteArray(AgentBridgeExportAuthorityStore.MAX_BYTES + 1) { 0x20 } },
            { it.decodeToString().replaceFirst("\"mac\":\"", "\"mac\":\"f").toByteArray() },
        )
        for (mutate in mutations) AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val corrupt = mutate(bytes(f))
            Files.write(ledger(f), corrupt)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.restart().discover(f.peerContext, f.discoveryRequest()) }
            assertThat(bytes(f)).isEqualTo(corrupt)
        }
    }

    @Test
    fun validMacCannotMakeDuplicateRecordsCoercedScalarsOrUnknownNestedFieldsValidState() {
        val mutations: List<(JsonObject) -> JsonObject> = listOf(
            { state -> JsonObject(state + ("grants" to JsonArray(state.getValue("grants").jsonArray.toList() + state.getValue("grants").jsonArray[0]))) },
            { state -> JsonObject(state + ("revision" to JsonPrimitive("1"))) },
            { state ->
                val record = state.getValue("grants").jsonArray[0].jsonObject
                val text = record.getValue("delegationCanonical").jsonPrimitive.content.replaceFirst("{", "{\"unknown\":false,")
                JsonObject(state + ("grants" to JsonArray(listOf(JsonObject(record + ("delegationCanonical" to JsonPrimitive(text)))))))
            },
            { state -> JsonObject(state + ("version" to JsonPrimitive(2))) },
        )
        for (mutate in mutations) AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            rewriteWithSyntheticMac(f, mutate)
            val corrupt = bytes(f)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.restart().discover(f.peerContext, f.discoveryRequest()) }
            assertThat(bytes(f)).isEqualTo(corrupt)
        }
    }

    @Test
    fun symlinkHardLinkLoosePermissionsMissingLedgerAndInterruptedWriteFailClosed() {
        val mutations: List<(AgentBridgeExportPlanningFixture) -> Unit> = listOf(
            { f ->
                val outside = f.parent.resolve("outside")
                Files.write(outside, bytes(f)); Files.delete(ledger(f)); Files.createSymbolicLink(ledger(f), outside)
            },
            { f -> Files.createLink(f.parent.resolve("alias"), ledger(f)) },
            { f -> Files.setPosixFilePermissions(ledger(f), PosixFilePermissions.fromString("rw-r--r--")) },
            { f -> Files.setPosixFilePermissions(ledger(f).parent, PosixFilePermissions.fromString("rwxr-xr-x")) },
            { f -> Files.delete(ledger(f)) },
            { f -> Files.write(ledger(f).parent.resolve("pending-interrupted"), byteArrayOf(1)) },
        )
        for (mutate in mutations) AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            mutate(f)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.restart().discover(f.peerContext, f.discoveryRequest()) }
            assertThat(f.native.decisions).hasSize(2)
        }
    }

    @Test
    fun privateDirectorySymlinkAndReplacedAnchorAreNotAcceptedAsNewRoots() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val target = f.parent.resolve("moved")
            Files.move(ledger(f).parent, target)
            Files.createSymbolicLink(ledger(f).parent, target)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.discover(f.peerContext, f.discoveryRequest()) }
        }
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val moved = f.parent.resolveSibling(f.parent.fileName.toString() + "-moved")
            try {
                Files.move(f.parent, moved)
                Files.createDirectory(f.parent, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")))
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.discover(f.peerContext, f.discoveryRequest()) }
            } finally { moved.toFile().deleteRecursively() }
        }
    }

    @Test
    fun observedRootSubstitutionIsFencedWithinInstanceButFreshOpenHasNoPersistedInodeGuarantee() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val root = ledger(f).parent
            val moved = f.parent.resolve("replaced-root")
            Files.move(root, moved)
            Files.createDirectory(root, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")))
            Files.newDirectoryStream(moved).use { entries ->
                entries.forEach { entry ->
                    val copy = root.resolve(entry.fileName)
                    Files.copy(entry, copy)
                    Files.setPosixFilePermissions(copy, PosixFilePermissions.fromString("rw-------"))
                }
            }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.discover(f.peerContext, f.discoveryRequest()) }
            // Same valid signed bytes in a replacement owned temp directory: MAC is NOT inode identity
            // or anti-rollback. This explicitly records the fresh-open limitation, not a restore API.
            assertThat(f.restart().discover(f.peerContext, f.discoveryRequest()).authorityReferences).hasSize(1)
        }
    }

    @Test
    fun revocationIsDurableAndCannotBeEvictedRenewedOrUnrevokedAtCapacity() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            f.store.revoke(f.native, f.peer, f.delegation().authorityId, 1)
            for (n in 1 until AgentBridgeExportAuthorityStore.MAX_GRANTS) {
                f.store.putDelegation(f.native, f.delegation().copy(authorityId = AgentBridgeExportPlanningFixture.id(100 + n)), 0)
            }
            val before = bytes(f)
            f.expect(AgentBridgeErrorCode.BUSY) {
                f.store.putDelegation(f.native, f.delegation().copy(authorityId = AgentBridgeExportPlanningFixture.id(200)), 0)
            }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.store.putDelegation(f.native, f.delegation().copy(grantRevision = 2), 1) }
            assertThat(bytes(f)).isEqualTo(before)
            assertThat(f.restart().discover(f.peerContext, f.discoveryRequest()).authorityReferences).hasSize(31)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) {
                f.restart().plan(f.peerContext, f.request(f.restart().discover(f.peerContext, f.discoveryRequest())))
            }
        }
    }

    @Test
    fun concurrentNativeGrantRevisionCasHasExactlyOneWinnerAcrossStoreInstances() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val pool = Executors.newFixedThreadPool(4)
            try {
                val results = (1..8).map {
                    pool.submit<AgentBridgeErrorCode?> {
                        try {
                            AgentBridgeExportAuthorityStore.inPrivateDirectory(f.parent, f.keys).putDelegation(f.native, f.delegation().copy(grantRevision = 2), 1)
                            null
                        } catch (e: AgentBridgeException) { e.code }
                    }
                }.map { it.get(30, TimeUnit.SECONDS) }
                assertThat(results.count { it == null }).isEqualTo(1)
                assertThat(results.filterNotNull()).containsExactlyElementsIn(List(7) { AgentBridgeErrorCode.REVISION_CONFLICT })
                assertThat(f.restart().discover(f.peerContext, f.discoveryRequest()).authorityReferences.single().grantRevision).isEqualTo(2)
            } finally { pool.shutdownNow() }
        }
    }

    private fun ledger(f: AgentBridgeExportPlanningFixture): Path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
    private fun bytes(f: AgentBridgeExportPlanningFixture) = Files.readAllBytes(ledger(f))
    private fun rewriteWithSyntheticMac(f: AgentBridgeExportPlanningFixture, mutate: (JsonObject) -> JsonObject) {
        val root = Json.parseToJsonElement(bytes(f).decodeToString()).jsonObject
        val state = mutate(root.getValue("state").jsonObject)
        val bytes = AgentBridgeCodec.canonicalize(state.toString().toByteArray())
        val mac = Mac.getInstance("HmacSHA256").apply {
            init(requireNotNull(f.keys.key)); update("HealthMd.AgentBridge.AndroidExportAuthorityStore.v1\u0000".toByteArray())
        }.doFinal(bytes).joinToString("") { "%02x".format(it) }
        Files.write(ledger(f), AgentBridgeCodec.canonicalize(JsonObject(mapOf("state" to state, "mac" to JsonPrimitive(mac))).toString().toByteArray()))
    }
}
