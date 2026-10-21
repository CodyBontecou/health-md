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
    private fun executionRequest(f: AgentBridgeExportPlanningFixture, storeDecision: Boolean = true, policy: AgentBridgeSettingsPolicy? = null): AgentBridgeExecuteRequest {
        val plan = f.service.plan(f.peerContext, f.request(f.enrolled(), f.intent(policy = policy ?: f.intent().settingsPolicy)))
        val approval = if (storeDecision) f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId,
            AgentBridgeValidation.bindingFor(plan)) else AgentBridgeApproval(AgentBridgeExportPlanningFixture.id(81),
                f.clock.instant().toString(), plan.authorityReferences.native.authorityId, AgentBridgeValidation.bindingFor(plan),
                listOf(AgentBridgeApprovalRightsItem.EXPORT_EXECUTE), "healthmd.agent_approval", 1)
        return AgentBridgeExecuteRequest(approval, AgentBridgeExportPlanningFixture.id(82), AgentBridgeExportPlanningFixture.id(83),
            plan, AgentBridgeExportPlanningFixture.id(84), "healthmd.agent_execute_request", 1)
    }

    @Test
    fun captureReadKeepsFrozenSavedOutputAfterPlanningExpiryWithoutPreferenceReads() {
        AgentBridgeExportPlanningFixture().use { f ->
            val native = AgentBridgeRequestSettingsResolver.resolve(f.intent(),
                f.configuration.readConfiguration(f.intent().settingsPolicy).settings, f.clock).exporterSettings()
            f.configuration.saved = AgentBridgeRequestSettingsSnapshot(7, native)
            val request = executionRequest(f, policy = AgentBridgeSettingsPolicySavedDeviceSettings(7, "saved_device_settings"))
            f.service.acceptExecution(f.peerContext, request)
            val reservation = f.service.claimCapture(f.peerContext, request)
            val original = kotlinx.serialization.json.Json { encodeDefaults = true }.decodeFromString<AgentBridgeRequestSettingsResolution>(reservation.job.resolutionCanonical)
            f.clock.now = f.clock.now.plusSeconds(600)
            f.configuration.saved = null; f.configuration.readPolicies.clear()
            val frozen = f.service.captureReadConfiguration(f.peerContext, reservation)
            assertThat(frozen.configurationEquals(original)).isTrue()
            assertThat(f.configuration.readPolicies).isNotEmpty()
            assertThat(f.configuration.readPolicies.all { it == null }).isTrue()
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
            assertThat(ledgerState(f).getValue("captureClaims").jsonArray.size).isEqualTo(1)
        }
    }

    @Test
    fun captureReadRejectsUnavailableMetricsAndCurrentNativeAuthorityLoss() {
        for (mode in listOf("metric", "permission", "entitlement", "trust", "grant", "delayed_key")) AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.service.acceptExecution(f.peerContext, request)
            val reservation = f.service.claimCapture(f.peerContext, request)
            when (mode) {
                "metric" -> f.configuration.catalog = AgentBridgeRequestSettingsCatalog(AgentBridgeExportTestRegistry.load(),
                    setOf("avg_hr", "min_hr", "max_hr", "resting_hr", "hrv"), 4)
                "permission" -> f.configuration.grants = AgentBridgeDiscoveryNativeGrants.REQUIRED
                "entitlement" -> f.configuration.entitlement = AgentBridgeDiscoveryEntitlement.REQUIRED
                "trust" -> f.peerContext.trusted = false
                "grant" -> (request.plan as AgentBridgeGeneratedPlan).authorityReferences.native.let { f.store.revoke(f.native, f.peer, it.authorityId, it.grantRevision) }
                else -> f.keys.onLoad = { f.clock.now = f.clock.now.plusSeconds(604800) }
            }
            try { f.service.captureReadConfiguration(f.peerContext, reservation); throw AssertionError("Expected rejection") }
            catch (_: AgentBridgeException) { }
        }
    }

    @Test
    fun captureReadRejectsFabricatedReservationBeforeMetadataAndRechecksReadCallbacks() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.service.acceptExecution(f.peerContext, request)
            val reservation = f.service.claimCapture(f.peerContext, request)
            val fake = reservation.copy(claim = reservation.claim.copy(claimId = AgentBridgeExportPlanningFixture.id(99)))
            val reads = f.configuration.calls
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.captureReadConfiguration(f.peerContext, fake) }
            assertThat(f.configuration.calls).isEqualTo(reads)
            f.configuration.onRead = { f.configuration.grants = AgentBridgeDiscoveryNativeGrants.REQUIRED }
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.captureReadConfiguration(f.peerContext, reservation) }
        }
    }

    @Test
    fun captureReservationRequiresAcceptanceAndCannotBeReclaimedAfterRestart() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.claimCapture(f.peerContext, request) }
            val accepted = f.service.acceptExecution(f.peerContext, request)
            val claim = f.service.claimCapture(f.peerContext, request)
            assertThat(claim.job).isEqualTo(accepted.job)
            assertThat(claim.claim.requestSha256).isEqualTo(accepted.job.requestSha256)
            assertThat(ledgerState(f).getValue("version").jsonPrimitive.int).isEqualTo(4)
            val bytes = ledgerBytes(f)
            f.expect(AgentBridgeErrorCode.BUSY) { f.restart().claimCapture(f.peerContext, request) }
            assertThat(f.restart().acceptExecution(f.peerContext, request).newlyAccepted).isFalse()
            assertThat(ledgerBytes(f)).isEqualTo(bytes)
            val another = request.copy(idempotencyKey = AgentBridgeExportPlanningFixture.id(94), jobId = AgentBridgeExportPlanningFixture.id(95), requestId = AgentBridgeExportPlanningFixture.id(96))
            assertThat(f.service.acceptExecution(f.peerContext, another).newlyAccepted).isTrue()
            assertThat(ledgerState(f).getValue("version").jsonPrimitive.int).isEqualTo(4)
            assertThat(ledgerState(f).getValue("captureClaims").jsonArray.size).isEqualTo(1)
        }
    }

    @Test
    fun captureReservationRejectsExpiredChangedOrRevokedAuthorityWithoutClaiming() {
        for (mode in listOf("expired", "configuration", "trust", "grant")) AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.service.acceptExecution(f.peerContext, request)
            when (mode) {
                "expired" -> f.clock.now = Instant.parse((request.plan as AgentBridgeGeneratedPlan).expiresAt)
                "configuration" -> f.configuration.grants = AgentBridgeDiscoveryNativeGrants.REQUIRED
                "trust" -> f.peerContext.trusted = false
                else -> (request.plan as AgentBridgeGeneratedPlan).authorityReferences.native.let { f.store.revoke(f.native, f.peer, it.authorityId, it.grantRevision) }
            }
            try { f.service.claimCapture(f.peerContext, request); throw AssertionError("Expected rejection") }
            catch (_: AgentBridgeException) { }
            assertThat(ledgerState(f).containsKey("captureClaims")).isFalse()
        }
    }

    @Test
    fun captureReservationSerializesIndependentClaimantsWithoutReturningSecondReservation() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.service.acceptExecution(f.peerContext, request)
            val executor = java.util.concurrent.Executors.newFixedThreadPool(2)
            val start = java.util.concurrent.CountDownLatch(1)
            try {
                val futures = (1..2).map { executor.submit<String> {
                    start.await()
                    try { f.restart().claimCapture(f.peerContext, request); "claimed" }
                    catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.BUSY); "busy" }
                } }
                start.countDown()
                assertThat(futures.map { it.get(10, java.util.concurrent.TimeUnit.SECONDS) }).containsExactly("claimed", "busy")
                assertThat(ledgerState(f).getValue("captureClaims").jsonArray.size).isEqualTo(1)
            } finally { executor.shutdownNow(); assertThat(executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)).isTrue() }
        }
    }

    @Test
    fun captureReservationExpiryAfterSigningPublishesNoClaim() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.service.acceptExecution(f.peerContext, request)
            var encodes = 0
            f.keys.onEncode = { if (++encodes == 2) f.clock.now = Instant.parse((request.plan as AgentBridgeGeneratedPlan).expiresAt) }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.service.claimCapture(f.peerContext, request) }
            f.keys.onEncode = null
            assertThat(encodes).isAtLeast(2)
            assertThat(ledgerState(f).containsKey("captureClaims")).isFalse()
        }
    }

    @Test
    fun durableAcceptanceReplaysAfterPlanExpiryWithoutResolvingChangedSettings() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            val first = f.service.acceptExecution(f.peerContext, request)
            assertThat(first.newlyAccepted).isTrue()
            assertThat(first.job.request()).isEqualTo(request)
            assertThat(first.job.requestSha256).isEqualTo(AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request)))
            val before = ledgerBytes(f)
            assertThat(ledgerState(f).getValue("version").jsonPrimitive.int).isEqualTo(3)
            f.clock.now = f.clock.now.plusSeconds(600)
            f.configuration.active = false
            val reads = f.configuration.calls
            val retry = f.restart().acceptExecution(f.peerContext, request)
            assertThat(retry.newlyAccepted).isFalse()
            assertThat(retry.job).isEqualTo(first.job)
            assertThat(f.configuration.calls).isEqualTo(reads)
            assertThat(ledgerBytes(f)).isEqualTo(before)
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun durableAcceptanceRejectsChangedBytesAndUnstoredApproval() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.service.acceptExecution(f.peerContext, request)
            for (changed in listOf(request.copy(idempotencyKey = AgentBridgeExportPlanningFixture.id(90)),
                request.copy(requestId = AgentBridgeExportPlanningFixture.id(91)))) {
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.acceptExecution(f.peerContext, changed) }
            }
            assertThat(ledgerState(f).getValue("acceptedJobs").jsonArray.size).isEqualTo(1)
            // Same key on a distinct job is a distinct contract index, not global key reuse.
            val distinct = request.copy(jobId = AgentBridgeExportPlanningFixture.id(92), requestId = AgentBridgeExportPlanningFixture.id(93))
            assertThat(f.service.acceptExecution(f.peerContext, distinct).newlyAccepted).isTrue()
            assertThat(ledgerState(f).getValue("acceptedJobs").jsonArray.size).isEqualTo(2)
        }
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f, false)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.acceptExecution(f.peerContext, request) }
            assertThat(ledgerState(f).containsKey("acceptedJobs")).isFalse()
        }
    }

    @Test
    fun durableAcceptanceSerializesIndependentHandlesWithoutDuplicatingJobs() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            val executor = java.util.concurrent.Executors.newFixedThreadPool(2)
            val start = java.util.concurrent.CountDownLatch(1)
            try {
                val futures = (1..2).map { executor.submit<AgentBridgeExportJobAcceptance> {
                    start.await(); f.restart().acceptExecution(f.peerContext, request)
                } }
                start.countDown()
                val results = futures.map { it.get(10, java.util.concurrent.TimeUnit.SECONDS) }
                assertThat(results.count { it.newlyAccepted }).isEqualTo(1)
                assertThat(results[0].job).isEqualTo(results[1].job)
                assertThat(ledgerState(f).getValue("acceptedJobs").jsonArray.size).isEqualTo(1)
            } finally { executor.shutdownNow(); assertThat(executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)).isTrue() }
        }
    }

    @Test
    fun durableAcceptanceRechecksExpiryDuringSigningAndRejectsRevokedRetry() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            var encodes = 0
            f.keys.onEncode = { if (++encodes == 2) f.clock.now = Instant.parse((request.plan as AgentBridgeGeneratedPlan).expiresAt) }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.service.acceptExecution(f.peerContext, request) }
            f.keys.onEncode = null
            assertThat(encodes).isAtLeast(2)
            assertThat(ledgerState(f).containsKey("acceptedJobs")).isFalse()
        }
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.service.acceptExecution(f.peerContext, request)
            f.peerContext.trusted = false
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.acceptExecution(f.peerContext, request) }
        }
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            f.service.acceptExecution(f.peerContext, request)
            val ref = (request.plan as AgentBridgeGeneratedPlan).authorityReferences.native
            f.store.revoke(f.native, f.peer, ref.authorityId, ref.grantRevision)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.acceptExecution(f.peerContext, request) }
        }
    }

    @Test
    fun executionPreparationPinsStoredDecisionAndResolutionAcrossRestartWithoutMutation() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            val before = ledgerBytes(f)
            for (service in listOf(f.service, f.restart())) {
                val prepared = service.prepareExecution(f.peerContext, request)
                assertThat(prepared.requestBytes()).isEqualTo(AgentBridgeCodec.encode(request))
                assertThat(prepared.requestSha256).isEqualTo(AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request)))
                val resolution = prepared.resolution()
                assertThat(resolution.peer).isEqualTo((request.plan as AgentBridgeGeneratedPlan).intent.peer)
                assertThat(resolution.destination).isEqualTo((request.plan as AgentBridgeGeneratedPlan).intent.destination)
                assertThat(resolution.predictedRelativePaths).isEqualTo((request.plan as AgentBridgeGeneratedPlan).predictedPaths)
                assertThat(resolution.selection.map { it.semanticId }).isEqualTo((request.plan as AgentBridgeGeneratedPlan).resolvedMetricIds)
                val bytes = prepared.requestBytes(); bytes.fill(0)
                assertThat(prepared.requestBytes()).isEqualTo(AgentBridgeCodec.encode(request))
            }
            assertThat(ledgerBytes(f)).isEqualTo(before)
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun executionPreparationRejectsUnstoredOrReplacedApproval() {
        for (stored in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f, stored)
            val supplied = if (stored) request.copy(approval = request.approval.copy(approvalId = AgentBridgeExportPlanningFixture.id(85))) else request
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.prepareExecution(f.peerContext, supplied) }
        }
    }

    @Test
    fun executionPreparationRechecksKeyDelayRevocationConfigurationAndMissingKey() {
        for (mode in listOf("expired_key", "revoked_key", "configuration", "missing_key")) AgentBridgeExportPlanningFixture().use { f ->
            val request = executionRequest(f)
            when (mode) {
                "expired_key" -> f.keys.onLoad = { f.clock.now = Instant.parse((request.plan as AgentBridgeGeneratedPlan).expiresAt) }
                "revoked_key" -> f.keys.onLoad = { f.peerContext.trusted = false }
                "configuration" -> f.configuration.active = false
                else -> f.keys.key = null
            }
            try { f.service.prepareExecution(f.peerContext, request); throw AssertionError("Expected rejection") }
            catch (_: AgentBridgeException) { }
        }
    }

    @Test
    fun configurationReaderCannotMutateTheIssuedExplicitIntentThroughListAliases() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val before = AgentBridgeCodec.encode(request)
            var mutated = false
            f.configuration.onPolicyRead = { policy ->
                if (policy is AgentBridgeSettingsPolicyExplicit) {
                    (policy.settings.formats as MutableList).clear()
                    mutated = true
                }
            }
            val plan = f.service.plan(f.peerContext, request)
            assertThat(mutated).isTrue()
            assertThat(AgentBridgeCodec.encode(request)).isEqualTo(before)
            assertThat(plan.intent).isEqualTo(request.intent)
            assertThat(plan.effectiveSettings).isEqualTo(AgentBridgeExportPlanningFixture.output())
            f.configuration.onPolicyRead = null
            assertThat(f.service.reviewNativePlan(f.peerContext, plan.planId)).isEqualTo(plan)
        }
    }

    @Test
    fun discoveryConfigurationIsMetadataOnlyAndExplicitReadsExcludeSavedSources() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            assertThat(f.configuration.readPolicies).isNotEmpty()
            assertThat(f.configuration.readPolicies.all { it == null }).isTrue()
            val explicit = f.intent().settingsPolicy
            val inputs = f.configuration.readConfiguration(explicit).settings
            assertThat(inputs.savedDevice).isNull()
            assertThat(inputs.profiles).isEmpty()
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun everyPlanningReviewApprovalAndEnvelopeBoundaryUsesTheExactIssuedSettingsPolicy() {
        for (kind in listOf("explicit", "saved", "profile")) AgentBridgeExportPlanningFixture().use { f ->
            val native = AgentBridgeRequestSettingsResolver.resolve(f.intent(),
                f.configuration.readConfiguration(f.intent().settingsPolicy).settings, f.clock).exporterSettings()
            val profileId = AgentBridgeExportPlanningFixture.id(61)
            f.configuration.saved = AgentBridgeRequestSettingsSnapshot(7, native)
            f.configuration.profiles = listOf(
                AgentBridgeRequestSettingsProfile(profileId, AgentBridgeRequestSettingsSnapshot(7, native), false),
                AgentBridgeRequestSettingsProfile(AgentBridgeExportPlanningFixture.id(62), AgentBridgeRequestSettingsSnapshot(8, native), true))
            val policy = when (kind) {
                "saved" -> AgentBridgeSettingsPolicySavedDeviceSettings(7, "saved_device_settings")
                "profile" -> AgentBridgeSettingsPolicyProfile(7, profileId, "profile")
                else -> f.intent().settingsPolicy
            }
            val request = f.request(f.enrolled(), f.intent(policy = policy))
            fun checkReads(operation: () -> Unit) {
                f.configuration.readPolicies.clear()
                operation()
                assertThat(f.configuration.readPolicies.size).isAtLeast(3)
                assertThat(f.configuration.readPolicies.all { it == policy }).isTrue()
            }
            lateinit var plan: AgentBridgeGeneratedPlan
            checkReads { plan = f.service.plan(f.peerContext, request) }
            checkReads { assertThat(f.service.plan(f.peerContext, request)).isEqualTo(plan) }
            checkReads { assertThat(f.service.reviewNativePlan(f.peerContext, plan.planId)).isEqualTo(plan) }
            checkReads { f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan)) }
            checkReads { f.service.approval(f.peerContext, f.approvalRequest(plan)) }
            val negotiation = AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, listOf(2, 4), listOf(2, 4))
            for (message in listOf(AgentBridgeMessage("plan_request", request),
                AgentBridgeMessage("approval_request", f.approvalRequest(plan)))) {
                checkReads { f.service.handleEnvelope(AgentBridgeCodec.encodeEnvelope(message, negotiation), f.peerContext, negotiation) }
            }
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun nativePlanReviewUsesStoredPlanWithoutCreatingConsentOrChangingPreferences() {
        AgentBridgeExportPlanningFixture().use { f ->
            val plan = f.service.plan(f.peerContext, f.request(f.enrolled()))
            val before = ledgerBytes(f)
            val decisions = f.native.decisions.size
            val reviewed = f.service.reviewNativePlan(f.peerContext, plan.planId)
            assertThat(reviewed).isEqualTo(plan)
            assertThat(AgentBridgeValidation.bindingFor(reviewed)).isEqualTo(AgentBridgeValidation.bindingFor(plan))
            assertThat(f.restart().reviewNativePlan(f.peerContext, plan.planId)).isEqualTo(plan)
            assertThat(ledgerBytes(f)).isEqualTo(before)
            assertThat(f.native.decisions.size).isEqualTo(decisions)
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
            assertThat(ledgerState(f).getValue("decisions").jsonArray).isEmpty()
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.approval(f.peerContext, f.approvalRequest(reviewed)) }
        }
    }

    @Test
    fun nativePlanReviewRequiresExecutionDelegationAndNativeReadiness() {
        for (mode in listOf("plan_only", "permission", "entitlement")) AgentBridgeExportPlanningFixture().use { f ->
            if (mode == "permission") f.configuration.grants = AgentBridgeDiscoveryNativeGrants.REQUIRED
            if (mode == "entitlement") f.configuration.entitlement = AgentBridgeDiscoveryEntitlement.REQUIRED
            f.store.initialize(f.native)
            val grant = f.delegation()
            f.store.putDelegation(f.native, if (mode == "plan_only") grant.copy(
                rights = grant.rights.filter { it != AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE }) else grant, 0)
            val plan = f.service.plan(f.peerContext, f.request(f.service.discover(f.peerContext, f.discoveryRequest())))
            val before = ledgerBytes(f)
            val expected = when (mode) {
                "plan_only" -> AgentBridgeErrorCode.APPROVAL_REQUIRED
                "entitlement" -> AgentBridgeErrorCode.ENTITLEMENT_REQUIRED
                else -> AgentBridgeErrorCode.PERMISSION_REQUIRED
            }
            f.expect(expected) { f.service.reviewNativePlan(f.peerContext, plan.planId) }
            assertThat(ledgerBytes(f)).isEqualTo(before)
        }
    }

    @Test
    fun nativePlanReviewRechecksTrustConfigurationAndExpiryAtPublicationAndReturn() {
        for (stage in listOf(2, 3)) for (mode in listOf("permission", "configuration", "expiry"))
            AgentBridgeExportPlanningFixture().use { f ->
                val plan = f.service.plan(f.peerContext, f.request(f.enrolled()))
                val before = ledgerBytes(f)
                var reads = 0
                f.configuration.onRead = {
                    reads++
                    if (reads == stage && mode != "configuration") {
                        if (mode == "permission") f.peerContext.trusted = false
                        else f.clock.now = Instant.parse(plan.expiresAt)
                    }
                }
                var changed = false
                f.peerContext.onCheck = {
                    if (mode == "configuration" && !changed && reads == stage - 1) {
                        changed = true
                        f.configuration.catalog = AgentBridgeRequestSettingsCatalog(AgentBridgeExportTestRegistry.load(),
                            setOf("avg_hr", "min_hr", "max_hr", "resting_hr", "hrv"), 4)
                    }
                }
                // Change configuration before the publication/return read; the next boundary
                // must inspect current inputs rather than reuse the earlier copied snapshot.
                val expected = when (mode) {
                    "permission" -> AgentBridgeErrorCode.PERMISSION_REQUIRED
                    "configuration" -> AgentBridgeErrorCode.BINDING_CHANGED
                    else -> AgentBridgeErrorCode.PLAN_EXPIRED
                }
                f.expect(expected) { f.service.reviewNativePlan(f.peerContext, plan.planId) }
                assertThat(reads).isAtLeast(stage)
                assertThat(ledgerBytes(f)).isEqualTo(before)
                f.configuration.onRead = null
            }
    }

    @Test
    fun nativePlanReviewRejectsForeignPeerAndUnknownPlanWithoutWrites() {
        AgentBridgeExportPlanningFixture().use { f ->
            val plan = f.service.plan(f.peerContext, f.request(f.enrolled()))
            val before = ledgerBytes(f)
            val foreign = AgentBridgeExportTestPeer(f.peer.copy(hostInstallationId = AgentBridgeExportPlanningFixture.id(99)))
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.reviewNativePlan(foreign, plan.planId) }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.reviewNativePlan(f.peerContext, AgentBridgeExportPlanningFixture.id(99)) }
            assertThat(ledgerBytes(f)).isEqualTo(before)
        }
    }

    @Test
    fun nativePlanReviewDoesNotRetainAuthorityAfterRevocationOrExpiry() {
        for (revoke in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val plan = f.service.plan(f.peerContext, f.request(discovery))
            val reviewed = f.service.reviewNativePlan(f.peerContext, plan.planId)
            if (revoke) f.store.revoke(f.native, f.peer, discovery.authorityReferences.single().authorityId, 1)
            else f.clock.now = Instant.parse(plan.expiresAt)
            val before = ledgerBytes(f)
            f.expect(if (revoke) AgentBridgeErrorCode.APPROVAL_REQUIRED else AgentBridgeErrorCode.PLAN_EXPIRED) {
                f.service.reviewNativePlan(f.peerContext, reviewed.planId)
            }
            f.expect(if (revoke) AgentBridgeErrorCode.APPROVAL_REQUIRED else AgentBridgeErrorCode.PLAN_EXPIRED) {
                f.service.authorizeExactApproval(f.peerContext, f.native, reviewed.planId, AgentBridgeValidation.bindingFor(reviewed))
            }
            assertThat(ledgerBytes(f)).isEqualTo(before)
        }
    }

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
