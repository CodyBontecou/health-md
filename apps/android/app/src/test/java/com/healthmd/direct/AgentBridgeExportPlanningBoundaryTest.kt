package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.*
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.serialization.json.*
import org.junit.Test

/** Actual production service/store/resolver boundaries; no native Context, key or health reads. */
class AgentBridgeExportPlanningBoundaryTest {
    @Test
    fun discoveryCoversEveryEffectivePresetLeafIncludingFixedDisabledOutputs() {
        AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val plan = f.service.plan(f.peerContext, f.request(discovery))
            assertThat(plan.effectiveSettings).isEqualTo(AgentBridgeExportPlanningFixture.output())
            assertThat(plan.predictedPaths).containsExactly("2026/2026-03-07.json", "2026/2026-03-08.json").inOrder()
            assertThat(discovery.outputSupport.settingPointers).containsExactlyElementsIn(PRESET_LEAVES).inOrder()
            assertThat(plan.origins.filter { it.pointer.startsWith("/effective_settings/") }.map {
                it.pointer.removePrefix("/effective_settings")
            }).containsExactlyElementsIn(PRESET_LEAVES).inOrder()
            assertThat(discovery.outputSupport.formats).containsExactly(AgentBridgeFormat.JSON)
            assertThat(discovery.outputSupport.writeModes).containsExactly(AgentBridgeWriteMode.OVERWRITE)
            assertThat(discovery.outputSupport.compatibilityDetail).containsExactly(AgentBridgeCompatibilityDetail.SUMMARY)
            assertThat(discovery.outputSupport.nativeArchiveProducts).containsExactly(AgentBridgeOutputSupportNativeArchiveProductsItem.NONE)
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun exactConsentDelayedToExpiryCannotPublishOrBackdateAnApproval() {
        for (expiry in listOf("2026-05-29T01:00:00Z", "2026-05-29T00:03:00Z")) {
            AgentBridgeExportPlanningFixture().use { f ->
                f.store.initialize(f.native)
                f.store.putDelegation(f.native, f.delegation(expiry), 0)
                val request = f.request(f.service.discover(f.peerContext, f.discoveryRequest()))
                val plan = f.service.plan(f.peerContext, request)
                val before = ledgerBytes(f)
                var consentCalls = 0
                f.native.afterDecision = { decision ->
                    if (decision is AgentBridgeExportNativeDecision.ExactApproval) {
                        consentCalls++
                        f.clock.now = Instant.parse(plan.expiresAt)
                    }
                }
                f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) {
                    f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
                }
                assertThat(consentCalls).isEqualTo(1)
                assertThat(ledgerBytes(f)).isEqualTo(before)
                assertThat(ledgerState(f).getValue("decisions").jsonArray).isEmpty()
                f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.restart().plan(f.peerContext, request) }
                f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.restart().approval(f.peerContext, f.approvalRequest(plan)) }
            }
        }
    }

    @Test
    fun finalTrustDelayBeforePlanPublicationRejectsBothPlanAndParentExpiry() {
        for (expiry in listOf("2026-05-29T01:00:00Z", "2026-05-29T00:03:00Z")) {
            AgentBridgeExportPlanningFixture().use { f ->
                f.store.initialize(f.native)
                f.store.putDelegation(f.native, f.delegation(expiry), 0)
                val request = f.request(f.service.discover(f.peerContext, f.discoveryRequest()))
                val before = ledgerBytes(f)
                val configurationCalls = f.configuration.calls
                var delayed = false
                f.peerContext.onCheck = {
                    if (!delayed && f.configuration.calls > configurationCalls) {
                        delayed = true
                        f.clock.now = minOf(f.clock.now.plusSeconds(600), Instant.parse(expiry))
                    }
                }
                f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.service.plan(f.peerContext, request) }
                assertThat(delayed).isTrue()
                assertThat(ledgerBytes(f)).isEqualTo(before)
                assertThat(ledgerState(f).getValue("plans").jsonArray).isEmpty()
            }
        }
    }

    @Test
    fun actualProtectedKeySigningDelayCannotPublishExpiredPlanOrExactDecision() {
        for (decision in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = if (decision) f.service.plan(f.peerContext, request) else null
            val expiry = plan?.expiresAt ?: "2026-05-29T00:10:00Z"
            val before = ledgerBytes(f)
            var encodes = 0
            var delayed = false
            f.keys.onEncode = {
                encodes++
                // Key validation, stored MAC verification, then the real new-snapshot MAC signing.
                if (encodes == 3) { delayed = true; f.clock.now = Instant.parse(expiry) }
            }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) {
                if (plan == null) f.service.plan(f.peerContext, request) else
                    f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            }
            assertThat(delayed).isTrue()
            assertThat(encodes).isAtLeast(3)
            assertThat(ledgerBytes(f)).isEqualTo(before)
            assertThat(ledgerState(f).getValue("decisions").jsonArray).isEmpty()
        }
    }

    @Test
    fun cachedPlanDecisionAndApprovalRelayCannotReturnAfterFinalTrustExpiry() {
        for (operation in listOf("plan", "decision", "relay")) AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = f.service.plan(f.peerContext, request)
            f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            val before = ledgerBytes(f)
            val calls = f.configuration.calls
            var delayed = false
            f.peerContext.onCheck = {
                if (!delayed && f.configuration.calls > calls) { delayed = true; f.clock.now = Instant.parse(plan.expiresAt) }
            }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) {
                when (operation) {
                    "plan" -> f.service.plan(f.peerContext, request)
                    "decision" -> f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
                    else -> f.service.approval(f.peerContext, f.approvalRequest(plan))
                }
            }
            assertThat(delayed).isTrue()
            assertThat(ledgerBytes(f)).isEqualTo(before)
            f.peerContext.onCheck = null
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.restart().approval(f.peerContext, f.approvalRequest(plan)) }
        }
    }

    @Test
    fun discoveryReturnChecksItsLifetimeAndEveryCurrentlyReferencedParent() {
        for (parentExpires in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            f.store.putDelegation(f.native, f.delegation(if (parentExpires) "2026-05-29T00:03:00Z" else "2026-05-29T01:00:00Z"), 0)
            val calls = f.configuration.calls
            val before = ledgerBytes(f)
            var delayed = false
            f.peerContext.onCheck = {
                if (!delayed && f.configuration.calls > calls) {
                    delayed = true
                    f.clock.now = f.clock.now.plusSeconds(if (parentExpires) 180 else 600)
                }
            }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.service.discover(f.peerContext, f.discoveryRequest()) }
            assertThat(delayed).isTrue()
            assertThat(ledgerBytes(f)).isEqualTo(before)
            f.peerContext.onCheck = null
            if (parentExpires) assertThat(f.restart().discover(f.peerContext, f.discoveryRequest()).authorityReferences).isEmpty()
        }
    }

    @Test
    fun postpublicationFinalReturnExpiryIsSeparateAndStoredStalePlanNeverBecomesPermission() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            var delayed = false
            f.peerContext.onCheck = {
                val plans = ledgerState(f).getValue("plans").jsonArray
                if (!delayed && plans.isNotEmpty()) {
                    delayed = true
                    val stored = AgentBridgeCodec.decode(plans.single().jsonObject.getValue("planCanonical").jsonPrimitive.content.toByteArray()) as AgentBridgeGeneratedPlan
                    f.clock.now = Instant.parse(stored.expiresAt)
                }
            }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.service.plan(f.peerContext, request) }
            assertThat(delayed).isTrue()
            // The clock crossed AFTER atomic publication, not a prepublication rollback proof.
            assertThat(ledgerState(f).getValue("plans").jsonArray).hasSize(1)
            assertThat(ledgerState(f).getValue("decisions").jsonArray).isEmpty()
            f.peerContext.onCheck = null
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.restart().plan(f.peerContext, request) }
        }
    }

    @Test
    fun advertisedFixedLeavesDoNotPermitNondefaultPresentationDisabledOutputsOrContainers() {
        AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val base = AgentBridgeExportPlanningFixture.output()
            val p = base.presentation
            val outputs = listOf(
                base.copy(formats = listOf(AgentBridgeFormat.CSV)),
                base.copy(writeMode = AgentBridgeWriteMode.APPEND),
                base.copy(outputProfile = AgentBridgeOutputProfile.ANDROID_ANALYTICAL_V5),
                base.copy(presentation = p.copy(displayUnits = AgentBridgePresentationDisplayUnits.IMPERIAL)),
                base.copy(presentation = p.copy(locale = "fr-FR")),
                base.copy(presentation = p.copy(includeMetadata = false)),
                base.copy(presentation = p.copy(groupByCategory = false)),
                base.copy(presentation = p.copy(frontmatter = p.frontmatter.copy(includeUnits = false))),
                base.copy(presentation = p.copy(frontmatter = p.frontmatter.copy(includeCaptureDiagnostics = true))),
                base.copy(presentation = p.copy(frontmatter = p.frontmatter.copy(enabledFieldIds = listOf("steps")))),
                base.copy(presentation = p.copy(frontmatter = p.frontmatter.copy(customFields = listOf(AgentBridgeFrontmatterCustomFieldsItem("reviewed", "inert"))))),
                base.copy(presentation = p.copy(markdown = p.markdown.copy(customTemplate = "inert"))),
                base.copy(presentation = p.copy(markdown = p.markdown.copy(placeholderIds = listOf("steps")))),
                base.copy(individualEntries = base.individualEntries.copy(enabled = true)),
                base.copy(individualEntries = base.individualEntries.copy(folderTemplate = "entries")),
                base.copy(individualEntries = base.individualEntries.copy(categoryFolders = true)),
                base.copy(dailyNotes = base.dailyNotes.copy(enabled = true)),
                base.copy(dailyNotes = base.dailyNotes.copy(createIfMissing = true)),
                base.copy(dailyNotes = base.dailyNotes.copy(folderTemplate = "notes")),
                base.copy(dictionary = AgentBridgeDictionaryProfileDictionaryV1("dictionary", AgentBridgeDictionaryProfileDictionaryV1Format.JSON, "profile_dictionary_v1")),
                base.copy(packaging = AgentBridgePackagingZip("archive-{date}", false, "healthmd.agent_artifact_manifest/1", 128, 1048576, "zip")),
            )
            val before = ledgerBytes(f)
            for ((index, output) in outputs.withIndex()) f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) {
                f.service.plan(f.peerContext, f.request(discovery, f.intent(output), AgentBridgeExportPlanningFixture.id(900 + index)))
            }
            assertThat(ledgerBytes(f)).isEqualTo(before)
            val supported = f.service.plan(f.peerContext, f.request(discovery, f.intent(base.copy(subfolder = "health", folderTemplate = "{year}/{month}", filenameTemplate = "day-{date}"))))
            assertThat(supported.predictedPaths).containsExactly("health/2026/03/day-2026-03-07.json", "health/2026/03/day-2026-03-08.json").inOrder()
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun pendingFileFenceRejectsExpiryWithoutPublishingOrLeavingAnOrphan() {
        for (decision in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = if (decision) f.service.plan(f.peerContext, request) else null
            val before = ledgerBytes(f)
            var pendingObserved = false
            f.peerContext.onCheck = {
                if (!pendingObserved && inventory(f).any { it.startsWith("pending-") }) {
                    pendingObserved = true
                    f.clock.now = Instant.parse(plan?.expiresAt ?: "2026-05-29T00:10:00Z")
                }
            }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) {
                if (plan == null) f.service.plan(f.peerContext, request) else
                    f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            }
            assertThat(pendingObserved).isTrue() // Actual real temp-file write/fsync occurred BEFORE rejection.
            assertThat(ledgerBytes(f)).isEqualTo(before)
            assertThat(inventory(f)).containsExactly("issuer.lock", "ledger.json")
            assertThat(ledgerState(f).getValue("decisions").jsonArray).isEmpty()
            f.peerContext.onCheck = null
            assertThat(f.restart().discover(f.peerContext, f.discoveryRequest()).authorityReferences).hasSize(1)
        }
    }

    @Test
    fun nativeConsentAndPublicationRecheckConfigurationWithoutRetargetingOrRenewal() {
        for (duringConsent in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            val plan = f.service.plan(f.peerContext, f.request(f.enrolled()))
            val before = ledgerBytes(f)
            var changed = false
            if (duringConsent) f.native.afterDecision = { decision ->
                if (decision is AgentBridgeExportNativeDecision.ExactApproval) { changed = true; f.configuration.sourceZone = "UTC" }
            } else f.peerContext.onCheck = {
                if (!changed && inventory(f).any { it.startsWith("pending-") }) { changed = true; f.configuration.sourceZone = "UTC" }
            }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) {
                f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            }
            assertThat(changed).isTrue()
            assertThat(ledgerBytes(f)).isEqualTo(before)
            assertThat(inventory(f)).containsExactly("issuer.lock", "ledger.json")
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun delayedConfigurationAndExistingKeyCannotReturnCachedAuthorityAtExpiry() {
        for (keyDelay in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = f.service.plan(f.peerContext, request)
            val approval = f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            val before = ledgerBytes(f)
            var delayed = false
            val delay = { delayed = true; f.clock.now = Instant.parse(plan.expiresAt) }
            if (keyDelay) f.keys.onLoad = delay else f.configuration.onRead = delay
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.service.approval(f.peerContext, f.approvalRequest(plan)) }
            assertThat(delayed).isTrue()
            assertThat(ledgerBytes(f)).isEqualTo(before)
            assertThat(approval.binding.expiresAt).isEqualTo(plan.expiresAt)
        }
    }

    @Test
    fun aLiveDelayedDecisionUsesPostconsentTimeButNeverExtendsTheIssuedPlan() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = f.service.plan(f.peerContext, request)
            f.native.afterDecision = { decision ->
                if (decision is AgentBridgeExportNativeDecision.ExactApproval) f.clock.now = f.clock.now.plusSeconds(17)
            }
            val approval = f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            assertThat(approval.approvedAt).isEqualTo("2026-05-29T00:00:17Z")
            assertThat(approval.binding.expiresAt).isEqualTo("2026-05-29T00:10:00Z")
            assertThat(f.service.plan(f.peerContext, request)).isEqualTo(plan)
            assertThat(f.restart().approval(f.peerContext, f.approvalRequest(plan))).isEqualTo(approval)
        }
    }

    @Test
    fun postpublicationFinalDecisionReturnRejectsExpiryAndStaleMetadataCannotRelayPermission() {
        AgentBridgeExportPlanningFixture().use { f ->
            val plan = f.service.plan(f.peerContext, f.request(f.enrolled()))
            var delayed = false
            f.peerContext.onCheck = {
                if (!delayed && ledgerState(f).getValue("decisions").jsonArray.isNotEmpty()) {
                    delayed = true; f.clock.now = Instant.parse(plan.expiresAt)
                }
            }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) {
                f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            }
            assertThat(delayed).isTrue()
            assertThat(ledgerState(f).getValue("decisions").jsonArray).hasSize(1)
            f.peerContext.onCheck = null
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.restart().approval(f.peerContext, f.approvalRequest(plan)) }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) {
                f.restart().authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            }
        }
    }

    @Test
    fun encodedEnvelopeReturnHasItsOwnLiveExpiryFence() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = f.service.plan(f.peerContext, request)
            val negotiation = AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, listOf(2, 4), listOf(2, 4))
            val bytes = AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("plan_request", request), negotiation)
            val start = f.peerContext.checks
            val first = f.service.handleEnvelope(bytes, f.peerContext, negotiation)
            assertThat((AgentBridgeCodec.decodeEnvelope(first, negotiation).payload as AgentBridgeGeneratedPlan)).isEqualTo(plan)
            val checksPerEnvelope = f.peerContext.checks - start
            val finalCheck = f.peerContext.checks + checksPerEnvelope
            var delayed = false
            f.peerContext.onCheck = {
                if (f.peerContext.checks == finalCheck) { delayed = true; f.clock.now = Instant.parse(plan.expiresAt) }
            }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.service.handleEnvelope(bytes, f.peerContext, negotiation) }
            assertThat(delayed).isTrue() // Delay the empirically observed LAST current-trust callback.
        }
    }

    @Test
    fun finalReturnReloadsAParentRevokedOrRevisedAfterTheIssuingTransactionUnlocks() {
        for (revoked in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            var changed = false
            var busy = 0
            f.peerContext.onCheck = {
                if (!changed && ledgerState(f).getValue("plans").jsonArray.isNotEmpty()) {
                    try {
                        if (revoked) f.store.revoke(f.native, f.peer, f.delegation().authorityId, 1) else
                            f.store.putDelegation(f.native, f.delegation().copy(grantRevision = 2), 1)
                        changed = true
                    } catch (e: AgentBridgeException) {
                        // The real issuer lock prevents reentrant CAS in its postpublication fence.
                        check(e.code == AgentBridgeErrorCode.BUSY); busy++
                    }
                }
            }
            f.expect(if (revoked) AgentBridgeErrorCode.APPROVAL_REQUIRED else AgentBridgeErrorCode.REVISION_CONFLICT) {
                f.service.plan(f.peerContext, request)
            }
            assertThat(changed).isTrue()
            assertThat(busy).isAtLeast(1)
            assertThat(ledgerState(f).getValue("plans").jsonArray).hasSize(1)
            assertThat(ledgerState(f).getValue("decisions").jsonArray).isEmpty()
            f.peerContext.onCheck = null
            f.expect(if (revoked) AgentBridgeErrorCode.APPROVAL_REQUIRED else AgentBridgeErrorCode.REVISION_CONFLICT) {
                f.restart().plan(f.peerContext, request)
            }
        }
    }

    @Test
    fun generateActualServiceDiscoveryCandidateOnlyWithBothExplicitScratchGates() {
        val enabled = System.getenv("HEALTHMD_GENERATE_AGENT_BRIDGE_V4")
        val destination = System.getenv("HEALTHMD_AGENT_BRIDGE_CANDIDATES")
        if (enabled == null && destination == null) return
        check(enabled == "1" && !destination.isNullOrBlank()) { "Both native candidate gates are required" }
        val scratch = File(requireNotNull(System.getProperty("healthmd.agentBridgeCandidateScratch"))).canonicalFile
        val output = File(destination).absoluteFile
        check(requireNotNull(output.parentFile).canonicalFile == scratch && output.name in setOf("native-discovery-before.json", "native-discovery-candidates.json"))
        check(!output.exists()) { "Never replace retained native candidates" }
        AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val intent = f.intent()
            val plan = f.service.plan(f.peerContext, f.request(discovery, intent))
            check(plan.effectiveSettings == AgentBridgeExportPlanningFixture.output())
            check(plan.predictedPaths == listOf("2026/2026-03-07.json", "2026/2026-03-08.json"))
            check(f.configuration.preferenceBytes() == f.preferencesBefore)
            val repository = repository()
            val sources = listOf(
                "apps/android/app/src/main/java/com/healthmd/direct/AgentBridgeExportPlanningService.kt",
                "apps/android/app/src/main/java/com/healthmd/direct/AgentBridgeExportAuthorityStore.kt",
                "apps/android/app/src/main/java/com/healthmd/direct/AgentBridgeRequestSettings.kt",
                "apps/android/app/src/test/java/com/healthmd/direct/AgentBridgeExportPlanningTestFixtures.kt",
                "apps/android/app/src/test/java/com/healthmd/direct/AgentBridgeExportPlanningBoundaryTest.kt",
                "apps/android/direct-protocol/src/main/kotlin/com/healthmd/direct/protocol/AgentBridgeModels.kt",
                "apps/android/direct-protocol/src/main/kotlin/com/healthmd/direct/protocol/AgentBridgeCodec.kt",
                "apps/android/direct-protocol/src/main/kotlin/com/healthmd/direct/protocol/AgentBridgeValidation.kt",
                "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json",
            )
            val candidate = buildJsonObject {
                put("producer", "kotlin_actual_service")
                put("source_base", "3bc392c823193ab04aeea4bb71e7cbcb5747b403")
                put("producer_source_sha256", buildJsonObject {
                    sources.forEach { path -> put(path, AgentBridgeCodec.sha256(File(repository, path).readBytes())) }
                })
                put("discovery", Json.parseToJsonElement(AgentBridgeCodec.encode(discovery).decodeToString()))
                put("intent", Json.parseToJsonElement(AgentBridgeCodec.encode(intent).decodeToString()))
                put("plan", Json.parseToJsonElement(AgentBridgeCodec.encode(plan).decodeToString()))
            }
            // Native construction, actual service verdict and SHA-256; no Python oracle/provenance.
            Files.write(output.toPath(), AgentBridgeCodec.canonicalize(candidate.toString().toByteArray()))
        }
    }

    private fun inventory(f: AgentBridgeExportPlanningFixture): Set<String> = Files.newDirectoryStream(
        f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)).use { entries -> entries.map { it.fileName.toString() }.toSet() }

    private fun ledgerBytes(f: AgentBridgeExportPlanningFixture): ByteArray = Files.readAllBytes(
        f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
    private fun ledgerState(f: AgentBridgeExportPlanningFixture) = Json.parseToJsonElement(ledgerBytes(f).decodeToString()).jsonObject.getValue("state").jsonObject

    private fun repository(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            if (File(directory, "packages/contracts/agent-bridge/v1/contract.md").isFile) return directory
            directory = directory.parentFile
        }
        error("Producer source root unavailable")
    }

    companion object {
        // Independent closed DTO/host leaf rule: arrays are one leaf; disabled outputs still count.
        private val PRESET_LEAVES = listOf(
            "/daily_notes/create_if_missing", "/daily_notes/enabled", "/daily_notes/filename_template",
            "/daily_notes/folder_template", "/daily_notes/only", "/daily_notes/section_ids", "/dictionary/type",
            "/filename_template", "/folder_template", "/formats", "/individual_entries/category_folders",
            "/individual_entries/enabled", "/individual_entries/filename_template", "/individual_entries/folder_template",
            "/individual_entries/metric_ids", "/output_profile", "/packaging/type", "/presentation/display_units",
            "/presentation/frontmatter/custom_fields", "/presentation/frontmatter/enabled_field_ids",
            "/presentation/frontmatter/include_capture_diagnostics", "/presentation/frontmatter/include_units",
            "/presentation/group_by_category", "/presentation/include_metadata", "/presentation/locale",
            "/presentation/machine_units", "/presentation/markdown/custom_template", "/presentation/markdown/placeholder_ids",
            "/presentation/markdown/style", "/subfolder", "/write_mode",
        )
    }
}
