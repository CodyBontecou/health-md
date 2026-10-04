package com.healthmd.accountauth

import org.junit.Test
import kotlinx.serialization.json.*
import java.lang.reflect.InvocationTargetException
import kotlin.system.exitProcess

/** Manual JUnit annotation runner, avoiding any unadmitted runner/transitive dependency. */
fun main(args: Array<String>) {
    checkSource(args.size == 1, "harness repository root")
    System.setProperty("healthmd.accountauth.root", args[0])
    val suites = listOf(AccountAuthWireTest(), AccountAuthCallbackTest(), AccountAuthTransportTest(), AccountAuthLifecycleTest())
    var passed = 0
    val actualPassed = mutableSetOf<String>()
    for (suite in suites) {
        val methods = suite.javaClass.declaredMethods.filter { it.isAnnotationPresent(Test::class.java) }.sortedBy { it.name }
        for (method in methods) {
            val label = "${suite.javaClass.simpleName}.${method.name}"
            try { method.invoke(suite); passed++; actualPassed.add(method.name); println("PASS $label") }
            catch (error: InvocationTargetException) {
                // No input, response, secret value, assertion diff, or port exception reflection.
                println("FAIL $label category=${error.cause?.javaClass?.simpleName ?: "unknown"}")
                exitProcess(1)
            }
        }
    }
    val seams = mapOf(
        "default_unavailable_zero_ports" to "defaultUnavailableAndMissingConsentNeverTouchAnyPortIncludingCleanup",
        "one_pending_attempt" to "onePendingAndConcurrentCallbackConsumeAtMostOnce",
        "cancel_then_late_callback" to "denialReplayCancelAndTimeoutConsumeOnlyCurrentAttempt",
        "callback_replay" to "onePendingAndConcurrentCallbackConsumeAtMostOnce",
        "switch_then_late_exchange" to "switchThenLateExchangeCannotClobberNewPendingOwner",
        "signout_before_secure_commit" to "signoutAfterParsingBeforeAuthoritativeCommitRejectsInstallation",
        "commit_noop" to "lostCommitReplyVerifiedReadbackInstallsButNoopPartialUnreadableNeverDo",
        "commit_lost_reply_verified_readback" to "lostCommitReplyVerifiedReadbackInstallsButNoopPartialUnreadableNeverDo",
        "commit_unreadable_uncertain" to "lostCommitReplyVerifiedReadbackInstallsButNoopPartialUnreadableNeverDo",
        "initial_generation_zero" to "initialServerGenerationMustBeZeroRegardlessOfLocalGeneration",
        "serialized_refresh_one_consumption" to "overlappingRefreshSerializesLoadRequestValidateCommitAndCoalescesOneConsumption",
        "refresh_preserves_account_client_install_family" to "refreshPreservesNamespaceClientInstallationFamilyAndScopes",
        "refresh_wrong_owner_quarantine" to "refreshWrongOwnerBindingScopeGenerationAndTokenReuseQuarantineActualResponses",
        "refresh_lost_reply_no_parent_replay" to "lostRefreshReplyAndLocalCommitFailureNeverReplayOrResurrectParent",
        "signout_immediate_local_fence" to "signoutImmediateFenceWhileEraseDeferredNoopOrUnreadableNeverClaimsLocalCompletion",
        "signout_clear_noop_not_verified" to "signoutImmediateFenceWhileEraseDeferredNoopOrUnreadableNeverClaimsLocalCompletion",
        "offline_remote_revocation_pending" to "offlineRemoteRevokeIsPendingAndProofCannotRefreshOrConfigure",
        "revocation_proof_not_refresh_or_config" to "offlineRemoteRevokeIsPendingAndProofCannotRefreshOrConfigure",
        "restart_stale_or_corrupt_no_resurrection" to "recreationStaleCorruptPartialOrFailedSignoutRowCannotResurrectAndPendingIsUnsecured",
        "process_loss_invalidates_unsecured_attempt" to "recreationStaleCorruptPartialOrFailedSignoutRowCannotResurrectAndPendingIsUnsecured",
        "generation_exhaustion_fail_closed" to "generationExhaustionFailsClosedAndNeverWrapsToAnOldOwner",
        "no_health_or_profile_or_destination_or_schedule_or_purchase_effects" to "entropyFailureNoFallbackAndIndependentLocalOfflineSentinelsRemainUnchanged",
    )
    val required = fixture("fixtures/native-client-vectors.json").getValue("lifecycle_required").jsonArray.map { it.jsonPrimitive.content }
    checkSource(required.toSet() == seams.keys && required.size == 22 && seams.values.all { it in actualPassed }, "all required seams link to actual passed source tests")
    for (id in required) println("SEAM $id PASS actual-method=${seams.getValue(id)}")
    println("OK account-auth-source tests=$passed lifecycle-source-seams=22 (synthetic JVM source only; no OS/native qualification)")
}
