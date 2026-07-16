package com.healthmd.rawchanges

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.rawexport.HealthConnectRecordCatalog
import com.healthmd.rawexport.RawEnumValue
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawJson
import com.healthmd.rawexport.RawHealthConnectMapper
import com.healthmd.rawexport.RawMetadata
import com.healthmd.rawexport.RawProviderCapabilities
import com.healthmd.rawexport.RawRecord
import com.healthmd.rawexport.withCanonicalIdentityAndHash
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Metadata
import io.mockk.every
import io.mockk.mockk
import java.io.File
import java.time.Instant
import java.util.ArrayDeque
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RawChangesServiceTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun bootstrapGetsTokenBeforeSnapshotAndCatchupPreventsConcurrentMiss() = runTest {
        val events = mutableListOf<String>()
        val source = FakeSource(events = events).apply {
            pages += NativeChangesPage(
                listOf(NativeChange.Upsert(record("concurrent", 2))), SecretChangesToken("after-catchup"), false, false,
            )
        }
        val harness = harness(source)
        val result = harness.service.bootstrap(scope()) { index ->
            events += "snapshot"
            index.record(record("base", 1))
            durableReceipt()
        }

        assertThat(events).containsExactly("token", "snapshot", "page").inOrder()
        val complete = result as RawChangesResult.Complete
        val root = RawJson.codec.parseToJsonElement(File(complete.archive.location).readText()).jsonObject
        assertThat(root.getValue("events").jsonArray).hasSize(1)
        assertThat(harness.state.identities.keys).containsAtLeast("base", "concurrent")
        assertThat(harness.state.chain!!.token.value).isEqualTo("after-catchup")
    }

    @Test fun paginationEmitsEquivalentUpsertKnownAndUnknownDeletionWithBoundedPages() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(
                listOf(NativeChange.Upsert(record("new", 2))), SecretChangesToken("page-2"), true, false,
            )
            pages += NativeChangesPage(
                listOf(NativeChange.Delete("old"), NativeChange.Delete("never-seen")),
                SecretChangesToken("terminal"), false, false,
            )
        }
        val harness = harness(source)
        val result = harness.service.bootstrap(scope()) { index ->
            index.record(record("old", 1))
            durableReceipt()
        } as RawChangesResult.Complete

        val root = RawJson.codec.parseToJsonElement(File(result.archive.location).readText()).jsonObject
        val archiveEvents = root.getValue("events").jsonArray
        assertThat(archiveEvents).hasSize(3)
        val upsert = archiveEvents[0].jsonObject
        assertThat(upsert.getValue("record")).isEqualTo(
            RawJson.codec.encodeToJsonElement(RawRecord.serializer(), record("new", 2)),
        )
        val known = archiveEvents[1].jsonObject
        assertThat(known.getValue("wireType").jsonPrimitive.content).isEqualTo("steps")
        assertThat(known.getValue("dataOriginPackageName").jsonPrimitive.content).isEqualTo("example.health")
        val unknown = archiveEvents[2].jsonObject
        assertThat(unknown.getValue("wireType")).isEqualTo(JsonNull)
        assertThat(unknown.getValue("dataOriginPackageName")).isEqualTo(JsonNull)
        assertThat(root.getValue("manifest").jsonObject.getValue("unknownDeletionCount").jsonPrimitive.content.toLong()).isEqualTo(1)
        assertThat(source.maxReturnedPageSize).isEqualTo(2)
        assertThat(harness.state.chain!!.token.value).isEqualTo("terminal")
    }

    @Test fun expiredTokenReturnsRebaseWithoutArchiveOrStateMutation() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), null, false, true)
        }
        val harness = harness(source)
        val result = harness.service.bootstrap(scope()) { durableReceipt() }
        assertThat(result).isInstanceOf(RawChangesResult.RebaseRequired::class.java)
        assertThat(harness.state.chain).isNull()
        assertThat(harness.state.identities).isEmpty()
        assertThat(File(harness.root, "raw-changes/archives").listFiles().orEmpty()).isEmpty()
    }

    @Test fun crashBeforePromotionReplaysPriorTokenWithoutSkipping() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(listOf(NativeChange.Upsert(record("one", 1))), SecretChangesToken("next"), false, false)
        }
        var crashed = false
        val harness = harness(source, RawChangesDurabilityHook { point ->
            if (!crashed && point == RawChangesDurabilityPoint.PREPARED) {
                crashed = true
                throw SimulatedCrash()
            }
        })
        assertThat(runCatching { harness.service.bootstrap(scope()) { durableReceipt() } }.exceptionOrNull())
            .isInstanceOf(SimulatedCrash::class.java)
        assertThat(harness.state.chain).isNull()
        source.pages += NativeChangesPage(listOf(NativeChange.Upsert(record("one", 1))), SecretChangesToken("next"), false, false)
        val recovered = harness.service.bootstrap(scope()) { durableReceipt() }
        assertThat(recovered).isInstanceOf(RawChangesResult.Complete::class.java)
        assertThat(source.createTokenCalls).isEqualTo(2)
        assertThat(source.pageCalls).isEqualTo(2)
        assertThat(harness.state.chain!!.token.value).isEqualTo("next")
    }

    @Test fun crashImmediatelyAfterPromotionReplaysPriorTokenAndKeepsOldState() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(listOf(NativeChange.Upsert(record("one", 1))), SecretChangesToken("next"), false, false)
        }
        var crashed = false
        val harness = harness(source, RawChangesDurabilityHook { point ->
            if (!crashed && point == RawChangesDurabilityPoint.PROMOTED) {
                crashed = true
                throw SimulatedCrash()
            }
        })
        runCatching { harness.service.bootstrap(scope()) { durableReceipt() } }
        assertThat(harness.state.chain).isNull()
        assertThat(harness.state.identities).isEmpty()
        source.pages += NativeChangesPage(listOf(NativeChange.Upsert(record("one", 1))), SecretChangesToken("next"), false, false)
        val recovered = harness.service.bootstrap(scope()) { durableReceipt() }
        assertThat(recovered).isInstanceOf(RawChangesResult.Complete::class.java)
        assertThat(source.pageCalls).isEqualTo(2)
        assertThat(harness.state.identities).containsKey("one")
    }

    @Test fun crashAfterPromotionBeforeTokenCommitReplaysDuplicateBeforeAdvancing() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(listOf(NativeChange.Upsert(record("one", 1))), SecretChangesToken("next"), false, false)
        }
        var crashed = false
        val harness = harness(source, RawChangesDurabilityHook { point ->
            if (!crashed && point == RawChangesDurabilityPoint.BEFORE_STATE_COMMIT) {
                crashed = true
                throw SimulatedCrash()
            }
        })
        runCatching { harness.service.bootstrap(scope()) { durableReceipt() } }
        val promoted = File(harness.root, "raw-changes/archives").listFiles().orEmpty().single { it.extension == "json" }
        val originalEventHash = RawJson.codec.parseToJsonElement(promoted.readText()).jsonObject
            .getValue("events").jsonArray.single().jsonObject.getValue("eventHash").jsonPrimitive.content
        assertThat(harness.state.identities).isEmpty()

        source.pages += NativeChangesPage(listOf(NativeChange.Upsert(record("one", 1))), SecretChangesToken("next"), false, false)
        val recovered = harness.service.bootstrap(scope()) { durableReceipt() } as RawChangesResult.Complete
        assertThat(eventHashes(recovered).single()).isEqualTo(originalEventHash)
        assertThat(harness.state.identities).containsKey("one")
        assertThat(source.pageCalls).isEqualTo(2)
    }

    @Test fun cancellationDiscardsCheckpointPartialTokenAndIndex() = runTest {
        val source = FakeSource().apply { failure = CancellationException("cancel") }
        val harness = harness(source)
        assertThat(runCatching { harness.service.bootstrap(scope()) { index ->
            index.record(record("base", 1)); durableReceipt()
        } }.exceptionOrNull()).isInstanceOf(CancellationException::class.java)
        assertThat(harness.state.pendingValue).isNull()
        assertThat(harness.state.chain).isNull()
        assertThat(harness.state.identities).isEmpty()
        assertThat(File(harness.root, "raw-changes/archives").listFiles().orEmpty()).isEmpty()
    }

    @Test fun chainSequencePreviousHashDuplicateReplayAndScopeGuardAreStable() = runTest {
        val duplicate = NativeChange.Upsert(record("same", 1))
        val source = FakeSource().apply {
            pages += NativeChangesPage(listOf(duplicate), SecretChangesToken("t1"), false, false)
        }
        val harness = harness(source)
        val first = harness.service.bootstrap(scope()) { durableReceipt() } as RawChangesResult.Complete
        source.pages += NativeChangesPage(listOf(duplicate), SecretChangesToken("t2"), false, false)
        val second = harness.service.append(scope(), first.archive.chainId) as RawChangesResult.Complete
        assertThat(second.archive.sequence).isEqualTo(2)
        val secondHeader = RawJson.codec.parseToJsonElement(File(second.archive.location).readText()).jsonObject.getValue("header").jsonObject
        assertThat(secondHeader.getValue("previousArchiveLogicalHash").jsonPrimitive.content)
            .isEqualTo(first.archive.logicalChecksumSha256)
        val firstEventHash = eventHashes(first).single()
        assertThat(eventHashes(second).single()).isEqualTo(firstEventHash)
        val mismatch = harness.service.append(scope(), expectedScopeHash = "0".repeat(64))
        assertThat(mismatch).isEqualTo(
            RawChangesResult.ScopeMismatch("0".repeat(64), RawChangesCanonical.scopeHash(scope())),
        )
        val chainMismatch = harness.service.append(scope(), expectedChainId = "wrong-chain")
        assertThat(chainMismatch).isInstanceOf(RawChangesResult.ScopeMismatch::class.java)
    }

    @Test fun tokenNeverLeaksToArtifactsSidecarsOrErrors() = runTest {
        val secret = "opaque-secret-token-DO-NOT-LEAK"
        val source = FakeSource(initialToken = secret).apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("next-secret-token"), false, false)
        }
        val harness = harness(source)
        harness.service.bootstrap(scope()) { durableReceipt() }
        File(harness.root, "raw-changes").walkTopDown().filter(File::isFile).forEach { file ->
            // Fake state is memory-only; production ciphertext is tested by construction/contract.
            assertThat(file.readBytes().toString(Charsets.ISO_8859_1)).doesNotContain(secret)
            assertThat(file.readBytes().toString(Charsets.ISO_8859_1)).doesNotContain("next-secret-token")
        }
        val failure = RawChangesProviderException("Health Connect incremental changes read failed.")
        assertThat(failure.message).doesNotContain(secret)
        assertThat(SecretChangesToken(secret).toString()).doesNotContain(secret)
    }

    @Test fun changesUpsertionUsesTheExactSnapshotRawRecordMapper() {
        val native = StepsRecord(
            startTime = Instant.ofEpochSecond(10, 123),
            startZoneOffset = null,
            endTime = Instant.ofEpochSecond(20, 456),
            endZoneOffset = null,
            count = 42,
            metadata = Metadata.manualEntry(clientRecordId = "same-mapper", clientRecordVersion = 3),
        )
        val snapshotRepresentation = RawHealthConnectMapper.map(native, "steps")
        val descriptor = HealthConnectRecordCatalog.records.single { it.wireType == "steps" }
        val changesRepresentation = requireNotNull(descriptor.mapUntyped(native))
        assertThat(changesRepresentation).isEqualTo(snapshotRepresentation)
        val event = RawChangesCanonical.signed(RawChangeEvent.Upsertion(1, changesRepresentation, ""))
        assertThat((event as RawChangeEvent.Upsertion).record).isEqualTo(snapshotRepresentation)
    }

    @Test fun scopeAndEventHashesAreDeterministicAndCatalogIsChangesComplete() {
        val a = RawChangesScope(linkedSetOf("steps", "heart_rate"), linkedSetOf("b.origin", "a.origin"))
        val b = RawChangesScope(linkedSetOf("heart_rate", "steps"), linkedSetOf("a.origin", "b.origin"))
        assertThat(RawChangesCanonical.scopeHash(a)).isEqualTo(RawChangesCanonical.scopeHash(b))
        val unsigned = RawChangeEvent.Upsertion(1, record("id", 1), "")
        assertThat(RawChangesCanonical.signed(unsigned).eventHash).isEqualTo(RawChangesCanonical.signed(unsigned).eventHash)
        assertThat(HealthConnectChangesSource.changeEligibleTypeKeys)
            .containsExactlyElementsIn(HealthConnectRecordCatalog.records.map { it.wireType })
        assertThat(HealthConnectChangesSource.changeEligibleTypeKeys).hasSize(42)
        assertThat(HealthConnectChangesSource.changeEligibleTypeKeys).doesNotContain("medical_resource")
    }

    private fun eventHashes(result: RawChangesResult.Complete): List<String> =
        RawJson.codec.parseToJsonElement(File(result.archive.location).readText()).jsonObject
            .getValue("events").jsonArray.map { it.jsonObject.getValue("eventHash").jsonPrimitive.content }

    private fun harness(source: FakeSource, hook: RawChangesDurabilityHook = RawChangesDurabilityHook { }): Harness {
        val root = temporary.newFolder("harness-${System.nanoTime()}")
        val context = mockk<Context> { every { noBackupFilesDir } returns root }
        val state = FakeState()
        val indexes = mutableMapOf<String, FakeIndex>()
        var tick = 1_700_000_000L
        val service = DefaultRawChangesService(
            context = context,
            source = source,
            state = state,
            destination = NoBackupRawChangesDestination(root, true),
            clock = { Instant.ofEpochSecond(tick++) },
            hook = hook,
            indexFactory = { file, scopeHash, lookup ->
                indexes.getOrPut(file.absolutePath) { FakeIndex(scopeHash, lookup) }
            },
        )
        return Harness(root, state, service)
    }

    private data class Harness(val root: File, val state: FakeState, val service: DefaultRawChangesService)

    private class FakeSource(
        private val initialToken: String = "initial-token",
        private val events: MutableList<String> = mutableListOf(),
    ) : RawChangesSource {
        val pages = ArrayDeque<NativeChangesPage>()
        var failure: Throwable? = null
        var createTokenCalls = 0
        var pageCalls = 0
        var maxReturnedPageSize = 0

        override suspend fun capabilities() = RawProviderCapabilities(
            available = true,
            grantedPermissions = HealthConnectRecordCatalog.records.mapTo(sortedSetOf()) { it.readPermission },
            availableFeatures = HealthConnectRecordCatalog.records.mapNotNullTo(sortedSetOf()) { it.featureName },
        )

        override suspend fun createToken(scope: RawChangesScope): SecretChangesToken {
            createTokenCalls++
            events += "token"
            return SecretChangesToken(initialToken)
        }

        override suspend fun getChanges(token: SecretChangesToken): NativeChangesPage {
            pageCalls++
            events += "page"
            failure?.let { throw it }
            return pages.removeFirst().also { maxReturnedPageSize = maxOf(maxReturnedPageSize, it.changes.size) }
        }
    }

    private class FakeState : RawChangesStateStore {
        var chain: RawChangesChainState? = null
        var pendingValue: PendingArchive? = null
        val identities = linkedMapOf<String, RawNativeIdentity>()

        override fun load(scopeHash: String) = chain?.takeIf { it.scopeHash == scopeHash }
        override fun identity(scopeHash: String, nativeRecordId: String) = identities[nativeRecordId]
        override fun pending(scopeHash: String) = pendingValue?.takeIf { it.scopeHash == scopeHash }
        override fun beginPending(pending: PendingArchive, initialToken: SecretChangesToken) { pendingValue = pending }
        override fun prepared(scopeHash: String, artifactPath: String, logicalHash: String, artifactHash: String) {
            pendingValue = requireNotNull(pendingValue).copy(
                artifactPath = artifactPath, logicalHash = logicalHash,
                artifactHash = artifactHash, phase = PendingPhase.PREPARED,
            )
        }
        override fun markPromoted(scopeHash: String) { pendingValue = requireNotNull(pendingValue).copy(phase = PendingPhase.PROMOTED) }
        override fun markSidecarDurable(scopeHash: String, sidecarPath: String) {
            pendingValue = requireNotNull(pendingValue).copy(sidecarPath = sidecarPath, phase = PendingPhase.SIDECAR_DURABLE)
        }
        override fun commit(
            pending: PendingArchive,
            scopeJson: String,
            nextToken: SecretChangesToken,
            mutations: Sequence<IdentityMutation>,
        ) {
            val next = LinkedHashMap(identities)
            mutations.forEach { mutation ->
                when (mutation) {
                    is IdentityMutation.Upsert -> next[mutation.nativeRecordId] = mutation.identity
                    is IdentityMutation.Delete -> next.remove(mutation.nativeRecordId)
                }
            }
            identities.clear(); identities.putAll(next)
            chain = RawChangesChainState(
                pending.scopeHash, scopeJson, pending.chainId, pending.sequence, pending.logicalHash,
                nextToken, pending.tokenGeneratedAtEpochSecond,
                pending.tokenGeneratedAtNano, pending.tokenGeneratedBeforeBase,
            )
            pendingValue = null
        }
        override fun discardPending(scopeHash: String) { pendingValue = null }
    }

    private class FakeIndex(
        private val scopeHash: String,
        private val fallback: (String, String) -> RawNativeIdentity?,
    ) : RawChangesMutableIndex {
        private val current = linkedMapOf<String, RawNativeIdentity>()
        private val journal = mutableListOf<IdentityMutation>()
        override fun record(record: RawRecord) = upsert(record)
        override fun lookup(nativeRecordId: String) = current[nativeRecordId] ?: fallback(scopeHash, nativeRecordId)
        override fun upsert(record: RawRecord) {
            val metadata = requireNotNull(record.metadata)
            val identity = RawNativeIdentity(metadata.id, record.wireType, record.wireType, metadata.dataOriginPackageName, record.hash)
            current[metadata.id] = identity
            journal += IdentityMutation.Upsert(identity)
        }
        override fun delete(nativeRecordId: String): RawNativeIdentity? {
            val known = lookup(nativeRecordId)
            current.remove(nativeRecordId)
            journal += IdentityMutation.Delete(nativeRecordId)
            return known
        }
        override fun mutations(): Sequence<IdentityMutation> = journal.asSequence()
        override fun close() = Unit
    }

    private class SimulatedCrash : RuntimeException()

    private fun scope() = RawChangesScope(setOf("steps"))
    private fun durableReceipt() = RawBaseSnapshotReceipt("base", "a".repeat(64), "b".repeat(64), durable = true)

    private fun record(id: String, second: Long): RawRecord = RawRecord(
        wireType = "steps",
        nativeIdentity = "hc:$id",
        startTime = RawInstant(second, 0),
        metadata = RawMetadata(
            id = id,
            clientRecordVersion = 1,
            lastModifiedTime = RawInstant(second, 1),
            dataOriginPackageName = "example.health",
            recordingMethod = RawEnumValue(2, "automatically_recorded"),
        ),
        fields = kotlinx.serialization.json.buildJsonObject { put("count", kotlinx.serialization.json.JsonPrimitive(second)) },
        hash = "",
    ).withCanonicalIdentityAndHash()
}
