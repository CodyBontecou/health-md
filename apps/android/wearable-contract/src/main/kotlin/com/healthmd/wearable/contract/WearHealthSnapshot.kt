package com.healthmd.wearable.contract

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Private phone-to-watch contract. Contains daily aggregates only, never samples or provenance. */
@Serializable
data class WearHealthSnapshot(
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
    val sequence: Long,
    val capturedAtEpochMillis: Long,
    val capturedZoneId: String,
    val days: List<WearHealthDay>,
    val permissionState: WearPermissionState = WearPermissionState.READY,
) {
    fun isStructurallyValid(): Boolean {
        if (schemaVersion != CURRENT_SCHEMA_VERSION || sequence < 0L || capturedAtEpochMillis < 0L) return false
        if (days.size > MAX_DAYS || runCatching { ZoneId.of(capturedZoneId) }.isFailure) return false
        val dates = days.map {
            if (!it.isValid()) return false
            runCatching { LocalDate.parse(it.localDate) }.getOrNull() ?: return false
        }
        return dates == dates.sorted() && dates.distinct().size == dates.size
    }

    fun isValid(nowEpochMillis: Long = Instant.now().toEpochMilli()): Boolean =
        isStructurallyValid() && capturedAtEpochMillis <= nowEpochMillis + MAX_CLOCK_SKEW_MILLIS

    fun freshness(nowEpochMillis: Long): WearFreshness {
        val age = nowEpochMillis - capturedAtEpochMillis
        return when {
            age < -MAX_CLOCK_SKEW_MILLIS -> WearFreshness.VERSION_MISMATCH
            age <= CURRENT_MILLIS -> WearFreshness.CURRENT
            age <= MAX_DISPLAY_MILLIS -> WearFreshness.STALE
            else -> WearFreshness.EXPIRED
        }
    }

    companion object {
        const val CURRENT_SCHEMA_VERSION = 1
        const val MAX_DAYS = 14
        const val MAX_ENCODED_BYTES = 64 * 1024
        const val MAX_CLOCK_SKEW_MILLIS = 5 * 60 * 1000L
        const val CURRENT_MILLIS = 4 * 60 * 60 * 1000L
        const val MAX_DISPLAY_MILLIS = 24 * 60 * 60 * 1000L
    }
}

@Serializable
data class WearHealthDay(
    val localDate: String,
    val steps: Int? = null,
    val moveKilocalories: Double? = null,
    val exerciseMinutes: Double? = null,
    val sleepMinutes: Double? = null,
    val restingHeartRateBpm: Double? = null,
    val averageHeartRateBpm: Double? = null,
    /** Health Connect RMSSD. This is not Apple SDNN. */
    val hrvRmssdMillis: Double? = null,
    /** Percentage in the inclusive range 0–100. */
    val bloodOxygenPercent: Double? = null,
) {
    val hasAnyData: Boolean
        get() = steps != null || moveKilocalories != null || exerciseMinutes != null ||
            sleepMinutes != null || restingHeartRateBpm != null || averageHeartRateBpm != null ||
            hrvRmssdMillis != null || bloodOxygenPercent != null

    fun isValid(): Boolean =
        runCatching { LocalDate.parse(localDate) }.isSuccess &&
            (steps == null || steps in 0..10_000_000) &&
            moveKilocalories.valid(0.0, 100_000.0) &&
            exerciseMinutes.valid(0.0, 10_080.0) &&
            sleepMinutes.valid(0.0, 2_880.0) &&
            restingHeartRateBpm.valid(1.0, 400.0) &&
            averageHeartRateBpm.valid(1.0, 400.0) &&
            hrvRmssdMillis.valid(0.0, 10_000.0) &&
            bloodOxygenPercent.valid(0.0, 100.0)
}

@Serializable
enum class WearPermissionState { READY, PERMISSION_REQUIRED, HEALTH_CONNECT_UNAVAILABLE }

enum class WearFreshness { CURRENT, STALE, EXPIRED, VERSION_MISMATCH }

@Serializable
data class WearSnapshotAck(val sequence: Long, val accepted: Boolean, val reason: WearAckReason? = null)

@Serializable
enum class WearAckReason { APPLIED, DUPLICATE, OUT_OF_ORDER, INVALID, VERSION_MISMATCH, DELETED }

object WearSnapshotAckCodec {
    private val json = Json { encodeDefaults = true; explicitNulls = false; ignoreUnknownKeys = false }
    fun encode(ack: WearSnapshotAck): ByteArray {
        require(ack.sequence >= 0L)
        return json.encodeToString(WearSnapshotAck.serializer(), ack).encodeToByteArray().also { require(it.size <= 1024) }
    }
    fun decode(bytes: ByteArray): WearSnapshotAck? = if (bytes.size !in 1..1024) null else runCatching {
        json.decodeFromString(WearSnapshotAck.serializer(), bytes.decodeToString(throwOnInvalidSequence = true))
    }.getOrNull()?.takeIf { it.sequence >= 0L }
}

/** Bounded control message establishing an ordering barrier for an explicit user deletion. */
@Serializable
data class WearDeleteRequest(val clearedThroughSequence: Long)

object WearDeleteRequestCodec {
    private val json = Json { encodeDefaults = true; explicitNulls = false; ignoreUnknownKeys = false }
    fun encode(request: WearDeleteRequest): ByteArray {
        require(request.clearedThroughSequence >= 0L)
        return json.encodeToString(WearDeleteRequest.serializer(), request).encodeToByteArray().also {
            require(it.size <= MAX_BYTES)
        }
    }
    fun decode(bytes: ByteArray): WearDeleteRequest? = if (bytes.size !in 1..MAX_BYTES) null else runCatching {
        json.decodeFromString(WearDeleteRequest.serializer(), bytes.decodeToString(throwOnInvalidSequence = true))
    }.getOrNull()?.takeIf { it.clearedThroughSequence >= 0L }

    private const val MAX_BYTES = 1024
}

sealed interface WearSnapshotDecodeResult {
    data class Valid(val snapshot: WearHealthSnapshot) : WearSnapshotDecodeResult
    data class Rejected(val reason: WearAckReason) : WearSnapshotDecodeResult
}

object WearHealthSnapshotCodec {
    private val json = Json { encodeDefaults = true; explicitNulls = false; ignoreUnknownKeys = false }

    fun encode(snapshot: WearHealthSnapshot): ByteArray {
        require(snapshot.isValid()) { "Invalid wearable snapshot" }
        return json.encodeToString(WearHealthSnapshot.serializer(), snapshot).encodeToByteArray().also {
            require(it.size <= WearHealthSnapshot.MAX_ENCODED_BYTES) { "Wearable snapshot is too large" }
        }
    }

    fun decodeResult(bytes: ByteArray, nowEpochMillis: Long = Instant.now().toEpochMilli()): WearSnapshotDecodeResult {
        if (bytes.isEmpty() || bytes.size > WearHealthSnapshot.MAX_ENCODED_BYTES) return WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID)
        val source = runCatching { bytes.decodeToString(throwOnInvalidSequence = true) }.getOrElse {
            return WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID)
        }
        val topLevel = runCatching { json.parseToJsonElement(source).jsonObject }.getOrElse {
            return WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID)
        }
        val versionElement = topLevel["schemaVersion"]
            ?: return WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID)
        val version = runCatching { versionElement.jsonPrimitive.content.toInt() }.getOrNull()
            ?: return WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID)
        if (version != WearHealthSnapshot.CURRENT_SCHEMA_VERSION) {
            return WearSnapshotDecodeResult.Rejected(WearAckReason.VERSION_MISMATCH)
        }
        return try {
            val value = json.decodeFromString(WearHealthSnapshot.serializer(), source)
            if (value.isValid(nowEpochMillis)) WearSnapshotDecodeResult.Valid(value) else WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID)
        } catch (_: SerializationException) { WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID) }
        catch (_: IllegalArgumentException) { WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID) }
    }

    fun decode(bytes: ByteArray, nowEpochMillis: Long = Instant.now().toEpochMilli()): WearHealthSnapshot? =
        (decodeResult(bytes, nowEpochMillis) as? WearSnapshotDecodeResult.Valid)?.snapshot

    /** Decode an already accepted local cache without reapplying mutable wall-clock skew policy. */
    fun decodeStored(bytes: ByteArray): WearHealthSnapshot? {
        if (bytes.isEmpty() || bytes.size > WearHealthSnapshot.MAX_ENCODED_BYTES) return null
        val source = runCatching { bytes.decodeToString(throwOnInvalidSequence = true) }.getOrNull() ?: return null
        return runCatching { json.decodeFromString(WearHealthSnapshot.serializer(), source) }
            .getOrNull()?.takeIf(WearHealthSnapshot::isStructurallyValid)
    }
}

object WearDataPaths {
    const val SNAPSHOT = "/healthmd/wear/snapshot/v1"
    const val TOMBSTONE = "/healthmd/wear/tombstone/v1"
    const val REFRESH = "/healthmd/wear/refresh/v1"
    const val ACK = "/healthmd/wear/ack/v1"
    const val DELETE = "/healthmd/wear/delete/v1"
    const val CAPABILITY_PHONE = "healthmd_phone_sync"
    const val CAPABILITY_WATCH = "healthmd_watch_sync"
}

private fun Double?.valid(min: Double, max: Double): Boolean =
    this == null || (isFinite() && this in min..max)
