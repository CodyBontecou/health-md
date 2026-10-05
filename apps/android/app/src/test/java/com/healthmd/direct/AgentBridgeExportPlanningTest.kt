package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.*
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Test

class AgentBridgeExportPlanningTest {
    @Test
    fun nativeStoredConsentIsRequiredBeforeActualResolverCanIssueYearJsonPlan() {
        AgentBridgeExportPlanningFixture().use { f ->
            val empty = f.service.discover(f.peerContext, f.discoveryRequest())
            assertThat(empty.authorityReferences).isEmpty()
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.plan(f.peerContext, f.request(empty)) }
            assertThat(Files.exists(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
            assertThat(f.native.decisions).isEmpty()

            f.store.initialize(f.native)
            val ref = f.store.putDelegation(f.native, f.delegation(), expectedGrantRevision = 0)
            val discovery = f.service.discover(f.peerContext, f.discoveryRequest())
            assertThat(discovery.authorityReferences).containsExactly(ref)
            val request = f.request(discovery)
            val plan = f.service.plan(f.peerContext, request)
            assertThat(plan.predictedPaths).containsExactly("2026/2026-03-07.json", "2026/2026-03-08.json").inOrder()
            assertThat(plan.resolvedMetricIds).containsExactly("heart_rate_avg", "steps").inOrder()
            assertThat(plan.resolvedDates).isEqualTo(AgentBridgeDatesExact(AgentBridgeRange("2026-03-08", "2026-03-07"), "exact"))
            assertThat(plan.authorityReferences.native).isEqualTo(ref)
            assertThat(plan.authorityReferences.host).isEqualTo(f.hostReference)
            assertThat(plan.origins).contains(AgentBridgeOrigin(AgentBridgeOriginOrigin.REQUEST, "/capture_scope/selection/metric_ids", 0))
            assertThat(plan.origins).contains(AgentBridgeOrigin(AgentBridgeOriginOrigin.REQUEST, "/effective_settings/daily_notes/enabled", 0))
            assertThat(plan.sideEffects).isEqualTo(AgentBridgeZeroControlEffects(0, 0, 0, 0, 0, 0, 0, 0))
            assertThat(AgentBridgeCodec.decode(AgentBridgeCodec.encode(plan))).isEqualTo(plan)
            assertThat(f.service.plan(f.peerContext, request)).isEqualTo(plan)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.approval(f.peerContext, f.approvalRequest(plan)) }
            val approval = f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            assertThat(f.service.approval(f.peerContext, f.approvalRequest(plan))).isEqualTo(approval)
            assertThat(approval.binding).isEqualTo(AgentBridgeValidation.bindingFor(plan))
            assertThat(f.configuration.calls).isAtLeast(3)
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun discoveryIsPeerFilteredAndDoesNotFabricateQueriesProjectionExecutionOrControls() {
        AgentBridgeExportPlanningFixture().use { f ->
            val initial = f.enrolled()
            assertThat(initial.queryCatalogSha256).isEqualTo("0".repeat(64))
            assertThat(initial.projectionCatalogSha256).isEqualTo("0".repeat(64))
            assertThat(initial.queryOperations).isEmpty()
            assertThat(initial.projectionProducts).isEmpty()
            assertThat(initial.projectionSourceCatalog).isNull()
            assertThat(initial.controlOperations).isEmpty()
            assertThat(initial.features).containsExactly(AgentBridgeDiscoveryFeaturesItem.EXPLICIT_SETTINGS, AgentBridgeDiscoveryFeaturesItem.ZERO_HEALTH_PLAN)
            assertThat(initial.lifecycle).isEqualTo(AgentBridgeDiscoveryLifecycle.ANDROID_USER_STARTED_SERVICE_AFTER_FIRST_UNLOCK)
            f.peerContext.current = f.peer.copy(hostInstallationId = AgentBridgeExportPlanningFixture.id(40))
            val filtered = f.service.discover(f.peerContext, f.discoveryRequest().copy(peer = f.peerContext.current))
            assertThat(filtered.authorityReferences).isEmpty()
            assertThat(filtered.capabilitySha256).isNotEqualTo(initial.capabilitySha256)
            f.configuration.active = false
            f.configuration.unlocked = false
            val inactive = f.service.discover(f.peerContext, f.discoveryRequest().copy(peer = f.peerContext.current))
            assertThat(inactive.requiredActions).containsExactly(AgentBridgeDiscoveryRequiredActionsItem.OPEN_MOBILE_APP, AgentBridgeDiscoveryRequiredActionsItem.UNLOCK_MOBILE)
            assertThat(f.configuration.active).isFalse()
            assertThat(f.configuration.unlocked).isFalse()
            assertThat(f.native.decisions).hasSize(2)
        }
    }

    @Test
    fun authenticatedContextIsMandatoryBeforeConfigurationAndWrongGrantOrIssuerCannotPlan() {
        AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val request = f.request(discovery)
            val calls = f.configuration.calls
            f.peerContext.trusted = false
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.plan(f.peerContext, request) }
            assertThat(f.configuration.calls).isEqualTo(calls)
            f.peerContext.trusted = true
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.plan(f.peerContext, request.copy(intent = f.intent().copy(peer = f.peer.copy(hostInstallationId = AgentBridgeExportPlanningFixture.id(41)), destination = f.intent().destination.copy(hostInstallationId = AgentBridgeExportPlanningFixture.id(41))))) }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.plan(f.peerContext, request.copy(authorityId = AgentBridgeExportPlanningFixture.id(42))) }
            f.expect(AgentBridgeErrorCode.REVISION_CONFLICT) { f.service.plan(f.peerContext, request.copy(authorityRevision = 2)) }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.plan(f.peerContext, request.copy(hostAuthorityReference = f.hostReference.copy(issuer = AgentBridgeIssuer.NATIVE_SOURCE))) }
            assertThat(f.native.decisions).hasSize(2)
        }
    }

    @Test
    fun exactApprovalCannotBeForgedOrRetargetedByRehashingBindingFields() {
        AgentBridgeExportPlanningFixture().use { f ->
            val plan = f.service.plan(f.peerContext, f.request(f.enrolled()))
            val request = f.approvalRequest(plan)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.approval(f.peerContext, request.copy(planId = AgentBridgeExportPlanningFixture.id(43))) }
            val binding = request.binding
            val changes = listOf(
                binding.copy(scopeSha256 = "c".repeat(64)), binding.copy(settingsSha256 = "c".repeat(64)),
                binding.copy(planSha256 = "c".repeat(64)), binding.copy(capabilitySha256 = "c".repeat(64)),
                binding.copy(destination = binding.destination.copy(identitySha256 = "c".repeat(64))),
                binding.copy(destination = binding.destination.copy(revision = 2)),
                binding.copy(authorityReferences = binding.authorityReferences.copy(native = binding.authorityReferences.native.copy(grantSha256 = "c".repeat(64)))),
                binding.copy(authorityReferences = binding.authorityReferences.copy(host = binding.authorityReferences.host.copy(grantSha256 = "c".repeat(64)))),
                binding.copy(authorityReferences = binding.authorityReferences.copy(native = binding.authorityReferences.native.copy(grantRevision = 2))),
                binding.copy(expiresAt = "2026-05-29T00:09:59Z"),
            )
            for (changed in changes) f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.approval(f.peerContext, request.copy(binding = changed)) }
            f.native.allowed = false
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, binding) }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.approval(f.peerContext, request) }
            f.native.allowed = true
            f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, binding)
            for (changed in changes) f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.approval(f.peerContext, request.copy(binding = changed)) }
        }
    }

    @Test
    fun approvedInBoundsNewScopeAndOpaqueHostBindingRequireFreshPlansAndDecisions() {
        AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val originalRequest = f.request(discovery)
            val original = f.service.plan(f.peerContext, originalRequest)
            val approval = f.service.authorizeExactApproval(f.peerContext, f.native, original.planId, AgentBridgeValidation.bindingFor(original))
            val changedIntent = f.intent(metrics = listOf("steps")).let { it.copy(destination = it.destination.copy(bindingId = AgentBridgeExportPlanningFixture.id(44), identitySha256 = "c".repeat(64))) }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.plan(f.peerContext, originalRequest.copy(intent = changedIntent)) }
            val next = f.service.plan(f.peerContext, f.request(discovery, changedIntent, AgentBridgeExportPlanningFixture.id(45)))
            assertThat(next.planId).isNotEqualTo(original.planId)
            assertThat(next.scopeSha256).isNotEqualTo(original.scopeSha256)
            // This source binds but does NOT assert host-side root/grant verification.
            assertThat(next.intent.destination).isEqualTo(changedIntent.destination)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.approval(f.peerContext, f.approvalRequest(next).copy(binding = approval.binding)) }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.approval(f.peerContext, f.approvalRequest(next)) }
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun nativeParentExpiryAndRevocationClampAndInvalidatePlansWithoutRenewal() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            f.store.putDelegation(f.native, f.delegation("2026-05-29T00:03:00Z"), 0)
            val request = f.request(f.service.discover(f.peerContext, f.discoveryRequest()))
            val plan = f.service.plan(f.peerContext, request)
            assertThat(plan.expiresAt).isEqualTo("2026-05-29T00:03:00Z")
            f.clock.now = Instant.parse("2026-05-29T00:03:00Z")
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.restart().plan(f.peerContext, request) }
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { f.restart().approval(f.peerContext, f.approvalRequest(plan)) }
        }
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = f.service.plan(f.peerContext, request)
            f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            f.store.revoke(f.native, f.peer, f.delegation().authorityId, 1)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.restart().approval(f.peerContext, f.approvalRequest(plan)) }
            assertThat(f.restart().discover(f.peerContext, f.discoveryRequest()).authorityReferences).isEmpty()
        }
    }

    @Test
    fun liveTrustRevocationDuringConfigurationAndNativeDecisionPreventsCommit() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(path)
            f.configuration.onRead = { f.peerContext.trusted = false }
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.plan(f.peerContext, request) }
            assertThat(Files.readAllBytes(path)).isEqualTo(before)
            f.peerContext.trusted = true
            f.configuration.onRead = null
            val plan = f.service.plan(f.peerContext, request)
            val beforeDecision = Files.readAllBytes(path)
            f.native.afterDecision = { if (it is AgentBridgeExportNativeDecision.ExactApproval) f.peerContext.trusted = false }
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan)) }
            assertThat(Files.readAllBytes(path)).isEqualTo(beforeDecision)
            f.peerContext.trusted = true
            f.native.afterDecision = null
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.approval(f.peerContext, f.approvalRequest(plan)) }
        }
    }

    @Test
    fun responseBoundaryRechecksTrustEvenIfPrivateIssuanceCommittedBeforeRevocation() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val revokeAt = f.peerContext.checks + 4 // Entry, after callback, precommit, postcommit response fence.
            f.peerContext.onCheck = { if (f.peerContext.checks == revokeAt) f.peerContext.trusted = false }
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.plan(f.peerContext, request) }
            // A committed private plan is not an approval/export; no response or rollback fallback occurs.
            f.peerContext.onCheck = null
            f.peerContext.trusted = true // Explicit fake native trust restoration, NOT a remote operation.
            val stored = f.restart().plan(f.peerContext, request)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.approval(f.peerContext, f.approvalRequest(stored)) }
            assertThat(f.native.decisions).hasSize(2)
        }
    }

    @Test
    fun advancingNativeGrantRevisionAndParentScopeRestrictionsRequireNewConsentAndPlanning() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = f.service.plan(f.peerContext, request)
            f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            val narrowed = f.delegation().let { it.copy(grantRevision = 2, bounds = it.bounds.copy(metricIds = listOf("steps"))) }
            f.store.putDelegation(f.native, narrowed, 1)
            f.expect(AgentBridgeErrorCode.REVISION_CONFLICT) { f.restart().approval(f.peerContext, f.approvalRequest(plan)) }
            val current = f.service.discover(f.peerContext, f.discoveryRequest())
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.plan(f.peerContext, f.request(current, requestId = AgentBridgeExportPlanningFixture.id(70)).copy(authorityRevision = 2)) }
            val next = f.service.plan(f.peerContext, f.request(current, f.intent(metrics = listOf("steps")), AgentBridgeExportPlanningFixture.id(71)).copy(authorityRevision = 2))
            assertThat(next.authorityReferences.native.grantRevision).isEqualTo(2)
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { f.service.approval(f.peerContext, f.approvalRequest(next)) }
        }
    }

    @Test
    fun plansAndPreviouslyStoredExactDecisionsSurviveDurableRestartAndClockDoesNotSlideExpiry() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = f.service.plan(f.peerContext, request)
            val approval = f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            f.clock.now = f.clock.now.plusSeconds(90)
            val restarted = f.restart()
            assertThat(restarted.plan(f.peerContext, request)).isEqualTo(plan)
            assertThat(restarted.approval(f.peerContext, f.approvalRequest(plan))).isEqualTo(approval)
            assertThat(plan.expiresAt).isEqualTo("2026-05-29T00:10:00Z")
        }
    }

    @Test
    fun allAvailableStaysLogicalWhileCivilAnchorsDSTAndDistinctRmssdUseTheActualResolver() {
        AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val logical = f.service.plan(f.peerContext, f.request(discovery, f.intent(dates = AgentBridgeDatesAllAvailable("all_available"))))
            assertThat(logical.predictedPaths).isEmpty()
            assertThat(logical.resolvedDates).isEqualTo(AgentBridgeDatesAllAvailable("all_available"))
            assertThat(logical.pathPrediction).isEqualTo(AgentBridgeGeneratedPlanPathPrediction.TEMPLATE_ONLY_ALL_AVAILABLE)
            assertThat(logical.limitations).containsExactly("history_bounds_unresolved")
            val relative = f.service.plan(f.peerContext, f.request(discovery,
                f.intent(metrics = listOf("android.hrv_rmssd", "heart_rate_avg", "heart_rate_max", "heart_rate_min", "resting_heart_rate", "steps"),
                    dates = AgentBridgeDatesPastCompleteDays("2026-03-09", 2, "past_complete_days")), AgentBridgeExportPlanningFixture.id(46)))
            assertThat(relative.predictedPaths).containsExactly("2026/2026-03-07.json", "2026/2026-03-08.json").inOrder()
            assertThat(relative.resolvedMetricIds).contains("android.hrv_rmssd")
            assertThat(relative.resolvedMetricIds).doesNotContain("hrv")
            assertThat(relative.origins).hasSize(40)
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun savedAndProfileOutputRevisionsArePinnedWithoutFallbackOrInheritedApiScheduleAuthority() {
        AgentBridgeExportPlanningFixture().use { f ->
            val native = AgentBridgeRequestSettingsResolver.resolve(f.intent(), f.configuration.readConfiguration().settings, f.clock).exporterSettings()
                .copy(apiEndpointUrl = "https://synthetic.invalid/never-contact", scheduleEnabled = true)
            val profileId = AgentBridgeExportPlanningFixture.id(47)
            f.configuration.saved = AgentBridgeRequestSettingsSnapshot(7, native)
            f.configuration.profiles = listOf(AgentBridgeRequestSettingsProfile(profileId, AgentBridgeRequestSettingsSnapshot(7, native), false))
            val discovery = f.enrolled()
            val policies = listOf(AgentBridgeSettingsPolicySavedDeviceSettings(7, "saved_device_settings"), AgentBridgeSettingsPolicyProfile(7, profileId, "profile"))
            for ((index, policy) in policies.withIndex()) {
                val plan = f.service.plan(f.peerContext, f.request(discovery, f.intent(policy = policy), AgentBridgeExportPlanningFixture.id(48 + index)))
                assertThat(plan.effectiveSettings).isEqualTo(AgentBridgeExportPlanningFixture.output())
                assertThat(plan.revisions.single().revision).isEqualTo(7)
                assertThat(plan.origins.filter { it.pointer.startsWith("/effective_settings/") }.all { it.revision == 7 }).isTrue()
            }
            f.expect(AgentBridgeErrorCode.REVISION_CONFLICT) { f.service.plan(f.peerContext, f.request(discovery,
                f.intent(policy = AgentBridgeSettingsPolicySavedDeviceSettings(8, "saved_device_settings")), AgentBridgeExportPlanningFixture.id(50))) }
            f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { f.service.plan(f.peerContext, f.request(discovery,
                f.intent(policy = AgentBridgeSettingsPolicyProfile(7, AgentBridgeExportPlanningFixture.id(51), "profile")), AgentBridgeExportPlanningFixture.id(52))) }
            assertThat(f.configuration.saved?.settings).isEqualTo(native)
        }
    }

    @Test
    fun capabilityAndSameRevisionNativeSettingsMutationRejectStoredPlans() {
        AgentBridgeExportPlanningFixture().use { f ->
            val native = AgentBridgeRequestSettingsResolver.resolve(f.intent(), f.configuration.readConfiguration().settings, f.clock).exporterSettings()
            f.configuration.saved = AgentBridgeRequestSettingsSnapshot(7, native)
            val request = f.request(f.enrolled(), f.intent(policy = AgentBridgeSettingsPolicySavedDeviceSettings(7, "saved_device_settings")))
            val plan = f.service.plan(f.peerContext, request)
            f.configuration.saved = AgentBridgeRequestSettingsSnapshot(7, native.copy(folderStructure = "changed/{year}"))
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.approval(f.peerContext, f.approvalRequest(plan)) }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.plan(f.peerContext, request) }
        }
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val plan = f.service.plan(f.peerContext, request)
            f.configuration.catalog = AgentBridgeRequestSettingsCatalog(AgentBridgeExportTestRegistry.load(), setOf("steps", "avg_hr"), 3)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.service.approval(f.peerContext, f.approvalRequest(plan)) }
        }
    }

    @Test
    fun unsupportedOutputsIdsUnsafePathsAndNativeReadinessRejectWithoutEnrollmentOrPreferenceWrites() {
        AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val unsupported = AgentBridgeExportPlanningFixture.output().copy(formats = listOf(AgentBridgeFormat.MARKDOWN))
            f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { f.service.plan(f.peerContext, f.request(discovery, f.intent(unsupported))) }
            f.expect(AgentBridgeErrorCode.UNSUPPORTED_METRIC) { f.service.plan(f.peerContext, f.request(discovery, f.intent(metrics = listOf("hrv")))) }
            f.expect(AgentBridgeErrorCode.UNSAFE_PATH) { f.service.plan(f.peerContext, f.request(discovery, f.intent(AgentBridgeExportPlanningFixture.output().copy(folderTemplate = "../escape")))) }
            f.configuration.active = false
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.plan(f.peerContext, f.request(discovery)) }
            f.configuration.active = true
            f.configuration.unlocked = false
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.plan(f.peerContext, f.request(discovery)) }
            f.configuration.unlocked = true
            f.configuration.grants = AgentBridgeDiscoveryNativeGrants.UNVERIFIED
            val plan = f.service.plan(f.peerContext, f.request(f.service.discover(f.peerContext, f.discoveryRequest())))
            assertThat(plan.requiredActions).containsExactly("grant_health_access")
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan)) }
            assertThat(f.native.decisions).hasSize(2)
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun contendedNativeConfigurationTransactionHasBoundedBusyAdmission() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            f.configuration.onRead = { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }
            val pool = Executors.newSingleThreadExecutor()
            try {
                val active = pool.submit<AgentBridgeDiscovery> { f.service.discover(f.peerContext, f.discoveryRequest()) }
                assertThat(entered.await(5, TimeUnit.SECONDS)).isTrue()
                f.expect(AgentBridgeErrorCode.BUSY) { f.restart().discover(f.peerContext, f.discoveryRequest()) }
                release.countDown()
                assertThat(active.get(5, TimeUnit.SECONDS).authorityReferences).hasSize(1)
            } finally { release.countDown(); pool.shutdownNow() }
        }
    }

    @Test
    fun concurrentExactIssuanceAcrossServicesReturnsOneDurablePlanAndChangedBytesReject() {
        AgentBridgeExportPlanningFixture().use { f ->
            val request = f.request(f.enrolled())
            val pool = Executors.newFixedThreadPool(4)
            try {
                val plans = (1..8).map { pool.submit<AgentBridgeGeneratedPlan> { f.restart().plan(f.peerContext, request) } }.map { it.get(30, TimeUnit.SECONDS) }
                assertThat(plans.distinct()).hasSize(1)
                assertThat(f.restart().plan(f.peerContext, request)).isEqualTo(plans.first())
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.restart().plan(f.peerContext, request.copy(intent = f.intent(metrics = listOf("steps")))) }
            } finally { pool.shutdownNow() }
        }
    }

    @Test
    fun fullIssuedPlanLedgerDoesNotEvictReplayIdentityOrApprovals() {
        AgentBridgeExportPlanningFixture().use { f ->
            val discovery = f.enrolled()
            val originalRequest = f.request(discovery)
            val original = f.service.plan(f.peerContext, originalRequest)
            val approval = f.service.authorizeExactApproval(f.peerContext, f.native, original.planId, AgentBridgeValidation.bindingFor(original))
            for (n in 1 until AgentBridgeExportAuthorityStore.MAX_PLANS) {
                f.service.plan(f.peerContext, f.request(discovery, requestId = AgentBridgeExportPlanningFixture.id(300 + n)))
            }
            f.expect(AgentBridgeErrorCode.BUSY) { f.service.plan(f.peerContext, f.request(discovery, requestId = AgentBridgeExportPlanningFixture.id(400))) }
            assertThat(f.restart().plan(f.peerContext, originalRequest)).isEqualTo(original)
            assertThat(f.restart().approval(f.peerContext, f.approvalRequest(original))).isEqualTo(approval)
        }
    }

    @Test
    fun strictEnvelopeRouteRejectsExecuteAndMalformedBytesWithoutRemoteIssuerAccess() {
        AgentBridgeExportPlanningFixture().use { f ->
            val negotiation = AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, listOf(2, 4), listOf(2, 4))
            val discoveryBytes = AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("discovery_request", f.discoveryRequest()), negotiation)
            val apple = AgentBridgeNegotiation.negotiate(AgentBridgePlatform.APPLE, listOf(1, 3, 4), listOf(1, 3, 4))
            f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { f.service.handleEnvelope(discoveryBytes, f.peerContext, apple) }
            val old = AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, listOf(2, 4), listOf(2))
            f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { f.service.handleEnvelope(discoveryBytes, f.peerContext, old) }
            val discovery = AgentBridgeCodec.decodeEnvelope(f.service.handleEnvelope(discoveryBytes, f.peerContext, negotiation), negotiation).payload as AgentBridgeDiscovery
            assertThat(discovery.authorityReferences).isEmpty()
            val duplicate = discoveryBytes.decodeToString().replaceFirst("{", "{\"\\u0074ype\":\"discovery_request\",").toByteArray()
            f.expect(AgentBridgeErrorCode.INVALID_REQUEST) { f.service.handleEnvelope(duplicate, f.peerContext, negotiation) }
            f.expect(AgentBridgeErrorCode.INVALID_REQUEST) { f.service.handleEnvelope(byteArrayOf(0xc3.toByte(), 0x28), f.peerContext, negotiation) }
            f.expect(AgentBridgeErrorCode.INVALID_REQUEST) { f.service.handleEnvelope(ByteArray(2097153), f.peerContext, negotiation) }
            val actualDiscovery = f.enrolled()
            val requestBytes = AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("plan_request", f.request(actualDiscovery)), negotiation)
            val plan = AgentBridgeCodec.decodeEnvelope(f.service.handleEnvelope(requestBytes, f.peerContext, negotiation), negotiation).payload as AgentBridgeGeneratedPlan
            val approval = f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            val execute = AgentBridgeExecuteRequest(approval, AgentBridgeExportPlanningFixture.id(600), AgentBridgeExportPlanningFixture.id(601), plan,
                AgentBridgeExportPlanningFixture.id(602), "healthmd.agent_execute_request", 1)
            val before = f.native.decisions.size
            val rejected = AgentBridgeCodec.decodeEnvelope(f.service.handleEnvelope(AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("execute_request", execute), negotiation), f.peerContext, negotiation), negotiation)
            assertThat(rejected.type).isEqualTo("rejected")
            assertThat((rejected.payload as AgentBridgeError).code).isEqualTo(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
            assertThat(f.native.decisions).hasSize(before)
            val cancel = AgentBridgeCancelRequest(approval.approvalId, approval.authorityId, execute.jobId, f.peer,
                AgentBridgeCodec.fingerprint(execute), "healthmd.agent_cancel_request", 1)
            val resume = AgentBridgeResumeRequest(approval.binding, 0, plan.intent.destination, "d".repeat(64), execute.jobId,
                "d".repeat(64), f.peer, AgentBridgeCodec.fingerprint(execute), "healthmd.agent_resume_request", 1)
            for (message in listOf(AgentBridgeMessage("cancel_request", cancel), AgentBridgeMessage("resume_request", resume))) {
                f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { f.service.handleEnvelope(AgentBridgeCodec.encodeEnvelope(message, negotiation), f.peerContext, negotiation) }
            }
            val query = AgentBridgeQueryRequest(f.delegation().authorityId, 1, actualDiscovery.budgets, plan.intent.calendarTimezone,
                "d".repeat(64), plan.intent.dates, AgentBridgeQueryRequestDetail.SUMMARY, false, AgentBridgeQueryOperationMetricCatalog("metric_catalog"),
                AgentBridgeQueryPage(maxBytes = 1048576, maxItems = 1000), f.peer, "health_connect", AgentBridgeExportPlanningFixture.id(603),
                "healthmd.source_query_request", 1, plan.intent.captureScope.selection, AgentBridgeQueryCatalogSourceId.HEALTH_CONNECT)
            val queryRejected = AgentBridgeCodec.decodeEnvelope(f.service.handleEnvelope(AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("query_request", query), negotiation), f.peerContext, negotiation), negotiation)
            assertThat((queryRejected.payload as AgentBridgeError).code).isEqualTo(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
            val unsupportedControl = requestBytes.decodeToString().replace("\"type\":\"plan_request\"", "\"type\":\"control_plan_request\"").toByteArray()
            f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { f.service.handleEnvelope(unsupportedControl, f.peerContext, negotiation) }
            assertThat(f.native.decisions).hasSize(before)
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
        }
    }

    @Test
    fun corruptDecodedDuplicatePrivateKeysNeverResetOrRegenerateAuthority() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val original = path.toFile().readText()
            // Escaped and unescaped keys decode identically. MAC validation must not hide parser ambiguity.
            Files.write(path, original.replaceFirst("{", "{\"\\u0073tate\":{},").toByteArray())
            val corrupt = Files.readAllBytes(path)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.restart().discover(f.peerContext, f.discoveryRequest()) }
            assertThat(Files.readAllBytes(path)).isEqualTo(corrupt)
            assertThat(f.native.decisions).hasSize(2)
            f.expect(AgentBridgeErrorCode.REVISION_CONFLICT) { f.store.initialize(f.native) }
        }
    }
}
