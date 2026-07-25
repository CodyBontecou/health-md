package com.healthmd.data.health

import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Percentage
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.WorkoutRoutePointData
import com.healthmd.domain.model.WorkoutSplitData
import com.healthmd.domain.model.deterministicRecordId
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.time.Duration.Companion.nanoseconds

/** Compatibility-domain mapping kept separate from raw Health Connect fidelity mapping. */
internal object CompatibilityHealthMapper {
    /** Health Connect Percentage.value is expressed on a 0..100 scale; compatibility uses 0..1. */
    fun percentageFraction(value: Percentage): Double = value.value / 100.0

    fun latestBodyFatFraction(records: List<BodyFatRecord>): Double? =
        records.maxByOrNull { it.time }?.percentage?.let(::percentageFraction)

    fun latestWeightKilograms(records: List<WeightRecord>): Double? =
        records.maxByOrNull { it.time }?.weight?.inKilograms

    fun latestHeightMeters(records: List<HeightRecord>): Double? =
        records.maxByOrNull { it.time }?.height?.inMeters

    fun latestRestingHeartRate(records: List<RestingHeartRateRecord>): Double? =
        records.maxByOrNull { it.time }?.beatsPerMinute?.toDouble()

    /** Version zero is meaningful whenever a client record ID establishes client identity. */
    fun clientRecordVersion(metadata: Metadata): Long? = metadata.clientRecordVersion.takeIf {
        metadata.clientRecordId?.isNotBlank() == true || it > 0L
    }

    fun parentIdentity(metadata: Metadata, syntheticKind: String, vararg syntheticParts: Any?): ExactSourceIdentity {
        val nativeId = metadata.id.takeIf { it.isNotBlank() }
        val syntheticId = if (nativeId == null) deterministicRecordId(syntheticKind, *syntheticParts) else null
        return ExactSourceIdentity(
            nativeId = nativeId,
            clientRecordId = metadata.clientRecordId?.takeIf { it.isNotBlank() },
            clientRecordVersion = clientRecordVersion(metadata),
            origin = metadata.dataOrigin.packageName.takeIf { it.isNotBlank() },
            lastModified = metadata.lastModifiedTime.takeIf { it != Instant.EPOCH }
                ?.let { ExactSourceTimestamp.from(it) },
            syntheticId = syntheticId,
            isSynthetic = syntheticId != null,
        )
    }

    fun childIdentity(metadata: Metadata, kind: String, vararg parts: Any?): ExactSourceIdentity =
        ExactSourceIdentity(
            clientRecordId = metadata.clientRecordId?.takeIf { it.isNotBlank() },
            clientRecordVersion = clientRecordVersion(metadata),
            origin = metadata.dataOrigin.packageName.takeIf { it.isNotBlank() },
            lastModified = metadata.lastModifiedTime.takeIf { it != Instant.EPOCH }
                ?.let { ExactSourceTimestamp.from(it) },
            syntheticId = deterministicRecordId(kind, *parts),
            isSynthetic = true,
        )

    /**
     * Derives complete kilometre splits. Sparse route segments may cross several boundaries, so
     * each boundary instant is interpolated independently instead of being assigned the endpoint.
     */
    fun deriveDistanceSplits(
        route: List<WorkoutRoutePointData>,
        heartSamples: List<TimestampedSample>,
        splitDistanceMeters: Double,
    ): List<WorkoutSplitData> {
        if (route.size < 2 || splitDistanceMeters <= 0.0) return emptyList()
        val splits = mutableListOf<WorkoutSplitData>()
        var cumulativeMeters = 0.0
        var nextBoundaryMeters = splitDistanceMeters
        var splitStartTime = route.first().time
        var splitStartExact = route.first().exactTime
        var splitIndex = 1

        for (index in 1 until route.size) {
            val previous = route[index - 1]
            val current = route[index]
            val segmentMeters = previous.distanceMetersTo(current)
            if (!segmentMeters.isFinite() || segmentMeters <= 0.0) continue
            val segmentEndMeters = cumulativeMeters + segmentMeters

            while (nextBoundaryMeters <= segmentEndMeters + 1e-7) {
                val fraction = ((nextBoundaryMeters - cumulativeMeters) / segmentMeters).coerceIn(0.0, 1.0)
                val splitEndTime = interpolateLocal(previous.time, current.time, fraction) ?: break
                val splitEndExact = interpolateExact(previous.exactTime, current.exactTime, fraction)
                val duration = Duration.between(splitStartTime, splitEndTime)
                if (!duration.isNegative && !duration.isZero) {
                    splits += WorkoutSplitData(
                        index = splitIndex,
                        startTime = splitStartTime,
                        endTime = splitEndTime,
                        duration = duration.toNanos().nanoseconds,
                        distance = splitDistanceMeters,
                        averageHeartRate = heartSamples.averageBetween(splitStartTime, splitEndTime),
                        exactStartTime = splitStartExact,
                        exactEndTime = splitEndExact,
                        identity = ExactSourceIdentity(
                            syntheticId = deterministicRecordId(
                                "workout_split",
                                route.first().identity?.syntheticId,
                                splitIndex,
                                splitEndExact?.epochSecond,
                                splitEndExact?.nano,
                            ),
                            isSynthetic = true,
                        ),
                    )
                    splitIndex += 1
                }
                splitStartTime = splitEndTime
                // A missing/interpolation-inexact boundary must remain missing for both adjacent splits.
                splitStartExact = splitEndExact
                nextBoundaryMeters += splitDistanceMeters
            }
            cumulativeMeters = segmentEndMeters
        }
        return splits
    }

    private fun interpolateLocal(start: LocalDateTime, end: LocalDateTime, fraction: Double): LocalDateTime? =
        try {
            val nanos = Duration.between(start, end).toNanos()
            if (nanos < 0L || !fraction.isFinite()) null else start.plusNanos((nanos * fraction).roundToLong())
        } catch (_: ArithmeticException) {
            null
        }

    private fun interpolateExact(
        start: ExactSourceTimestamp?,
        end: ExactSourceTimestamp?,
        fraction: Double,
    ): ExactSourceTimestamp? {
        if (start == null || end == null || start.offset != end.offset || !fraction.isFinite()) return null
        return try {
            val nanos = Duration.between(start.instant(), end.instant()).toNanos()
            if (nanos < 0L) null else {
                val instant = start.instant().plusNanos((nanos * fraction).roundToLong())
                ExactSourceTimestamp(instant.epochSecond, instant.nano, start.offset)
            }
        } catch (_: ArithmeticException) {
            null
        }
    }

    private fun List<TimestampedSample>.averageBetween(start: LocalDateTime, end: LocalDateTime): Double? =
        filter { !it.time.isBefore(start) && !it.time.isAfter(end) }
            .map { it.value }
            .takeIf { it.isNotEmpty() }
            ?.average()

    private fun WorkoutRoutePointData.distanceMetersTo(other: WorkoutRoutePointData): Double {
        val earthRadiusMeters = 6_371_000.0
        val lat1 = Math.toRadians(latitude)
        val lat2 = Math.toRadians(other.latitude)
        val dLat = Math.toRadians(other.latitude - latitude)
        val dLon = Math.toRadians(other.longitude - longitude)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
