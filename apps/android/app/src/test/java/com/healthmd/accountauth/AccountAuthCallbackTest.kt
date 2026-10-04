package com.healthmd.accountauth

import kotlinx.serialization.json.*
import org.junit.Test

class AccountAuthCallbackTest {
    @Test fun all32SharedCallbacksReachParserOrActualOwnerFence() {
        val rows = fixture("fixtures/security-vectors.json").getValue("callback_vectors").jsonArray
        checkSource(rows.size == 32, "shared callbacks count")
        val apple = SyntheticRegistration.forWireTests("synthetic-apple-ios")
        val state = reference(31)
        val code = "hmd_acode_${reference(23)}"
        var ownerCases = 0
        for (element in rows) {
            val row = element.jsonObject
            val id = row.text("id")
            if (id in setOf("cancelled_attempt", "account_switch_callback", "unregistered_production")) {
                val rig = AuthRig()
                if (id == "unregistered_production") {
                    val owner = AccountAuthCoordinator.unavailableForSyntheticTests(rig.ports)
                    checkSource(owner.acceptCallback(bytes("${apple.callback}?code=$code&state=$state&iss=${apple.issuer}")) == AuthAction.UNAVAILABLE, "unregistered owner")
                    rig.noPortCalls()
                } else {
                    val callback = rig.begin()
                    if (id == "cancelled_attempt") checkSource(rig.owner.cancelAttempt() == AuthAction.CANCELLED, "actual cancellation")
                    else checkSource(rig.owner.switchTo(AndroidAuthChannel.FDROID) == AuthAction.FENCED, "actual switch")
                    checkSource(rig.owner.acceptCallback(callback) == AuthAction.REJECTED && rig.transport.count() == 0, "actual stale owner callback")
                }
                ownerCases++
                continue
            }
            val raw = row.text("uri").replace("{callback}", apple.callback).replace("{code}", code)
                .replace("{state}", state).replace("{issuer}", apple.issuer).replace("{refresh}", "hmd_nrf_${reference(22)}")
            val registration = if (id == "wrong_public_client") SyntheticRegistration.forWireTests("synthetic-android-play") else apple
            when (row.text("expected")) {
                "accept_code" -> {
                    val accepted = AccountAuthCallback.decode(bytes(raw), registration, state) as? CallbackResult.Code
                    checkSource(accepted?.code?.wire == code && !accepted.toString().contains(code), "positive callback private bytes")
                }
                "accept_denial" -> checkSource(AccountAuthCallback.decode(bytes(raw), registration, state) == CallbackResult.Denied, "fixed denial")
                else -> rejection(id) { AccountAuthCallback.decode(bytes(raw), registration, state) }
            }
        }
        checkSource(ownerCases == 3, "context vectors exercised in actual source owner")
        println("CORPUS callbacks=32 raw-parser=29 actual-owner-context=3")
    }

    @Test fun exactPinnedCallbacksForEveryContextAndBothAndroidOwners() {
        val state = reference(1)
        val code = "hmd_acode_${reference(2)}"
        for (client in listOf("synthetic-apple-ios", "synthetic-apple-ipados", "synthetic-apple-macos", "synthetic-android-play", "synthetic-android-fdroid")) {
            val registration = SyntheticRegistration.forWireTests(client)
            val callback = bytes("${registration.callback}?code=$code&state=$state&iss=${registration.issuer}")
            checkSource((AccountAuthCallback.decode(callback, registration, state) as CallbackResult.Code).code.wire == code, "each exact pinned callback")
        }
        for (channel in AndroidAuthChannel.entries) {
            val rig = AuthRig(channel)
            rig.signIn()
            checkSource(rig.owner.status().clientId == channel.clientId && rig.owner.status().sessionGeneration == 0L, "both actual Android owners")
            val plan = rig.consent.query()
            checkSource(plan.keys == setOf("client_id", "redirect_uri", "response_type", "scope", "state", "code_challenge", "code_challenge_method", "audience"), "closed authorization plan")
            checkSource(plan["client_id"] == channel.clientId && plan["redirect_uri"] == SyntheticRegistration.android(channel).callback &&
                plan["response_type"] == "code" && plan["code_challenge_method"] == "S256" && plan["audience"] == SyntheticRegistration.AUDIENCE &&
                plan["scope"] == TEST_SCOPE && AccountAuthPKCE.isReference(plan.getValue("code_challenge")), "full outbound authorization values")
        }
        println("CALLBACK positives pinned=5 Android-coordinator-channels=2")
    }

    @Test fun rawBoundsUtf8ControlsAndAliasesBeforeNormalization() {
        val registration = SyntheticRegistration.forWireTests("synthetic-android-fdroid")
        val state = reference(1)
        val valid = "${registration.callback}?code=hmd_acode_${reference(2)}&state=$state&iss=${registration.issuer}"
        for (raw in listOf(valid + "?", valid + "&", " $valid", valid + '\u007f', valid + '\u0085', valid.replace("state=", "sta%74e="),
            valid.replace("https://callbacks", "http://callbacks"), valid.replace("state=$state", "state=$state="), valid.replace("/return?", "/return\\?"),
            valid.replace("?code=", "?code=%"), valid + "&session_id=" + reference(3))) {
            rejection("raw callback rejection") { AccountAuthCallback.decode(bytes(raw), registration, state) }
        }
        rejection("4KiB overflow before normalization") { AccountAuthCallback.decode(ByteArray(4097) { 65 }, registration, state) }
        rejection("callback strict UTF8") { AccountAuthCallback.decode(byteArrayOf(0xed.toByte(), 0xa0.toByte(), 0x80.toByte()), registration, state) }
    }

    @Test fun denialReplayCancelAndTimeoutConsumeOnlyCurrentAttempt() {
        val rig = AuthRig()
        val callback = rig.begin()
        checkSource(rig.owner.begin(TEST_SCOPE) == AuthAction.REJECTED && rig.consent.calls.get() == 1, "one pending attempt")
        val query = rig.consent.query()
        val denial = bytes(query.getValue("redirect_uri") + "?error=access_denied&state=" + query.getValue("state") + "&iss=" + SyntheticRegistration.ISSUER)
        checkSource(rig.owner.acceptCallback(denial) == AuthAction.DENIED && rig.owner.acceptCallback(callback) == AuthAction.REJECTED &&
            rig.transport.count() == 0, "denial consumes current pending without transport")
        val late = rig.begin()
        checkSource(rig.owner.cancelAttempt() == AuthAction.CANCELLED && rig.owner.acceptCallback(late) == AuthAction.REJECTED, "cancel invalidation")
        val timed = rig.begin()
        rig.clock.value.set(400)
        checkSource(rig.owner.acceptCallback(timed) == AuthAction.REJECTED && rig.owner.status().lastFence?.reason == FenceReason.TIMEOUT &&
            rig.transport.count() == 0, "timeout at equality")
        rig.clock.value.set(100)
        rig.signIn()
        checkSource(rig.owner.acceptCallback(rig.callback()) == AuthAction.REJECTED && rig.transport.count(AuthRequestKind.CODE) == 1, "callback replay one consumption")
    }
}
