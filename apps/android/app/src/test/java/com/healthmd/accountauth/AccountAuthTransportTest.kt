package com.healthmd.accountauth

import kotlinx.serialization.json.*
import org.junit.Test

class AccountAuthTransportTest {
    private val registration = SyntheticRegistration.forWireTests("synthetic-android-play")
    private fun secret(): AttemptSecrets {
        val entropy = CountingEntropy()
        return AccountAuthPKCE.freshForSyntheticTests(entropy, AccountAuthPKCE.installationForSyntheticTests(entropy))
    }

    @Test fun exactPinnedJsonRequestsHaveNoForeignCredentialOrReplayPolicy() {
        val secrets = secret()
        val code = AuthorizationCode("hmd_acode_${reference(7)}")
        val session = decodeFixture()
        val window = AuthRequestWindow.capture(100)
        val plans = listOf(AuthRequestPlan.code(registration, code, secrets, window), AuthRequestPlan.refresh(registration, session, window),
            AuthRequestPlan.revoke(registration, session.refreshToken, session.installationId, window))
        for (plan in plans) {
            checkSource(plan.window === window && plan.window.startedAtSeconds == 100L &&
                plan.window.deadlineAtSeconds == 105L && plan.window.timeoutSeconds == 5L, "closed finite source request window")
            checkSource(plan.method == "POST" && !plan.allowCookies && !plan.allowRedirects && plan.transparentRetries == 0 &&
                plan.responseByteLimit == 8192 && plan.headers == mapOf("Content-Type" to "application/json", "Accept" to "application/json"), "exact request policy")
            checkSource(plan.url == if (plan.kind == AuthRequestKind.REVOKE) registration.revokeEndpoint else registration.tokenEndpoint, "pinned request URL")
            val request = Json.parseToJsonElement(plan.bodyBytes().toString(Charsets.UTF_8)).jsonObject
            val expected = when (plan.kind) {
                AuthRequestKind.CODE -> mapOf("grant_type" to "authorization_code", "client_id" to registration.clientId,
                    "redirect_uri" to registration.callback, "code" to code.wire, "code_verifier" to secrets.verifier, "installation_id" to secrets.installationId)
                AuthRequestKind.REFRESH -> mapOf("grant_type" to "refresh_token", "client_id" to registration.clientId,
                    "installation_id" to session.installationId, "refresh_token" to session.refreshToken.wire)
                AuthRequestKind.REVOKE -> mapOf("client_id" to registration.clientId, "installation_id" to session.installationId,
                    "refresh_token" to session.refreshToken.wire)
            }
            checkSource(request.keys == expected.keys && expected.all { (key, value) -> request.text(key) == value }, "every private outbound field")
            val mutated = plan.bodyBytes(); mutated.fill(0)
            checkSource(plan.bodyBytes().any { it != 0.toByte() }, "immutable body snapshot")
            checkSource(!plan.toString().contains(code.wire) && !plan.toString().contains(session.refreshToken.wire), "redacted request description")
        }
        var immutable = false
        try { (plans.first().headers as MutableMap)["Cookie"] = "synthetic" } catch (_: UnsupportedOperationException) { immutable = true }
        checkSource(immutable, "immutable headers")
    }

    @Test fun actualCloudUtf8HeadersAndBareJsonBothWorkWithoutWireProvenanceFlags() {
        val session = decodeFixture()
        val ctx = WireContext.forSyntheticTests(session.clientId, session.installationId, session.scope)
        val row = fixture("fixtures/native-client-vectors.json").getValue("response_cases").jsonArray.map { it.jsonObject }
            .first { it.text("id") == "success-synthetic-android-play" }
        val plan = AuthRequestPlan.refresh(registration, session, AuthRequestWindow.capture(100))
        for (type in listOf("application/json", "application/json; charset=utf-8")) {
            val headers = SyntheticReply.sourceJsonHeaders().map { if (it.first == "Content-Type") it.first to type else it } +
                listOf("Content-Security-Policy" to "default-src 'none'; frame-ancestors 'none'; base-uri 'none'", "X-Frame-Options" to "DENY")
            val result = tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, request.url, 200, raw(row), headers) }, plan, ctx)
            checkSource(result is TokenReply.Session && result.value.same(session), "actual closed response with reviewed headers")
        }
        rejection("response cannot self-attest provenance") {
            tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, request.url, 200,
                patched(raw(row), mapOf("trusted_transport" to JsonPrimitive(true)))) }, plan, ctx)
        }
        println("TRANSPORT positive-media-types=2 includes-actual-Cloud-UTF8 headers=no-store/no-referrer")
    }

    @Test fun boundedHeadersStatusRedirectCookieAndRequestCorrelationReject() {
        val session = decodeFixture()
        val ctx = WireContext.forSyntheticTests(session.clientId, session.installationId, session.scope)
        val row = fixture("fixtures/native-client-vectors.json").getValue("response_cases").jsonArray.map { it.jsonObject }
            .first { it.text("id") == "success-synthetic-android-play" }
        val body = raw(row)
        val plan = AuthRequestPlan.refresh(registration, session, AuthRequestWindow.capture(100))
        val source = SyntheticReply.sourceJsonHeaders()
        val headers = mutableListOf<List<Pair<String, String>>>()
        for (media in listOf("text/html", "application/json; charset=utf-16", "application/json; charset=iso-8859-1", "application/json; charset=utf-8; extra=1")) {
            headers += source.map { if (it.first == "Content-Type") it.first to media else it }
        }
        for (forbidden in listOf("Cookie", "Set-Cookie", "Authorization", "Proxy-Authorization", "sEt-CoOkIe")) headers += source + (forbidden to "synthetic")
        headers += source.filter { it.first != "Cache-Control" }
        headers += source.filter { it.first != "Referrer-Policy" }
        headers += source.map { if (it.first == "Cache-Control") it.first to "public" else it }
        headers += source.map { if (it.first == "Referrer-Policy") it.first to "unsafe-url" else it }
        headers += source + ("content-type" to "application/json")
        headers += source + ("X-Bad" to "synthetic\r\nCookie: synthetic")
        headers += source + ("X-Large" to "x".repeat(1025))
        headers += source + List(13) { "X-$it" to "x" }
        headers += source + List(5) { "X-$it" to "x".repeat(900) }
        for (candidate in headers) rejection("closed bounded receipt headers") {
            tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, request.url, 200, body, candidate) }, plan, ctx)
        }
        for (status in listOf(201, 204, 301, 307, 400, 503)) rejection("non-200 token success") {
            tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, request.url, status, body) }, plan, ctx)
        }
        for (url in listOf(plan.url + "?", plan.url + "/", plan.url.replace("https:", "http:"), "https://evil.example/token")) rejection("exact final URL") {
            tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, url, 200, body) }, plan, ctx)
        }
        rejection("redirect despite final exact URL") { tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, request.url, 200, body, redirectHops = 1) }, plan, ctx) }
        rejection("reply for a different request") {
            tokenReply(SyntheticAuthTransport { request -> SyntheticReply(AuthRequestPlan.refresh(registration, session, plan.window), request.url, 200, body) }, plan, ctx)
        }
        for (invalid in listOf(ByteArray(0), ByteArray(8193))) rejection("bounded response receipt") {
            tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, request.url, 200, invalid) }, plan, ctx)
        }
        println("TRANSPORT negative-header-sets=${headers.size} status-cases=6 URL-cases=4 correlation/redirect/bounds=4")
    }

    @Test fun everyFixedFailureRequiresItsActualStatusAndNeverReturnsSession() {
        val session = decodeFixture()
        val plan = AuthRequestPlan.refresh(registration, session, AuthRequestWindow.capture(100))
        val ctx = WireContext.forSyntheticTests(session.clientId, session.installationId, session.scope)
        for (failure in AuthFailure.entries) {
            val body = bytes("{\"error\":\"${failure.wireName}\"}")
            val result = tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, request.url, failure.httpStatus, body) }, plan, ctx)
            checkSource(result is TokenReply.Failure && result.value == failure, "fixed error/status binding")
            for (status in listOf(200, 201, if (failure.httpStatus == 400) 401 else 400)) rejection("error wrong status or successful-session confusion") {
                tokenReply(SyntheticAuthTransport { request -> SyntheticReply(request, request.url, status, body) }, plan, ctx)
            }
        }
    }
}
