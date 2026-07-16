package com.healthmd.rawchanges

import android.content.Context
import com.fasterxml.jackson.databind.ObjectMapper
import com.google.common.truth.Truth.assertThat
import com.healthmd.rawexport.HealthConnectRecordCatalog
import com.healthmd.rawexport.RawAtomicExportSink
import com.healthmd.rawexport.RawEnumValue
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawExportItem
import com.healthmd.rawexport.RawExportStorage
import com.healthmd.rawexport.RawExportTypeCatalog
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawJson
import com.healthmd.rawexport.RawHealthConnectMapper
import com.healthmd.rawexport.RawHealthRepository
import com.healthmd.rawexport.RawMetadata
import com.healthmd.rawexport.RawProviderCapabilities
import com.healthmd.rawexport.RawRecord
import com.healthmd.rawexport.RawSnapshotExportOrchestrator
import com.healthmd.rawexport.RawSnapshotRequest
import com.healthmd.rawexport.RawSnapshotScope
import com.healthmd.rawexport.RawSnapshotStatus
import com.healthmd.rawexport.RawTypeReport
import com.healthmd.rawexport.RawTypeStatus
import com.healthmd.rawexport.withCanonicalIdentityAndHash
import com.networknt.schema.JsonSchemaFactory
import com.networknt.schema.SpecVersion
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Metadata
import io.mockk.every
import io.mockk.mockk
import java.io.File
import java.io.RandomAccessFile
import java.time.Instant
import java.util.ArrayDeque
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
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
        val changed = record("new", 2).copy(wireType = "weight").withCanonicalIdentityAndHash()
        val source = FakeSource().apply {
            pages += NativeChangesPage(
                listOf(NativeChange.Upsert(changed)), SecretChangesToken("page-2"), true, false,
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
            RawJson.codec.encodeToJsonElement(RawRecord.serializer(), changed),
        )
        val known = archiveEvents[1].jsonObject
        assertThat(known.getValue("wireType").jsonPrimitive.content).isEqualTo("steps")
        assertThat(known.getValue("dataOriginPackageName").jsonPrimitive.content).isEqualTo("example.health")
        val unknown = archiveEvents[2].jsonObject
        assertThat(unknown.getValue("wireType")).isEqualTo(JsonNull)
        assertThat(unknown.getValue("dataOriginPackageName")).isEqualTo(JsonNull)
        val manifest = root.getValue("manifest").jsonObject
        assertThat(manifest.getValue("unknownDeletionCount").jsonPrimitive.content.toLong()).isEqualTo(1)
        assertThat(manifest.getValue("typeCounts").jsonArray.map { it.jsonObject.getValue("wireType").jsonPrimitive.content })
            .containsExactly("steps", "unknown_deletion", "weight").inOrder()
        assertThat(source.maxReturnedPageSize).isEqualTo(2)
        assertThat(harness.state.chain!!.token.value).isEqualTo("terminal")
    }

    @Test fun generatedArchiveValidatesAgainstPublishedDraft202012Schema() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("terminal"), false, false)
        }
        val result = harness(source).service.bootstrap(scope()) { durableReceipt() } as RawChangesResult.Complete
        val schemaFile = repoFile("docs/export-contract/schemas/healthmd.raw_changes.v1.schema.json")
        val schema = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012).getSchema(schemaFile.toURI())
        val document = ObjectMapper().readTree(File(result.archive.location))

        assertThat(schema.validate(document)).isEmpty()
    }

    @Test fun terminalTokenReceiptMetadataIsCommittedButHeaderDescribesConsumedToken() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("bootstrap-terminal"), false, false)
        }
        val harness = harness(source)
        val first = harness.service.bootstrap(scope()) { durableReceipt() } as RawChangesResult.Complete
        val firstHeader = archiveRoot(first).getValue("header").jsonObject
        assertThat(firstHeader.getValue("tokenSemantics").jsonObject.getValue("generatedBeforeBaseSnapshot").jsonPrimitive.content)
            .isEqualTo("true")
        assertThat(harness.state.chain!!.tokenGeneratedBeforeBase).isFalse()
        assertThat(harness.state.chain!!.tokenGeneratedAtEpochSecond).isEqualTo(1_700_000_002L)

        source.pages += NativeChangesPage(emptyList(), SecretChangesToken("append-terminal"), false, false)
        val second = harness.service.append(scope()) as RawChangesResult.Complete
        val consumed = archiveRoot(second).getValue("header").jsonObject.getValue("tokenSemantics").jsonObject
        assertThat(consumed.getValue("generatedBeforeBaseSnapshot").jsonPrimitive.content).isEqualTo("false")
        assertThat(consumed.getValue("generatedAt").jsonObject.getValue("epochSecond").jsonPrimitive.content.toLong())
            .isEqualTo(1_700_000_002L)
        assertThat(harness.state.chain!!.tokenGeneratedAtEpochSecond).isEqualTo(1_700_000_005L)
    }

    @Test fun repeatedTombstonesKeepLatestStagedIdentityInsteadOfStaleCommittedIdentity() = runTest {
        val latest = record("same", 9)
        val stale = record("same", 1)
        val source = FakeSource().apply {
            pages += NativeChangesPage(
                listOf(NativeChange.Upsert(latest), NativeChange.Delete("same"), NativeChange.Delete("same")),
                SecretChangesToken("terminal"), false, false,
            )
        }
        val result = harness(source).service.bootstrap(scope()) { index ->
            index.record(stale)
            durableReceipt()
        } as RawChangesResult.Complete
        val deletions = archiveRoot(result).getValue("events").jsonArray.drop(1).map { it.jsonObject }

        assertThat(deletions.map { it.getValue("lastKnownRecordHash").jsonPrimitive.content })
            .containsExactly(latest.hash, latest.hash)
        assertThat(archiveRoot(result).getValue("manifest").jsonObject.getValue("unknownDeletionCount").jsonPrimitive.content)
            .isEqualTo("0")
    }

    @Test fun rebaseSequenceOneDoesNotResolveOrRetainStaleChainIdentities() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("first-terminal"), false, false)
        }
        val harness = harness(source)
        harness.service.bootstrap(scope()) { index ->
            index.record(record("old-deleted", 1))
            index.record(record("old-untouched", 2))
            durableReceipt()
        } as RawChangesResult.Complete

        source.pages += NativeChangesPage(
            listOf(NativeChange.Delete("old-deleted")), SecretChangesToken("rebased-terminal"), false, false,
        )
        val rebased = harness.service.bootstrap(scope()) { index ->
            index.record(record("new-base", 3))
            durableReceipt()
        } as RawChangesResult.Complete

        val deletion = RawJson.codec.parseToJsonElement(File(rebased.archive.location).readText()).jsonObject
            .getValue("events").jsonArray.single().jsonObject
        assertThat(deletion.getValue("wireType")).isEqualTo(JsonNull)
        assertThat(deletion.getValue("lastKnownRecordHash")).isEqualTo(JsonNull)
        assertThat(harness.state.identities.keys).containsExactly("new-base")
    }

    @Test fun gatedUnavailableScopeReturnsStructuredResultWithoutTokenOrArtifact() = runTest {
        val source = FakeSource().apply {
            capabilitiesOverride = RawProviderCapabilities(
                available = true,
                grantedPermissions = HealthConnectRecordCatalog.records.mapTo(sortedSetOf()) { it.readPermission },
                availableFeatures = emptySet(),
            )
        }
        val harness = harness(source)
        val result = harness.service.bootstrap(RawChangesScope(setOf("planned_exercise_session"))) { durableReceipt() }

        assertThat(result).isEqualTo(
            RawChangesResult.UnavailableScope(
                recordTypeKeys = listOf("planned_exercise_session"),
                requiredFeatures = listOf("planned_exercise"),
            ),
        )
        assertThat(source.createTokenCalls).isEqualTo(0)
        assertThat(harness.state.pendingValue).isNull()
        assertThat(File(harness.root, "raw-changes/archives").listFiles().orEmpty()).isEmpty()
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

    @Test fun bootstrapRejectsPartialBoundedAndScopeMismatchedReceiptsBeforeCatchup() = runTest {
        val invalid = listOf(
            durableReceipt().copy(status = RawSnapshotStatus.PARTIAL),
            durableReceipt().copy(historicalCoverage = RawBaseHistoricalCoverage.BOUNDED_DATE_RANGE),
            durableReceipt().copy(recordTypeKeys = setOf("weight")),
            durableReceipt().copy(dataOriginPackageNames = setOf("other.origin")),
        )
        invalid.forEach { receipt ->
            val harness = harness(FakeSource())
            assertThat(runCatching { harness.service.bootstrap(scope()) { receipt } }.exceptionOrNull())
                .isInstanceOf(IllegalArgumentException::class.java)
            assertThat(harness.state.chain).isNull()
            assertThat(harness.state.pendingValue).isNull()
        }
    }

    @Test fun baseReceiptVerifierRejectsUnverifiedArtifactAndSidecar() {
        val artifact = temporary.newFile("base.json").apply { writeText("{}") }
        val sidecar = File(artifact.parentFile, "${artifact.name}.sha256").apply {
            writeText("${RawJson.sha256(artifact.readBytes())}  ${artifact.name}\n")
        }
        val receipt = durableReceipt().copy(
            artifactPath = artifact.absolutePath,
            sidecarPath = sidecar.absolutePath,
            artifactChecksumSha256 = RawJson.sha256(artifact.readBytes()),
        )
        assertThat(runCatching { DefaultRawBaseSnapshotReceiptVerifier.verify(receipt) }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
    }

    @Test fun baseReceiptVerifierAcceptsGeneratedCompleteArtifactAndBindsManifestIdentity() = runTest {
        val receipt = generatedBaseReceipt()
        DefaultRawBaseSnapshotReceiptVerifier.verify(receipt)

        assertThat(runCatching {
            DefaultRawBaseSnapshotReceiptVerifier.verify(receipt.copy(snapshotId = "different-snapshot"))
        }.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching {
            DefaultRawBaseSnapshotReceiptVerifier.verify(receipt.copy(logicalChecksumSha256 = "0".repeat(64)))
        }.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test fun sameScopeOperationsAreSerializedFromRecoveryThroughCommit() = runTest {
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("first"), false, false)
            pages += NativeChangesPage(emptyList(), SecretChangesToken("second"), false, false)
        }
        val harness = harness(source)
        val first = async {
            harness.service.bootstrap(scope()) {
                entered.complete(Unit)
                release.await()
                durableReceipt()
            }
        }
        entered.await()
        val second = async { harness.service.bootstrap(scope()) { durableReceipt() } }
        runCurrent()
        assertThat(source.createTokenCalls).isEqualTo(1)
        release.complete(Unit)

        assertThat(first.await()).isInstanceOf(RawChangesResult.Complete::class.java)
        assertThat(second.await()).isInstanceOf(RawChangesResult.Complete::class.java)
        assertThat(source.createTokenCalls).isEqualTo(2)
    }

    @Test fun stateConflictReturnsSanitizedConflictWithoutAdvancingToken() = runTest {
        val source = FakeSource(initialToken = "never-expose-this-token")
        val harness = harness(source)
        harness.state.conflictOnBegin = true
        val result = harness.service.bootstrap(scope()) { durableReceipt() }

        assertThat(result).isEqualTo(RawChangesResult.Conflict(RawChangesCanonical.scopeHash(scope())))
        assertThat(result.toString()).doesNotContain("never-expose-this-token")
        assertThat(harness.state.chain).isNull()
    }

    @Test fun phaseCasRejectsCrossWiredArchiveIdentityAndSequence() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("terminal"), false, false)
        }
        val harness = harness(source, RawChangesDurabilityHook { point ->
            if (point == RawChangesDurabilityPoint.PREPARED) throw SimulatedCrash()
        })
        runCatching { harness.service.bootstrap(scope()) { durableReceipt() } }
        val actual = requireNotNull(harness.state.pendingValue)
        val crossWired = actual.copy(archiveId = "different-archive", sequence = actual.sequence + 1)

        assertThat(runCatching { harness.state.markPromoted(crossWired) }.exceptionOrNull())
            .isInstanceOf(RawChangesStateConflictException::class.java)
        assertThat(harness.state.pendingValue).isEqualTo(actual)
    }

    @Test fun activePendingOwnedByAnotherProcessStyleLockReturnsConflict() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("terminal"), false, false)
        }
        val harness = harness(source, RawChangesDurabilityHook { point ->
            if (point == RawChangesDurabilityPoint.PREPARED) throw SimulatedCrash()
        })
        runCatching { harness.service.bootstrap(scope()) { durableReceipt() } }
        val work = requireNotNull(File(requireNotNull(harness.state.pendingValue).workDatabasePath).parentFile)
        val lockFile = RandomAccessFile(File(work, ".active.lock"), "rw")
        val lock = lockFile.channel.lock()
        try {
            val result = harness.service.bootstrap(scope()) { durableReceipt() }
            assertThat(result).isEqualTo(RawChangesResult.Conflict(RawChangesCanonical.scopeHash(scope())))
        } finally {
            lock.release()
            lockFile.close()
        }
    }

    @Test fun parentDirectorySyncFailureFailsClosedBeforeTokenCommit() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("must-not-commit"), false, false)
        }
        val harness = harness(source, directorySync = { throw java.io.IOException("directory sync unsupported") })
        assertThat(runCatching { harness.service.bootstrap(scope()) { durableReceipt() } }.exceptionOrNull())
            .isInstanceOf(java.io.IOException::class.java)
        assertThat(harness.state.chain).isNull()
        assertThat(harness.state.pendingValue?.phase).isEqualTo(PendingPhase.PREPARED)
    }

    @Test fun staleCheckpointGcPreservesReferencedAndActivelyLockedRuns() = runTest {
        val source = FakeSource().apply {
            pages += NativeChangesPage(emptyList(), SecretChangesToken("terminal"), false, false)
        }
        var crash = true
        val harness = harness(source, RawChangesDurabilityHook { point ->
            if (crash && point == RawChangesDurabilityPoint.PREPARED) {
                crash = false
                throw SimulatedCrash()
            }
        })
        runCatching { harness.service.bootstrap(scope()) { durableReceipt() } }
        val referenced = requireNotNull(File(requireNotNull(harness.state.pendingValue).workDatabasePath).parentFile)
        val stale = File(harness.root, "raw-changes/checkpoints/stale-after-db-commit").apply { mkdirs() }
        File(stale, "run-index.db").writeText("stale")
        val active = File(harness.root, "raw-changes/checkpoints/active-run").apply { mkdirs() }
        val activeFile = RandomAccessFile(File(active, ".active.lock"), "rw")
        val activeLock = activeFile.channel.lock()

        harness.service.garbageCollectStaleCheckpoints()
        assertThat(stale.exists()).isFalse()
        assertThat(referenced.exists()).isTrue()
        assertThat(active.exists()).isTrue()
        activeLock.release()
        activeFile.close()
        harness.service.garbageCollectStaleCheckpoints()
        assertThat(active.exists()).isFalse()
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
        assertThat(RawChangesCanonical.signed(unsigned).eventHash)
            .isEqualTo("9fb4ea3c170a86f5d1a5a884c5e8c12518e2a27ca3021a91891310f30af0290e")
        val independentEligibilityFixture = requireNotNull(
            javaClass.getResource("/raw-export/v1/changes-eligible-wire-types.txt"),
        ).readText().lineSequence().filter(String::isNotBlank).toList()
        assertThat(HealthConnectChangesSource.changeEligibleTypeKeys)
            .containsExactlyElementsIn(independentEligibilityFixture).inOrder()
        assertThat(HealthConnectChangesSource.changeEligibleTypeKeys).hasSize(42)
        assertThat(HealthConnectChangesSource.changeEligibleTypeKeys).doesNotContain("medical_resource")
    }

    private fun eventHashes(result: RawChangesResult.Complete): List<String> =
        archiveRoot(result).getValue("events").jsonArray.map { it.jsonObject.getValue("eventHash").jsonPrimitive.content }

    private fun archiveRoot(result: RawChangesResult.Complete) =
        RawJson.codec.parseToJsonElement(File(result.archive.location).readText()).jsonObject

    private fun repoFile(path: String): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            File(directory, path).takeIf(File::exists)?.let { return it }
            directory = directory.parentFile
        }
        error("Could not locate $path")
    }

    private fun harness(
        source: FakeSource,
        hook: RawChangesDurabilityHook = RawChangesDurabilityHook { },
        directorySync: (File) -> Unit = { directory ->
            java.nio.channels.FileChannel.open(directory.toPath(), java.nio.file.StandardOpenOption.READ).use { it.force(true) }
        },
    ): Harness {
        val root = temporary.newFolder("harness-${System.nanoTime()}")
        val context = mockk<Context> { every { noBackupFilesDir } returns root }
        val state = FakeState()
        val indexes = mutableMapOf<String, FakeIndex>()
        var tick = 1_700_000_000L
        val service = DefaultRawChangesService(
            context = context,
            source = source,
            state = state,
            destination = NoBackupRawChangesDestination(root, true, directorySync),
            clock = { Instant.ofEpochSecond(tick++) },
            hook = hook,
            baseSnapshotVerifier = RawBaseSnapshotReceiptVerifier { },
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
        var capabilitiesOverride: RawProviderCapabilities? = null

        override suspend fun capabilities() = capabilitiesOverride ?: RawProviderCapabilities(
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
        var conflictOnBegin = false

        override fun load(scopeHash: String) = chain?.takeIf { it.scopeHash == scopeHash }
        override fun identity(scopeHash: String, nativeRecordId: String) = identities[nativeRecordId]
        override fun pending(scopeHash: String) = pendingValue?.takeIf { it.scopeHash == scopeHash }
        override fun allPending() = listOfNotNull(pendingValue)
        override fun beginPending(pending: PendingArchive, initialToken: SecretChangesToken) {
            if (conflictOnBegin || pendingValue != null) throw RawChangesStateConflictException()
            val expected = chain
            if (expected?.chainId != pending.expectedChainId || expected?.sequence != pending.expectedSequence ||
                expected?.previousLogicalHash != pending.expectedLogicalHash
            ) throw RawChangesStateConflictException()
            pendingValue = pending
        }
        override fun prepared(pending: PendingArchive, artifactPath: String, logicalHash: String, artifactHash: String) {
            val actual = requireOwned(pending, PendingPhase.READING)
            pendingValue = actual.copy(
                artifactPath = artifactPath, logicalHash = logicalHash,
                artifactHash = artifactHash, phase = PendingPhase.PREPARED,
            )
        }
        override fun markPromoted(pending: PendingArchive) {
            pendingValue = requireOwned(pending, PendingPhase.PREPARED).copy(phase = PendingPhase.PROMOTED)
        }
        override fun markSidecarDurable(pending: PendingArchive, sidecarPath: String) {
            pendingValue = requireOwned(pending, PendingPhase.PROMOTED).copy(sidecarPath = sidecarPath, phase = PendingPhase.SIDECAR_DURABLE)
        }
        override fun commit(
            pending: PendingArchive,
            scopeJson: String,
            nextToken: SecretChangesToken,
            nextTokenReceivedEpochSecond: Long,
            nextTokenReceivedNano: Int,
            mutations: Sequence<IdentityMutation>,
        ) {
            requireOwned(pending, PendingPhase.SIDECAR_DURABLE)
            val next = if (pending.sequence == 1L) LinkedHashMap() else LinkedHashMap(identities)
            mutations.forEach { mutation ->
                when (mutation) {
                    is IdentityMutation.Upsert -> next[mutation.nativeRecordId] = mutation.identity
                    is IdentityMutation.Delete -> next.remove(mutation.nativeRecordId)
                }
            }
            identities.clear(); identities.putAll(next)
            chain = RawChangesChainState(
                pending.scopeHash, scopeJson, pending.chainId, pending.sequence, pending.logicalHash,
                nextToken, nextTokenReceivedEpochSecond,
                nextTokenReceivedNano, false,
            )
            pendingValue = null
        }
        override fun discardPending(pending: PendingArchive) {
            requireOwned(pending, requireNotNull(pendingValue).phase)
            pendingValue = null
        }

        private fun requireOwned(pending: PendingArchive, phase: PendingPhase): PendingArchive {
            val actual = pendingValue
            if (actual?.archiveId != pending.archiveId || actual.chainId != pending.chainId ||
                actual.sequence != pending.sequence || actual.phase != phase
            ) throw RawChangesStateConflictException()
            return actual
        }
    }

    private class FakeIndex(
        private val scopeHash: String,
        private val fallback: (String, String) -> RawNativeIdentity?,
    ) : RawChangesMutableIndex {
        private val current = linkedMapOf<String, RawNativeIdentity>()
        private val deleted = linkedMapOf<String, RawNativeIdentity?>()
        private val journal = mutableListOf<IdentityMutation>()
        override fun record(record: RawRecord) = upsert(record)
        override fun lookup(nativeRecordId: String) = current[nativeRecordId]
            ?: if (deleted.containsKey(nativeRecordId)) deleted[nativeRecordId] else fallback(scopeHash, nativeRecordId)
        override fun upsert(record: RawRecord) {
            val metadata = requireNotNull(record.metadata)
            val identity = RawNativeIdentity(metadata.id, record.wireType, record.wireType, metadata.dataOriginPackageName, record.hash)
            current[metadata.id] = identity
            deleted.remove(metadata.id)
            journal += IdentityMutation.Upsert(identity)
        }
        override fun delete(nativeRecordId: String): RawNativeIdentity? {
            val known = lookup(nativeRecordId)
            current.remove(nativeRecordId)
            deleted[nativeRecordId] = known
            journal += IdentityMutation.Delete(nativeRecordId)
            return known
        }
        override fun mutations(): Sequence<IdentityMutation> = journal.asSequence()
        override fun close() = Unit
    }

    private class TestRawExportStorage(private val directory: File) : RawExportStorage {
        override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink {
            directory.mkdirs()
            val partial = File(directory, "$snapshotId.partial")
            val final = File(directory, "$snapshotId.${format.name.lowercase()}")
            return object : RawAtomicExportSink {
                override val output = partial.outputStream()
                override val partialLocation = partial.absolutePath
                override fun close() = output.close()
                override fun promote(): String {
                    close()
                    check(partial.renameTo(final))
                    return final.absolutePath
                }
                override fun abort() {
                    runCatching { close() }
                    partial.delete()
                }
            }
        }
    }

    private suspend fun generatedBaseReceipt(): RawBaseSnapshotReceipt {
        val root = temporary.newFolder("generated-base")
        val repository = object : RawHealthRepository {
            override suspend fun capabilities() = RawProviderCapabilities(available = true)
            override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = flow {
                emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
                RawExportTypeCatalog.definitions.forEach { definition ->
                    emit(RawExportItem.TypeReport(RawTypeReport(
                        typeKey = definition.typeKey,
                        wireType = definition.wireType,
                        status = if (definition.typeKey == "steps") RawTypeStatus.EXPORTED else RawTypeStatus.NOT_SELECTED,
                        permission = definition.permission,
                        feature = definition.feature,
                        rangeBehavior = definition.rangeBehavior,
                    )))
                }
                emit(RawExportItem.Status(RawSnapshotStatus.COMPLETE))
            }
        }
        val result = RawSnapshotExportOrchestrator(
            repository = repository,
            storage = TestRawExportStorage(File(root, "out")),
            spoolRoot = File(root, "spool"),
            clock = { Instant.ofEpochSecond(100) },
        ).export(RawSnapshotRequest(
            format = RawExportFormat.JSON,
            scope = RawSnapshotScope.SELECTED_RECORD_TYPES,
            startTime = RawInstant(0, 0),
            endTime = RawInstant(200, 0),
            selectedMetricIds = setOf("steps"),
        ))
        val artifact = File(result.finalLocation)
        val sidecar = File(artifact.parentFile, "${artifact.name}.sha256").apply {
            writeText("${result.artifactChecksumSha256}  ${artifact.name}\n")
        }
        return durableReceipt().copy(
            snapshotId = result.snapshotId,
            artifactPath = artifact.absolutePath,
            sidecarPath = sidecar.absolutePath,
            logicalChecksumSha256 = result.manifest.logicalChecksumSha256,
            artifactChecksumSha256 = result.artifactChecksumSha256,
        )
    }

    private class SimulatedCrash : RuntimeException()

    private fun scope() = RawChangesScope(setOf("steps"))
    private fun durableReceipt() = RawBaseSnapshotReceipt(
        snapshotId = "base",
        schema = "healthmd.raw-snapshot",
        version = 1,
        status = RawSnapshotStatus.COMPLETE,
        recordTypeKeys = setOf("steps"),
        dataOriginPackageNames = emptySet(),
        historicalCoverage = RawBaseHistoricalCoverage.UNBOUNDED_ALL_READABLE_WITHIN_SCOPE,
        format = RawExportFormat.JSON,
        artifactPath = "/verified/base.json",
        sidecarPath = "/verified/base.json.sha256",
        logicalChecksumSha256 = "a".repeat(64),
        artifactChecksumSha256 = "b".repeat(64),
    )

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
