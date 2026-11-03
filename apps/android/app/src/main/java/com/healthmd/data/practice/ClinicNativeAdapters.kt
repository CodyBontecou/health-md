package com.healthmd.data.practice

import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.practice.ClinicRefreshRequest
import com.healthmd.domain.practice.PracticeFeaturePolicy
import com.healthmd.domain.repository.SettingsRepository
import java.io.File
import java.io.FileOutputStream
import java.net.URI
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

@Serializable
data class ClinicSetupReview(
    val clinicId: String, val clinicName: String, val setupId: String, val subjectId: String, val deviceId: String, val connectionId: String, val revision: String,
    val name: String, val settingsSnapshotJson: String, val endpointUrl: String, val zoneId: String,
    val weekly: Boolean, val hour: Int, val expiresAtMillis: Long,
)
@Serializable
data class ClinicProfileApproval(val review: ClinicSetupReview, val profileId: String, val destinationFingerprint: String)
@Serializable
private data class SetupApplication(val version: Int, val review: ClinicSetupReview, val approval: ClinicProfileApproval? = null)

/** Caller roots this in Context.noBackupFilesDir. Only native-local reviewed settings and metadata are persisted. */
class ClinicSetupStore(private val root: File) {
    private val lock = locks.computeIfAbsent(root.canonicalPath) { Any() }
    companion object { private val locks = java.util.concurrent.ConcurrentHashMap<String, Any>() }
    init { check(root.mkdirs() || root.isDirectory); check(!Files.isSymbolicLink(root.toPath())) }
    private fun file(review: ClinicSetupReview): File {
        val key = listOf(review.subjectId, review.deviceId, review.setupId).joinToString("\u0000")
        val hash = MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }
        return File(root, "$hash.setup")
    }
    internal fun load(review: ClinicSetupReview): ClinicProfileApproval? = synchronized(lock) {
        val path = file(review)
        if (!Files.exists(path.toPath(), java.nio.file.LinkOption.NOFOLLOW_LINKS)) return@synchronized null
        check(!Files.isSymbolicLink(path.toPath()) && path.isFile && path.length() <= 1_048_576) { "invalid_journal" }
        val record = Json.decodeFromString<SetupApplication>(path.readText())
        check(record.version == 1 && record.review == review) { "review_changed" }
        checkNotNull(record.approval) { "interrupted" }
    }
    internal fun reserve(review: ClinicSetupReview) = synchronized(lock) {
        check(!Files.exists(file(review).toPath(), java.nio.file.LinkOption.NOFOLLOW_LINKS)) { "interrupted" }
        save(review, null)
    }
    internal fun save(review: ClinicSetupReview, approval: ClinicProfileApproval?) = synchronized(lock) {
        val destination = file(review)
        check(destination.exists() || (root.listFiles()?.size ?: 100) < 100) { "capacity" }
        val bytes = Json.encodeToString(SetupApplication(version = 1, review = review, approval = approval)).toByteArray()
        check(bytes.size <= 1_048_576) { "capacity" }
        val temporary = File.createTempFile("clinic-", ".pending", root)
        try {
            FileOutputStream(temporary).use { it.write(bytes); it.fd.sync() }
            Files.move(temporary.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            java.nio.channels.FileChannel.open(root.toPath(), java.nio.file.StandardOpenOption.READ).use { it.force(true) }
        } finally { temporary.delete() }
    }
}

/** No transport/parser/presenter is installed: the future authenticated mapper supplies a full native snapshot.
 * Acceptance adds a separate profile and disabled schedule, preserving existing profiles and every snapshot option. */
class ClinicNativeOnboarding(
    private val profiles: ExportProfileRepository, private val schedules: ScheduledProfileEntryStore,
    private val credentials: APIExportCredentialStore, private val store: ClinicSetupStore,
    private val enabled: () -> Boolean = { PracticeFeaturePolicy.current().isEnabled },
) {
    private var pending: Triple<ClinicSetupReview, String, String>? = null
    suspend fun preview(review: ClinicSetupReview, now: Long = System.currentTimeMillis()): String {
        check(listOf(review.clinicId, review.setupId, review.subjectId, review.deviceId, review.connectionId, review.revision).all { it.isNotEmpty() && it.toByteArray().size <= 200 && it.none(Char::isISOControl) })
        check(enabled() && review.expiresAtMillis > now && review.hour in 0..23 && review.name.isNotBlank() && review.clinicName.isNotBlank()) { "unavailable" }
        check(AndroidExportSettingsSnapshotCodec.decodeOrNull(review.settingsSnapshotJson)?.ianaTimeZone == review.zoneId) { "invalid_snapshot" }
        check(boundHTTPS(review.endpointUrl)) { "endpoint_binding_required" }
        val configuration = checkNotNull(credentials.requestConfiguration(review.endpointUrl)) { "endpoint_binding_required" }
        check(!configuration.authorizationHeader.isNullOrBlank()) { "endpoint_binding_required" }
        ZoneId.of(review.zoneId)
        val fingerprint = configuration.destinationFingerprint
        val digest = MessageDigest.getInstance("SHA-256").digest((Json.encodeToString(review) + "\u0000" + fingerprint).toByteArray())
            .joinToString("") { "%02x".format(it) }
        pending = Triple(review, digest, fingerprint); return digest
    }
    suspend fun accept(digest: String, now: Long = System.currentTimeMillis(), authorize: suspend (ClinicSetupReview) -> Unit): ClinicProfileApproval {
        check(enabled()) { "unavailable" }
        val (review, expected, fingerprint) = checkNotNull(pending) { "unavailable" }
        check(digest == expected && review.expiresAtMillis > now) { "review_changed" }; authorize(review)
        check(credentials.destinationFingerprint(review.endpointUrl) == fingerprint) { "destination_changed" }
        store.load(review)?.let { return it }
        store.reserve(review); pending = null
        val profile = profiles.add(name = review.name, settingsSnapshotJson = review.settingsSnapshotJson,
            target = ExportTarget.API_ENDPOINT, apiEndpointUrl = review.endpointUrl)
        check(schedules.upsert(ScheduledProfileEntry(profileId = profile.id, isEnabled = false,
            anchorEpochDay = Instant.ofEpochMilli(now).atZone(ZoneId.of(review.zoneId)).toLocalDate().toEpochDay(),
            hour = review.hour, cadenceUnit = if (review.weekly) ScheduledProfileCadenceUnit.WEEK else ScheduledProfileCadenceUnit.DAY,
            zoneId = review.zoneId))) { "interrupted" }
        return ClinicProfileApproval(review, profile.id, fingerprint).also { store.save(review, it) }
    }
}

class ClinicAndroidExportAdapter(
    private val profiles: ExportProfileRepository, private val snapshots: ScheduledProfileSnapshotFactory,
    private val settings: SettingsRepository, private val credentials: APIExportCredentialStore,
    private val runner: APIEndpointExportRunner,
    private val enabled: () -> Boolean = { PracticeFeaturePolicy.current().isEnabled },
) {
    suspend fun export(request: ClinicRefreshRequest, approval: ClinicProfileApproval, authorityCheck: suspend () -> Unit): String {
        check(enabled()) { "unavailable" }; authorityCheck(); val review = approval.review
        check(request.subjectId == review.subjectId && request.deviceId == review.deviceId && request.connectionId == review.connectionId
            && request.profileId == approval.profileId && request.revision == review.revision) { "unavailable" }
        val zone = ZoneId.of(review.zoneId)
        val start = Instant.ofEpochMilli(request.startMillis).atZone(zone)
        val end = Instant.ofEpochMilli(request.endMillis).atZone(zone)
        check(start.toLocalDate().atStartOfDay(zone).toInstant() == start.toInstant()
            && end.toLocalDate().atStartOfDay(zone).toInstant() == end.toInstant()) { "partial_day_scope_unsupported" }
        val dates = generateSequence(start.toLocalDate()) { it.plusDays(1) }.takeWhile { it < end.toLocalDate() }.take(367).toList()
        check(dates.isNotEmpty() && dates.size <= 366) { "unavailable" }
        val profile = checkNotNull(profiles.profileById(approval.profileId)) { "profile_changed" }
        check(profile.target == ExportTarget.API_ENDPOINT && profile.settingsSnapshotJson == review.settingsSnapshotJson
            && profile.apiEndpointUrl == review.endpointUrl && !profiles.isSharedSetupV2Blocked(profile.id)) { "profile_changed" }
        val restored = checkNotNull(snapshots.applyForActivation(profile, settings.getExportSettings())) { "invalid_snapshot" }
        // The runner resolves its own device calendar. Reject a changed zone rather than widening the approved interval.
        check(ZoneId.systemDefault() == zone) { "timezone_changed" }
        val result = runner.exportDates(dates, restored, expectedDestinationFingerprint = approval.destinationFingerprint,
            authorityCheck = {
                authorityCheck()
                val latest = profiles.profileById(profile.id)
                check(latest == profile && !profiles.isSharedSetupV2Blocked(profile.id)
                    && credentials.destinationFingerprint(review.endpointUrl) == approval.destinationFingerprint
                    && ZoneId.systemDefault() == zone) { "profile_changed" }
            })
        check(!result.wasCancelled && result.successCount == dates.size && result.failedDateDetails.isEmpty()) { "incomplete_export" }
        return "clinic-" + request.requestId
    }
}

private fun boundHTTPS(value: String): Boolean = runCatching {
    val uri = URI(value)
    uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null
}.getOrDefault(false)
