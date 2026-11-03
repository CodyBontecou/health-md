package com.healthmd.domain.practice

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class ClinicReviewFact(val label: String, val value: String)
enum class ClinicInboxAccess { CLINIC_COVERED, CONSUMER, UNAVAILABLE }
data class ClinicInboxReview(
    val id: String, val digest: String, val clinic: String, val profile: String, val destination: String,
    val metrics: List<String>, val options: List<ClinicReviewFact>, val schedule: String,
    val expiresAtMillis: Long, val access: ClinicInboxAccess,
)
enum class ClinicInboxStatus { REQUESTED, RUNNING, UPLOADED, PROCESSED, FAILED, CANCELLED, EXPIRED, REVOKED }
data class ClinicInboxRefresh(
    val id: String, val connectionId: String, val clinic: String, val profile: String, val destination: String,
    val scope: String, val metrics: List<String>, val status: ClinicInboxStatus, val receiptPending: Boolean = false, val sharingActive: Boolean = true,
)
data class ClinicInboxSnapshot(val synthetic: Boolean = false, val reviews: List<ClinicInboxReview> = emptyList(), val refreshes: List<ClinicInboxRefresh> = emptyList())
/** Internal presentation port, not a SetClinic wire API. A trusted mapper derives facts from the full local
 * native snapshot/digest and delegates actions to ClinicNativeOnboarding/ClinicForegroundRefresh and native gates. */
interface ClinicInboxTransport {
    /** Non-secret account/session generation key; never a token or Authorization value. */
    val sessionId: String?
    suspend fun load(): ClinicInboxSnapshot
    suspend fun applySetup(id: String, reviewedDigest: String)
    suspend fun export(id: String)
    suspend fun reportReceipt(id: String)
    suspend fun cancel(id: String)
    suspend fun revoke(connectionId: String)
}
object UnavailableClinicInboxTransport : ClinicInboxTransport {
    override val sessionId: String? = null
    override suspend fun load(): ClinicInboxSnapshot = error("unavailable")
    override suspend fun applySetup(id: String, reviewedDigest: String): Unit = error("unavailable")
    override suspend fun export(id: String): Unit = error("unavailable")
    override suspend fun reportReceipt(id: String): Unit = error("unavailable")
    override suspend fun cancel(id: String): Unit = error("unavailable")
    override suspend fun revoke(connectionId: String): Unit = error("unavailable")
}
data class ClinicInboxState(
    val snapshot: ClinicInboxSnapshot = ClinicInboxSnapshot(), val review: ClinicInboxReview? = null,
    val consent: Boolean = false, val loading: Boolean = false, val busy: Boolean = false,
    val unavailable: Boolean = false, val error: Boolean = false,
)
/** Feature-local controller. Call on the UI dispatcher; no export occurs on loading or navigation. */
class ClinicInboxController(
    private val transport: ClinicInboxTransport = UnavailableClinicInboxTransport,
    private val enabled: () -> Boolean = { PracticeFeaturePolicy.current().isEnabled },
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val mutable = MutableStateFlow(ClinicInboxState())
    val state: StateFlow<ClinicInboxState> = mutable
    private var loadedSession: String? = null
    private var generation = 0
    val canApply: Boolean get() = state.value.let { value ->
        value.review?.let { value.consent && !value.busy && !value.error && it.expiresAtMillis > now() && it.metrics.isNotEmpty()
            && it.digest.isNotEmpty() && loadedSession != null && loadedSession == transport.sessionId && enabled() } ?: false
    }
    fun clear() { generation++; loadedSession = null; mutable.value = ClinicInboxState() }
    fun dismissReview() { mutable.value = state.value.copy(review = null, consent = false) }
    fun setConsent(value: Boolean) { mutable.value = state.value.copy(consent = value) }
    fun openReview(id: String) {
        if (loadedSession == null || loadedSession != transport.sessionId) { clear(); return }
        if (!state.value.busy) mutable.value = state.value.copy(review = state.value.snapshot.reviews.firstOrNull {
            it.id == id && it.expiresAtMillis > now()
        }, consent = false)
    }
    suspend fun load() {
        if (state.value.busy) return
        clear()
        val session = transport.sessionId
        if (!enabled() || session == null) { mutable.value = state.value.copy(unavailable = true); return }
        val ticket = generation; mutable.value = state.value.copy(loading = true)
        try {
            val result = transport.load().frozenCopy()
            if (ticket != generation) return
            if (session != transport.sessionId) { clear(); return }
            loadedSession = session; mutable.value = ClinicInboxState(snapshot = result)
        } catch (_: CancellationException) { if (ticket == generation) clear() }
        catch (_: Exception) { if (ticket == generation) { clear(); mutable.value = state.value.copy(error = true) } }
    }
    suspend fun apply(): Boolean {
        if (loadedSession == null || loadedSession != transport.sessionId) { clear(); return false }
        if (!canApply) return false
        val review = state.value.review ?: return false
        return perform { transport.applySetup(review.id, review.digest) }
    }
    suspend fun export(id: String) {
        if (state.value.snapshot.refreshes.none { it.id == id && it.status == ClinicInboxStatus.REQUESTED && it.sharingActive }) return
        perform { transport.export(id) }
    }
    suspend fun reportReceipt(id: String) {
        if (state.value.snapshot.refreshes.none { it.id == id && it.status == ClinicInboxStatus.UPLOADED && it.receiptPending }) return
        perform { transport.reportReceipt(id) }
    }
    suspend fun cancel(id: String) {
        if (state.value.snapshot.refreshes.none { it.id == id && it.status in listOf(ClinicInboxStatus.REQUESTED, ClinicInboxStatus.RUNNING) }) return
        perform { transport.cancel(id) }
    }
    suspend fun revoke(connectionId: String) {
        if (state.value.snapshot.refreshes.none { it.connectionId == connectionId && it.sharingActive }) return
        perform { transport.revoke(connectionId) }
    }
    private suspend fun perform(operation: suspend () -> Unit): Boolean {
        val session = loadedSession
        if (state.value.busy || state.value.error) return false
        if (!enabled() || session == null || session != transport.sessionId) { clear(); return false }
        val ticket = generation; mutable.value = state.value.copy(busy = true, error = false)
        try {
            operation()
            if (ticket != generation) return false
            if (session != transport.sessionId) { clear(); return false }
            val result = transport.load().frozenCopy()
            if (ticket != generation) return false
            if (session != transport.sessionId) { clear(); return false }
            mutable.value = ClinicInboxState(snapshot = result); return true
        } catch (_: CancellationException) { if (ticket == generation) clear(); return false }
        catch (_: Exception) {
            if (ticket != generation) return false
            if (session == transport.sessionId) mutable.value = state.value.copy(busy = false, error = true)
            else clear()
            return false
        }
    }
}

/** Explicit fixture injection only. Does not read Health data, permissions, billing or network. */
class SyntheticClinicInboxTransport(now: Long = System.currentTimeMillis()) : ClinicInboxTransport {
    override var sessionId: String? = "session_synthetic"
    var value = ClinicInboxSnapshot(synthetic = true, reviews = listOf(ClinicInboxReview("setup_synthetic", "digest_synthetic", "Synthetic clinic",
        "Clinic profile", "Synthetic clinic endpoint", listOf("Steps", "Average heart rate"), listOf(
            ClinicReviewFact("Formats", "JSON, CSV"), ClinicReviewFact("Detail", "Summary"), ClinicReviewFact("Write mode", "Update")),
        "Daily at 12:00 UTC · starts paused", now + 900_000, ClinicInboxAccess.CLINIC_COVERED)),
        refreshes = listOf(ClinicInboxRefresh("refresh_synthetic", "connection_synthetic", "Synthetic clinic", "Clinic profile",
            "Synthetic clinic endpoint", "1–2 November 2026 · UTC", listOf("Steps", "Average heart rate"), ClinicInboxStatus.REQUESTED)))
    var exports = 0; private set
    var receiptsReported = 0; private set
    override suspend fun load(): ClinicInboxSnapshot { check(sessionId != null); return value }
    override suspend fun applySetup(id: String, reviewedDigest: String) {
        check(value.reviews.any { it.id == id && it.digest == reviewedDigest })
        value = value.copy(reviews = value.reviews.filterNot { it.id == id })
    }
    override suspend fun export(id: String) { exports++; update(id) { it.copy(status = ClinicInboxStatus.UPLOADED, receiptPending = true) } }
    override suspend fun reportReceipt(id: String) { receiptsReported++; update(id) { it.copy(receiptPending = false) } }
    override suspend fun cancel(id: String) { update(id) { it.copy(status = ClinicInboxStatus.CANCELLED) } }
    override suspend fun revoke(connectionId: String) { value = value.copy(refreshes = value.refreshes.map {
        if (it.connectionId == connectionId) it.copy(sharingActive = false, status = if (it.status in listOf(ClinicInboxStatus.REQUESTED, ClinicInboxStatus.RUNNING)) ClinicInboxStatus.REVOKED else it.status) else it
    }) }
    private fun update(id: String, change: (ClinicInboxRefresh) -> ClinicInboxRefresh) {
        value = value.copy(refreshes = value.refreshes.map { if (it.id == id) change(it) else it })
    }
}

private fun ClinicInboxSnapshot.frozenCopy(): ClinicInboxSnapshot {
    fun <T> immutable(values: List<T>): List<T> = java.util.Collections.unmodifiableList(ArrayList(values))
    return copy(reviews = immutable(reviews.map { it.copy(metrics = immutable(it.metrics), options = immutable(it.options)) }),
        refreshes = immutable(refreshes.map { it.copy(metrics = immutable(it.metrics)) }))
}
