package com.healthmd.accountauth

import kotlinx.serialization.json.*
import org.junit.Test

class AccountAuthWireTest {
    @Test fun allSharedResponsesAssertEveryFieldPrivately() {
        val rows = fixture("fixtures/native-client-vectors.json").getValue("response_cases").jsonArray
        checkSource(rows.size == 73, "shared response count")
        var positives = 0
        for (element in rows) {
            val row = element.jsonObject
            val captured = context(row)
            if (!row.flag("valid")) { rejection(row.text("id")) { AccountAuthWire.decodeSession(raw(row), captured) }; continue }
            val session = AccountAuthWire.decodeSession(raw(row), captured)
            val e = row.getValue("expected").jsonObject
            // Fixed labels only. No assertEquals/string diff that could disclose held secret bytes.
            checkSource(session.tokenType == e.text("token_type"), "positive token_type")
            checkSource(session.accessToken.wire == e.text("access_token"), "positive access bytes")
            checkSource(session.expiresIn == e.long("expires_in"), "positive ttl")
            checkSource(session.refreshToken.wire == e.text("refresh_token"), "positive refresh bytes")
            checkSource(session.sessionId == e.text("session_id"), "positive family")
            checkSource(session.scope == e.text("scope"), "positive scopes")
            checkSource(session.namespace.issuer == e.text("issuer"), "positive issuer")
            checkSource(session.namespace.environment == e.text("environment"), "positive environment")
            checkSource(session.audience == e.text("audience"), "positive audience")
            checkSource(session.clientId == e.text("client_id"), "positive client")
            checkSource(session.installationId == e.text("installation_id"), "positive installation")
            checkSource(session.namespace.accountId == e.text("account_id"), "positive account")
            checkSource(session.sessionGeneration == e.long("session_generation"), "positive server generation")
            for (description in listOf(session.toString(), session.accessToken.toString(), session.refreshToken.toString(), session.namespace.toString())) {
                checkSource(!description.contains(session.accessToken.wire) && !description.contains(session.refreshToken.wire) &&
                    !description.contains(session.namespace.accountId), "redacted DTO description")
            }
            positives++
        }
        checkSource(positives == 8, "shared response positives")
        println("CORPUS responses=73 positive=8 negative=65 fields-per-positive=13")
    }

    @Test fun allSharedErrorsAreClosedNonSuccess() {
        val rows = fixture("fixtures/native-client-vectors.json").getValue("error_cases").jsonArray
        checkSource(rows.size == 15, "shared error count")
        val context = WireContext.forSyntheticTests("synthetic-android-play", reference(9), TEST_SCOPE)
        for (element in rows) {
            val row = element.jsonObject
            if (row.flag("valid")) checkSource(AccountAuthWire.decodeFailure(raw(row)).wireName == row.text("expected"), "fixed known error")
            else rejection(row.text("id")) { AccountAuthWire.decodeFailure(raw(row)) }
            rejection("error is never session") { AccountAuthWire.decodeSession(raw(row), context) }
        }
        println("CORPUS errors=15 known=9 negative=6 all-rejected-as-success=15")
    }

    @Test fun allSharedPkceUsesActualSha256() {
        val rows = fixture("fixtures/native-client-vectors.json").getValue("pkce_vectors").jsonArray
        checkSource(rows.size == 3, "shared pkce count")
        for (element in rows) {
            val row = element.jsonObject
            checkSource(AccountAuthPKCE.s256(row.text("verifier")) == row.text("challenge"), "private PKCE golden")
        }
        val entropy = CountingEntropy()
        val installation = AccountAuthPKCE.installationForSyntheticTests(entropy)
        val secrets = AccountAuthPKCE.freshForSyntheticTests(entropy, installation)
        checkSource(entropy.calls.get() == 3 && AccountAuthPKCE.isReference(secrets.state) &&
            AccountAuthPKCE.isReference(secrets.verifier) && AccountAuthPKCE.isReference(secrets.installationId), "fresh entropy formatting")
        checkSource(secrets.state != secrets.verifier && secrets.verifier != secrets.installationId &&
            secrets.challenge == AccountAuthPKCE.s256(secrets.verifier), "separate PKCE material")
        checkSource(!secrets.toString().contains(secrets.verifier), "redacted PKCE")
        for (invalid in listOf("short", "A".repeat(129), "C".repeat(42) + "é", "C".repeat(42) + "=")) rejection("invalid verifier") { AccountAuthPKCE.s256(invalid) }
        for (faultSize in listOf(0, 31, 33)) {
            entropy.size = faultSize
            rejection("entropy wrong size") { AccountAuthPKCE.freshForSyntheticTests(entropy, installation) }
        }
        entropy.failure = true
        rejection("entropy failure no fallback") { AccountAuthPKCE.freshForSyntheticTests(entropy, installation) }
        println("CORPUS PKCE=3 actual=JDK-SHA256/base64url")
    }

    @Test fun pinsMatchReviewedRegistryAndCannotBeCallerSubstituted() {
        val environments = fixture("source-policy.json").getValue("environments").jsonObject
        val synthetic = environments.getValue("synthetic").jsonObject
        for (element in synthetic.getValue("clients").jsonArray) {
            val client = element.jsonObject
            val registration = SyntheticRegistration.forWireTests(client.text("client_id"))
            checkSource(registration.issuer == synthetic.text("issuer") && registration.audience == synthetic.text("audience") &&
                registration.callback == client.text("callback") && registration.environment == "synthetic", "full pinned tuple")
        }
        for (env in listOf("development", "staging", "production")) checkSource(environments[env] == JsonNull, "no live registrations")
        for (id in listOf("synthetic-google", "android-play", "synthetic-android-play/extra", "synthetic-ANDROID-play")) {
            rejection("unregistered client") { SyntheticRegistration.forWireTests(id) }
        }
        rejection("write without read") { WireContext.forSyntheticTests("synthetic-android-play", reference(9), "config:profiles:write") }
        rejection("noncanonical captured scope") { WireContext.forSyntheticTests("synthetic-android-play", reference(9), "config:profiles:read account:sessions:read") }
    }

    @Test fun additionalRawGrammarBoundsAndNumbers() {
        val rows = fixture("fixtures/native-client-vectors.json").getValue("response_cases").jsonArray
        val row = rows.first().jsonObject
        val captured = context(row)
        val source = row.text("raw")
        val malformed = listOf("", "[]", "null", source + "x", source.replace("\"expires_in\":300", "\"expires_in\":300.0"),
            source.replace("\"session_generation\":0", "\"session_generation\":00"),
            source.replace("\"session_generation\":0", "\"session_generation\":+0"),
            source.replace("\"session_generation\":0", "\"session_generation\":9223372036854775808"),
            source.replace("\"account_id\":\"synthetic-account-a\"", "\"account_id\":\"synthetic-account-\\udc00\""),
            source.replace("\"account_id\":\"synthetic-account-a\"", "\"account_id\":\"synthetic-account-\\u0000\""),
            source.replace("\"access_token\":", "\"access_token\":["), source.dropLast(1) + ",}")
        for (text in malformed) rejection("extra raw grammar") { AccountAuthWire.decodeSession(bytes(text), captured) }
        for (utf8 in listOf(byteArrayOf(0xc0.toByte(), 0xaf.toByte()), byteArrayOf(0xed.toByte(), 0xa0.toByte(), 0x80.toByte()))) {
            rejection("strict invalid UTF8") { AccountAuthWire.decodeSession(utf8, captured) }
        }
        val padded = " ".repeat(AccountAuthWire.BODY_BYTES - bytes(source).size) + source
        checkSource(AccountAuthWire.decodeSession(bytes(padded), captured).sessionGeneration == 0L, "exact 8KiB accepted")
        rejection("8KiB plus one") { AccountAuthWire.decodeSession(bytes(" $padded"), captured) }
        for (input in listOf("{\"revoked\":false}", "{\"revoked\":true,\"message\":\"private\"}", "{\"revoked\":1}", "{\"revoked\":true,\"\\u0072evoked\":true}")) {
            rejection("closed revoke") { AccountAuthWire.requireRevoked(bytes(input)) }
        }
        AccountAuthWire.requireRevoked(bytes("{\"revoked\":true}"))
    }

    @Test fun serverAndLocalGenerationsAreDifferentAndTransitionsClosed() {
        val original = decodeFixture()
        val ctx = WireContext.forSyntheticTests(original.clientId, original.installationId, original.scope)
        val row = fixture("fixtures/native-client-vectors.json").getValue("response_cases").jsonArray.map { it.jsonObject }
            .first { it.text("id") == "success-synthetic-android-play" }
        fun session(generation: Long): NativeSession = AccountAuthWire.decodeSession(patched(raw(row), mapOf(
            "session_generation" to JsonPrimitive(generation), "access_token" to JsonPrimitive("hmd_nac_${reference(10)}"),
            "refresh_token" to JsonPrimitive("hmd_nrf_${reference(11)}"))), ctx)
        AccountAuthWire.requireInitial(original)
        rejection("initial nonzero") { AccountAuthWire.requireInitial(session(1)) }
        AccountAuthWire.requireRefresh(original, session(1))
        rejection("refresh does not increment") { AccountAuthWire.requireRefresh(original, session(0)) }
        rejection("refresh skips generation") { AccountAuthWire.requireRefresh(original, session(2)) }
        rejection("refresh overflow never wraps") { AccountAuthWire.requireRefresh(session(AccountAuthWire.MAX_SERVER_GENERATION), session(0)) }
    }
}
