package com.healthmd.data.clinicianreport

import com.healthmd.domain.clinicianreport.*
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.HealthRepository
import kotlinx.coroutines.CancellationException
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import javax.inject.Inject

fun interface ClinicianReportDataSource {
    suspend fun load(configuration: ReportConfiguration, zoneId: ZoneId): ClinicianReportInput
}

fun interface ClinicianReportDateProvider {
    fun today(zoneId: ZoneId): LocalDate
}

class SystemClinicianReportDateProvider @Inject constructor() : ClinicianReportDateProvider {
    override fun today(zoneId: ZoneId): LocalDate = LocalDate.now(zoneId)
}

class DefaultClinicianReportDataSource @Inject constructor(
    private val healthRepository: HealthRepository,
    private val sourceLabelResolver: ClinicianReportSourceLabelResolver,
    private val dateProvider: ClinicianReportDateProvider,
) : ClinicianReportDataSource {
    override suspend fun load(configuration: ReportConfiguration, zoneId: ZoneId): ClinicianReportInput {
        // The operation's pinned zone is the only authority for "today" after capture begins.
        val range = ReportDateRange.normalized(
            configuration.dateRange.startDate,
            configuration.dateRange.endDate,
            today = dateProvider.today(zoneId),
        )
        val normalized = configuration.copy(dateRange = range)
        val selected = normalized.selectedMetrics
        val dataTypes = DataTypeSelection(
            sleep = ReportMetric.SLEEP_DURATION in selected,
            activity = ReportMetric.STEPS in selected,
            heart = ReportMetric.HEART_RATE in selected || ReportMetric.RESTING_HEART_RATE in selected,
            vitals = selected.any { it in VITAL_METRICS },
            body = ReportMetric.WEIGHT in selected,
            nutrition = false,
            mobility = false,
            reproductiveHealth = false,
            mindfulness = false,
            workouts = ReportMetric.WORKOUTS in selected,
            plannedWorkouts = false,
            medicalResources = false,
        )
        return try {
            val records = healthRepository.fetchHealthDataRange(
                dates = range.dates(),
                dataTypes = dataTypes,
                includeGranularData = true,
                zoneId = zoneId,
                pinnedCalendarDays = true,
            )
            adapt(normalized, zoneId, records)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            ClinicianReportInput(
                configuration = normalized,
                zoneId = zoneId,
                generatedAt = Instant.now(),
                warnings = listOf(ClinicianReportWarning.ReadFailure),
            )
        }
    }

    internal fun adapt(configuration: ReportConfiguration, zoneId: ZoneId, records: List<HealthData>): ClinicianReportInput {
        val scalars = mutableListOf<ScalarReportObservation>()
        val pressures = mutableListOf<BloodPressureReportObservation>()
        val daily = mutableListOf<DailyReportValue>()
        val sleep = mutableListOf<SleepReportObservation>()
        val workouts = mutableListOf<WorkoutReportObservation>()
        val warnings = mutableListOf<ClinicianReportWarning>()

        records.sortedBy { it.date }.forEach { data ->
            data.compatibilityProvenance?.providerFailures?.takeIf { it.isNotEmpty() }?.let {
                warnings += ClinicianReportWarning.SourceFailure(data.date)
            }
            if (ReportMetric.BLOOD_PRESSURE in configuration.selectedMetrics) {
                data.vitals.bloodPressureSamples.forEach { sample ->
                    pressures += BloodPressureReportObservation(
                        timestamp = instant(sample.exactTime, sample.time, zoneId),
                        systolic = sample.systolic,
                        diastolic = sample.diastolic,
                        stableId = stableId("blood_pressure", sample.identity),
                        source = source(sample.source, sample.identity, sample.metadata),
                    )
                }
            }
            if (ReportMetric.HEART_RATE in configuration.selectedMetrics) addScalar(data, ReportMetric.HEART_RATE, data.heart.samples, data.heart.averageHeartRate, zoneId, scalars, daily)
            if (ReportMetric.BLOOD_GLUCOSE in configuration.selectedMetrics) addScalar(data, ReportMetric.BLOOD_GLUCOSE, data.vitals.bloodGlucoseSamples, data.vitals.bloodGlucoseAvg, zoneId, scalars, daily)
            if (ReportMetric.OXYGEN_SATURATION in configuration.selectedMetrics) addScalar(data, ReportMetric.OXYGEN_SATURATION, data.vitals.bloodOxygenSamples, data.vitals.bloodOxygenAvg, zoneId, scalars, daily)
            if (ReportMetric.RESPIRATORY_RATE in configuration.selectedMetrics) addScalar(data, ReportMetric.RESPIRATORY_RATE, data.vitals.respiratoryRateSamples, data.vitals.respiratoryRateAvg, zoneId, scalars, daily)
            if (ReportMetric.BODY_TEMPERATURE in configuration.selectedMetrics) addScalar(data, ReportMetric.BODY_TEMPERATURE, data.vitals.bodyTemperatureSamples, data.vitals.bodyTemperatureAvg, zoneId, scalars, daily)

            if (ReportMetric.RESTING_HEART_RATE in configuration.selectedMetrics) {
                data.heart.restingHeartRate?.let { daily += DailyReportValue(ReportMetric.RESTING_HEART_RATE, data.date, it) }
            }
            if (ReportMetric.WEIGHT in configuration.selectedMetrics) {
                data.body.weight?.let { daily += DailyReportValue(ReportMetric.WEIGHT, data.date, it) }
            }
            if (ReportMetric.STEPS in configuration.selectedMetrics) {
                data.activity.steps?.let { daily += DailyReportValue(ReportMetric.STEPS, data.date, it.toDouble()) }
            }
            if (ReportMetric.SLEEP_DURATION in configuration.selectedMetrics && data.sleep.totalDuration.isPositive()) {
                val sessionSources = data.sleep.sessions.mapNotNull { session ->
                    sourceLabelResolver.resolve(session.source, session.metadata)
                }.distinctBy { it.label to it.isManualEntry }
                sleep += SleepReportObservation(
                    date = data.date,
                    durationMinutes = data.sleep.totalDuration.inWholeMilliseconds / 60_000.0,
                    source = sessionSources.singleOrNull(),
                )
            }
            if (ReportMetric.WORKOUTS in configuration.selectedMetrics) {
                data.workouts.forEach { workout ->
                    workouts += WorkoutReportObservation(
                        timestamp = workout.exactStartTime?.instant() ?: workout.startTime.atZone(zoneId).toInstant(),
                        type = workout.workoutType,
                        durationMinutes = workout.duration.inWholeMilliseconds / 60_000.0,
                        stableId = stableId("workout", workout.identity),
                        source = source(null, workout.identity, workout.metadata),
                    )
                }
            }
        }
        return ClinicianReportInput(
            configuration = configuration,
            zoneId = zoneId,
            generatedAt = Instant.now(),
            scalarObservations = scalars,
            bloodPressureObservations = pressures,
            dailyValues = daily,
            sleepObservations = sleep,
            workoutObservations = workouts,
            warnings = warnings.distinct(),
        )
    }

    private fun addScalar(
        data: HealthData,
        metric: ReportMetric,
        samples: List<TimestampedSample>,
        fallback: Double?,
        zoneId: ZoneId,
        output: MutableList<ScalarReportObservation>,
        dailyOutput: MutableList<DailyReportValue>,
    ) {
        if (samples.isNotEmpty()) {
            samples.forEach { sample -> output += ScalarReportObservation(
                metric = metric,
                timestamp = instant(sample.exactTime, sample.time, zoneId),
                value = sample.value,
                stableId = stableId(metric.name.lowercase(), sample.identity),
                source = source(sample.source, sample.identity, sample.metadata),
            ) }
        } else fallback?.let { value ->
            // Daily provider aggregates have no exact observation time or record provenance.
            dailyOutput += DailyReportValue(metric, data.date, value)
        }
    }

    private fun instant(exact: ExactSourceTimestamp?, local: LocalDateTime, zoneId: ZoneId): Instant = exact?.instant() ?: local.atZone(zoneId).toInstant()

    private fun source(origin: String?, identity: ExactSourceIdentity?, metadata: Map<String, String>): ReportSource? =
        sourceLabelResolver.resolve(origin ?: identity?.origin, metadata)

    private fun stableId(metric: String, identity: ExactSourceIdentity?): String? {
        identity ?: return null
        val sourceIdentity = when {
            !identity.nativeId.isNullOrBlank() -> "native:${identity.nativeId}"
            !identity.clientRecordId.isNullOrBlank() -> "client:${identity.clientRecordId}:${identity.clientRecordVersion ?: ""}"
            !identity.syntheticId.isNullOrBlank() -> "synthetic:${identity.syntheticId}"
            else -> return null
        }
        return "$metric:${identity.origin.orEmpty()}:$sourceIdentity"
    }

    companion object {
        private val VITAL_METRICS = setOf(
            ReportMetric.BLOOD_PRESSURE, ReportMetric.BLOOD_GLUCOSE, ReportMetric.OXYGEN_SATURATION,
            ReportMetric.RESPIRATORY_RATE, ReportMetric.BODY_TEMPERATURE,
        )
    }
}
