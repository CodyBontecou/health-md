package com.healthmd.accountauth

import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlinx.serialization.json.*

internal const val TEST_SCOPE = "account:sessions:read account:sessions:revoke:self config:profiles:read config:profiles:write"
internal fun checkSource(condition: Boolean, label: String) { if (!condition) throw AssertionError(label) }
internal fun bytes(value: String): ByteArray = value.toByteArray(StandardCharsets.UTF_8)
internal fun reference(value: Int): String = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32) { value.toByte() })
internal fun fixture(path: String): JsonObject {
    val explicit = System.getProperty("healthmd.accountauth.root")
    val root = explicit?.let { Path.of(it) } ?: generateSequence(Path.of(System.getProperty("user.dir")).toAbsolutePath()) { it.parent }
        .first { Files.isDirectory(it.resolve("packages/contracts/account-auth/v1")) }
    return Json.parseToJsonElement(Files.readString(root.resolve("packages/contracts/account-auth/v1/$path"))).jsonObject
}
internal fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content
internal fun JsonObject.long(key: String): Long = getValue(key).jsonPrimitive.long
internal fun JsonObject.flag(key: String): Boolean = getValue(key).jsonPrimitive.boolean
internal fun context(row: JsonObject): WireContext {
    val c = row.getValue("context").jsonObject
    val result = WireContext.forSyntheticTests(c.text("client_id"), c.text("installation_id"), c.text("scope"))
    checkSource(result.registration.issuer == c.text("issuer") && result.registration.environment == c.text("environment") &&
        result.registration.audience == c.text("audience") && result.registration.callback == c.text("callback"), "pinned corpus context")
    return result
}
internal fun raw(row: JsonObject): ByteArray = when {
    "raw" in row -> bytes(row.text("raw"))
    "hex" in row -> row.text("hex").chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    else -> ByteArray(row.long("repeat").toInt()) { 0x20 }
}
internal fun rejection(label: String, action: () -> Unit) {
    var rejected = false
    try { action() } catch (_: AuthSourceException) { rejected = true }
    checkSource(rejected, label)
}
internal fun decodeFixture(client: String = "synthetic-android-play"): NativeSession {
    val row = fixture("fixtures/native-client-vectors.json").getValue("response_cases").jsonArray
        .map { it.jsonObject }.first { it.text("id") == "success-$client" }
    return AccountAuthWire.decodeSession(raw(row), context(row))
}
internal fun patched(body: ByteArray, patch: Map<String, JsonElement>): ByteArray {
    val original = Json.parseToJsonElement(body.toString(StandardCharsets.UTF_8)).jsonObject
    return bytes(JsonObject(original + patch).toString())
}

internal class CountingEntropy : SyntheticEntropy {
    val calls = AtomicInteger()
    var failure: Boolean = false
    var size: Int = 32
    override fun bytes(count: Int): ByteArray {
        checkSource(count == 32, "entropy bound")
        val next = calls.incrementAndGet()
        if (failure) throw IllegalStateException("synthetic fault")
        return ByteArray(size) { (next + 32).toByte() }
    }
}
internal class CountingClock : SyntheticClock {
    val calls = AtomicInteger()
    val value = AtomicLong(100)
    override fun seconds(): Long { calls.incrementAndGet(); return value.get() }
}
internal class ReviewSink : SyntheticConsentPort {
    val calls = AtomicInteger()
    private val plans = mutableListOf<AuthorizationPlan>()
    override fun reviewOnly(plan: AuthorizationPlan) { synchronized(plans) { plans.add(plan) }; calls.incrementAndGet() }
    fun latest(): AuthorizationPlan = synchronized(plans) { plans.last() }
    fun query(): Map<String, String> = latest().rawUrl.substringAfter('?').split('&').associate { pair ->
        val fields = pair.split('=')
        fields[0] to java.net.URLDecoder.decode(fields[1], StandardCharsets.UTF_8.name())
    }
}

internal enum class VaultFault { NONE, NOOP, LOST_REPLY, BEFORE_COMMIT, UNREADABLE_AFTER_COMMIT, STALE_READBACK, PARTIAL, WRONG_OWNER, WRONG_GENERATION, WRONG_INSTALLATION, MISSING_RECEIPT }
internal class FaultVault : SyntheticAccountVault {
    private val lock = Any()
    private var image: VaultImage? = null
    private var previous: VaultImage? = null
    val reads = AtomicInteger()
    val writes = AtomicInteger()
    @Volatile var fault = VaultFault.NONE
    @Volatile var failReads = false
    @Volatile var staleRead = false
    val beforeCommit = AtomicReference<(() -> Unit)?>(null)
    val afterCommit = AtomicReference<(() -> Unit)?>(null)
    val beforeRead = AtomicReference<(() -> Unit)?>(null)
    override fun readNormal(): VaultImage? {
        reads.incrementAndGet()
        beforeRead.getAndSet(null)?.invoke()
        if (failReads) throw IllegalStateException("synthetic unreadable")
        return synchronized(lock) { if (staleRead) previous else image }
    }
    override fun transact(gate: AccountCommitGate, change: (VaultImage?) -> VaultImage) {
        writes.incrementAndGet()
        beforeCommit.getAndSet(null)?.invoke() // actual deferred preparation, outside authoritative gate
        if (fault == VaultFault.BEFORE_COMMIT) throw IllegalStateException("synthetic rollback")
        gate.commit {
            synchronized(lock) {
                val candidate = change(image)
                previous = image
                val record = candidate.normal
                image = when (fault) {
                    VaultFault.NOOP -> image
                    VaultFault.PARTIAL -> VaultImage(candidate.processOwner, candidate.localGeneration, candidate.signedOut,
                        record?.let { VaultSession(null, it.localGeneration, it.expiresAt, it.installationBinding) }, candidate.receipt)
                    VaultFault.WRONG_OWNER -> VaultImage(Any(), candidate.localGeneration, candidate.signedOut, record, candidate.receipt)
                    VaultFault.WRONG_GENERATION -> VaultImage(candidate.processOwner, candidate.localGeneration + 1, candidate.signedOut, record, candidate.receipt)
                    VaultFault.WRONG_INSTALLATION -> VaultImage(candidate.processOwner, candidate.localGeneration, candidate.signedOut,
                        record?.let { VaultSession(it.session, it.localGeneration, it.expiresAt, reference(99)) }, candidate.receipt)
                    VaultFault.MISSING_RECEIPT -> VaultImage(candidate.processOwner, candidate.localGeneration, candidate.signedOut, record, Any())
                    else -> candidate
                }
                if (fault == VaultFault.UNREADABLE_AFTER_COMMIT) failReads = true
                if (fault == VaultFault.STALE_READBACK) staleRead = true
            }
        }
        afterCommit.getAndSet(null)?.invoke() // real committed row, prior to owner readback/visibility
        if (fault == VaultFault.LOST_REPLY) throw IllegalStateException("synthetic lost reply")
    }
    fun inject(value: VaultImage?) { synchronized(lock) { image = value } }
    fun inspect(): VaultImage? = synchronized(lock) { image }
}

internal class FakeTransport(private val scope: String = TEST_SCOPE) : SyntheticAuthTransport {
    private val requests = mutableListOf<AuthRequestPlan>()
    private val sequence = AtomicInteger()
    private val generation = AtomicLong(-1)
    private val family = AtomicReference(reference(13))
    @Volatile var handler: ((AuthRequestPlan) -> SyntheticReply)? = null
    override fun sendOnce(plan: AuthRequestPlan): SyntheticReply {
        synchronized(requests) { requests.add(plan) }
        checkSource(plan.method == "POST" && plan.url.startsWith(SyntheticRegistration.ISSUER + "/api/account-auth/v1/"), "exact fake route")
        checkSource(!plan.allowCookies && !plan.allowRedirects && plan.transparentRetries == 0, "fake no replay/redirect/cookie")
        return handler?.invoke(plan) ?: normalReply(plan)
    }
    fun normalReply(plan: AuthRequestPlan): SyntheticReply {
        if (plan.kind == AuthRequestKind.REVOKE) return SyntheticReply(plan, plan.url, 200, bytes("{\"revoked\":true}"))
        val request = Json.parseToJsonElement(plan.bodyBytes().toString(StandardCharsets.UTF_8)).jsonObject
        val next = sequence.incrementAndGet()
        val serverGeneration = if (plan.kind == AuthRequestKind.CODE) { generation.set(0); family.set(reference(next + 13)); 0L } else generation.incrementAndGet()
        val fields = linkedMapOf<String, JsonElement>("token_type" to JsonPrimitive("Bearer"),
            "access_token" to JsonPrimitive("hmd_nac_${reference(next + 50)}"), "expires_in" to JsonPrimitive(300),
            "refresh_token" to JsonPrimitive("hmd_nrf_${reference(next + 80)}"), "session_id" to JsonPrimitive(family.get()),
            "scope" to JsonPrimitive(scope), "issuer" to JsonPrimitive(SyntheticRegistration.ISSUER),
            "environment" to JsonPrimitive("synthetic"), "audience" to JsonPrimitive(SyntheticRegistration.AUDIENCE),
            "client_id" to JsonPrimitive(request.text("client_id")), "installation_id" to JsonPrimitive(request.text("installation_id")),
            "account_id" to JsonPrimitive("synthetic-account-a"), "session_generation" to JsonPrimitive(serverGeneration))
        return SyntheticReply(plan, plan.url, 200, bytes(JsonObject(fields).toString()))
    }
    fun all(): List<AuthRequestPlan> = synchronized(requests) { requests.toList() }
    fun count(kind: AuthRequestKind? = null): Int = all().count { kind == null || it.kind == kind }
}

internal class AuthRig(channel: AndroidAuthChannel = AndroidAuthChannel.PLAY, consentPresent: Boolean = true, seed: Long = 0) {
    val entropy = CountingEntropy()
    val clock = CountingClock()
    val vault = FaultVault()
    val transport = FakeTransport()
    val consent = ReviewSink()
    val ports = SyntheticAuthPorts(entropy, clock, vault, transport, if (consentPresent) consent else null)
    val owner = AccountAuthCoordinator.forSyntheticTests(channel, ports, seed)
    fun callback(): ByteArray {
        val query = consent.query()
        return bytes(query.getValue("redirect_uri") + "?code=hmd_acode_${reference(23)}&state=" + query.getValue("state") + "&iss=" + SyntheticRegistration.ISSUER)
    }
    fun begin(): ByteArray { checkSource(owner.begin(TEST_SCOPE) == AuthAction.STARTED, "actual begin"); return callback() }
    fun signIn() { checkSource(owner.acceptCallback(begin()) == AuthAction.INSTALLED, "actual initial install") }
    fun noPortCalls() {
        checkSource(entropy.calls.get() == 0 && clock.calls.get() == 0 && vault.reads.get() == 0 && vault.writes.get() == 0 &&
            transport.count() == 0 && consent.calls.get() == 0, "default zero ports")
    }
}

internal class DeferredPoint {
    private val reached = CountDownLatch(1)
    private val released = CountDownLatch(1)
    fun pause() { reached.countDown(); checkSource(released.await(5, TimeUnit.SECONDS), "deferred release bound") }
    fun awaitReached() { checkSource(reached.await(5, TimeUnit.SECONDS), "deferred reached") }
    fun release() { released.countDown() }
}
internal class RunningAction(action: () -> AuthAction) {
    private val result = AtomicReference<AuthAction>()
    private val failure = AtomicReference<Throwable>()
    val thread = Thread {
        try { result.set(action()) } catch (error: Throwable) { failure.set(error) }
    }.apply { isDaemon = true; start() }
    fun awaitWaiting() {
        val end = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (thread.state != Thread.State.WAITING && System.nanoTime() < end) Thread.sleep(1)
        checkSource(thread.state == Thread.State.WAITING, "second actual refresh waiting on lock")
    }
    fun finish(): AuthAction {
        thread.join(5000)
        checkSource(!thread.isAlive && failure.get() == null, "actual worker completed")
        return result.get() ?: throw AssertionError("actual worker result")
    }
}
