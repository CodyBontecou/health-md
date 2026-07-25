package com.healthmd.rawexport

import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.*
import java.time.Duration
import java.time.Instant
import kotlinx.serialization.json.*

/** Explicit mapper for connect-client 1.2.0-alpha02. No reflection and no toString fallback. */
object RawHealthConnectMapper {
    fun map(record: Record, wireType: String): RawRecord {
        val temporal = temporal(record)
        return RawRecord(
            wireType = wireType,
            nativeIdentity = "",
            startTime = temporal.start.raw(),
            endTime = temporal.end?.raw(),
            startZoneOffsetSeconds = temporal.startOffset,
            endZoneOffsetSeconds = temporal.endOffset,
            metadata = record.metadata.raw(),
            fields = fields(record),
            hash = "",
        ).withCanonicalIdentityAndHash()
    }

    private data class Temporal(val start: Instant, val end: Instant?, val startOffset: Int?, val endOffset: Int?)

    private fun temporal(record: Record): Temporal = when (record) {
        is OxygenSaturationRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is CervicalMucusRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is BloodPressureRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is MenstruationFlowRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is SexualActivityRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is OvulationTestRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is RestingHeartRateRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is Vo2MaxRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is BodyTemperatureRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is HeightRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is HeartRateVariabilityRmssdRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is BodyFatRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is IntermenstrualBleedingRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is WeightRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is BasalMetabolicRateRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is RespiratoryRateRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is BodyWaterMassRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is BloodGlucoseRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is BasalBodyTemperatureRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is LeanBodyMassRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is BoneMassRecord -> Temporal(record.time, null, record.zoneOffset?.totalSeconds, null)
        is DistanceRecord -> record.interval()
        is SleepSessionRecord -> record.interval()
        is PlannedExerciseSessionRecord -> record.interval()
        is ExerciseSessionRecord -> record.interval()
        is PowerRecord -> record.interval()
        is TotalCaloriesBurnedRecord -> record.interval()
        is HeartRateRecord -> record.interval()
        is WheelchairPushesRecord -> record.interval()
        is ActiveCaloriesBurnedRecord -> record.interval()
        is CyclingPedalingCadenceRecord -> record.interval()
        is NutritionRecord -> record.interval()
        is ElevationGainedRecord -> record.interval()
        is MindfulnessSessionRecord -> record.interval()
        is SkinTemperatureRecord -> record.interval()
        is HydrationRecord -> record.interval()
        is StepsCadenceRecord -> record.interval()
        is StepsRecord -> record.interval()
        is ActivityIntensityRecord -> record.interval()
        is FloorsClimbedRecord -> record.interval()
        is SpeedRecord -> record.interval()
        is MenstruationPeriodRecord -> record.interval()
        else -> error("Catalog contains unsupported temporal shape: ${record::class.qualifiedName}")
    }

    private fun DistanceRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun SleepSessionRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun PlannedExerciseSessionRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun ExerciseSessionRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun PowerRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun TotalCaloriesBurnedRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun HeartRateRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun WheelchairPushesRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun ActiveCaloriesBurnedRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun CyclingPedalingCadenceRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun NutritionRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun ElevationGainedRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun MindfulnessSessionRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun SkinTemperatureRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun HydrationRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun StepsCadenceRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun StepsRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun ActivityIntensityRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun FloorsClimbedRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun SpeedRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)
    private fun MenstruationPeriodRecord.interval() = Temporal(startTime, endTime, startZoneOffset?.totalSeconds, endZoneOffset?.totalSeconds)

    private fun fields(record: Record): JsonObject = buildJsonObject {
        when (record) {
            is StepsRecord -> put("count", record.count)
            is HeartRateRecord -> put("samples", array(record.samples.sortedBy { it.time }) { sample ->
                obj("time" to sample.time.rawJson(), "beatsPerMinute" to JsonPrimitive(sample.beatsPerMinute))
            })
            is SleepSessionRecord -> {
                nullable("title", record.title); nullable("notes", record.notes)
                put("stages", array(record.stages.sortedBy { it.startTime }) { stage ->
                    obj(
                        "startTime" to stage.startTime.rawJson(),
                        "endTime" to stage.endTime.rawJson(),
                        "stage" to enumJson(stage.stage, sleepStageLabel(stage.stage)),
                    )
                })
            }
            is ExerciseSessionRecord -> exercise(record)
            is DistanceRecord -> quantity("distance", record.distance, "Length", "m")
            is ActiveCaloriesBurnedRecord -> quantity("energy", record.energy, "Energy", "kcal")
            is TotalCaloriesBurnedRecord -> quantity("energy", record.energy, "Energy", "kcal")
            is BasalMetabolicRateRecord -> quantity("basalMetabolicRate", record.basalMetabolicRate, "Power", "W")
            is BloodPressureRecord -> {
                quantity("systolic", record.systolic, "Pressure", "mmHg")
                quantity("diastolic", record.diastolic, "Pressure", "mmHg")
                enum("bodyPosition", record.bodyPosition, bodyPositionLabel(record.bodyPosition))
                enum("measurementLocation", record.measurementLocation, pressureLocationLabel(record.measurementLocation))
            }
            is BloodGlucoseRecord -> {
                quantity("level", record.level, "BloodGlucose", "mmol/L")
                enum("specimenSource", record.specimenSource, glucoseSpecimenLabel(record.specimenSource))
                enum("mealType", record.mealType, mealLabel(record.mealType))
                enum("relationToMeal", record.relationToMeal, relationToMealLabel(record.relationToMeal))
            }
            is BodyFatRecord -> quantity("percentage", record.percentage, "Percentage", "%")
            is BodyTemperatureRecord -> {
                quantity("temperature", record.temperature, "Temperature", "degC")
                enum("measurementLocation", record.measurementLocation, temperatureLocationLabel(record.measurementLocation))
            }
            is HeightRecord -> quantity("height", record.height, "Length", "m")
            is WeightRecord -> quantity("weight", record.weight, "Mass", "kg")
            is OxygenSaturationRecord -> quantity("percentage", record.percentage, "Percentage", "%")
            is RespiratoryRateRecord -> scalar("rate", record.rate, "breaths/min")
            is HeartRateVariabilityRmssdRecord -> scalar("heartRateVariabilityMillis", record.heartRateVariabilityMillis, "ms")
            is NutritionRecord -> nutrition(record)
            is HydrationRecord -> quantity("volume", record.volume, "Volume", "L")
            is FloorsClimbedRecord -> put("floors", decimalJson(record.floors))
            is LeanBodyMassRecord -> quantity("mass", record.mass, "Mass", "kg")
            is RestingHeartRateRecord -> put("beatsPerMinute", record.beatsPerMinute)
            is SpeedRecord -> put("samples", array(record.samples.sortedBy { it.time }) { sample ->
                obj("time" to sample.time.rawJson(), "speed" to sample.speed.quantityJson("Velocity", "m/s"))
            })
            is Vo2MaxRecord -> {
                scalar("vo2MillilitersPerMinuteKilogram", record.vo2MillilitersPerMinuteKilogram, "mL/(min*kg)")
                enum("measurementMethod", record.measurementMethod, vo2MethodLabel(record.measurementMethod))
            }
            is ElevationGainedRecord -> quantity("elevation", record.elevation, "Length", "m")
            is WheelchairPushesRecord -> put("count", record.count)
            is PowerRecord -> put("samples", array(record.samples.sortedBy { it.time }) { sample ->
                obj("time" to sample.time.rawJson(), "power" to sample.power.quantityJson("Power", "W"))
            })
            is BasalBodyTemperatureRecord -> {
                quantity("temperature", record.temperature, "Temperature", "degC")
                enum("measurementLocation", record.measurementLocation, temperatureLocationLabel(record.measurementLocation))
            }
            is BodyWaterMassRecord -> quantity("mass", record.mass, "Mass", "kg")
            is BoneMassRecord -> quantity("mass", record.mass, "Mass", "kg")
            is SkinTemperatureRecord -> {
                nullableQuantity("baseline", record.baseline, "Temperature", "degC")
                enum("measurementLocation", record.measurementLocation, skinLocationLabel(record.measurementLocation))
                put("deltas", array(record.deltas.sortedBy { it.time }) { delta ->
                    obj("time" to delta.time.rawJson(), "delta" to delta.delta.quantityJson("TemperatureDelta", "degC"))
                })
            }
            is CervicalMucusRecord -> {
                enum("appearance", record.appearance, cervicalAppearanceLabel(record.appearance))
                enum("sensation", record.sensation, cervicalSensationLabel(record.sensation))
            }
            is IntermenstrualBleedingRecord -> Unit
            is MenstruationFlowRecord -> enum("flow", record.flow, menstrualFlowLabel(record.flow))
            is MenstruationPeriodRecord -> Unit
            is OvulationTestRecord -> enum("result", record.result, ovulationLabel(record.result))
            is SexualActivityRecord -> enum("protectionUsed", record.protectionUsed, protectionLabel(record.protectionUsed))
            is CyclingPedalingCadenceRecord -> put("samples", array(record.samples.sortedBy { it.time }) { sample ->
                obj("time" to sample.time.rawJson(), "revolutionsPerMinute" to decimalJson(sample.revolutionsPerMinute))
            })
            is StepsCadenceRecord -> put("samples", array(record.samples.sortedBy { it.time }) { sample ->
                obj("time" to sample.time.rawJson(), "rate" to decimalJson(sample.rate))
            })
            is MindfulnessSessionRecord -> {
                enum("mindfulnessSessionType", record.mindfulnessSessionType, mindfulnessLabel(record.mindfulnessSessionType))
                nullable("title", record.title); nullable("notes", record.notes)
            }
            is PlannedExerciseSessionRecord -> planned(record)
            is ActivityIntensityRecord -> enum("activityIntensityType", record.activityIntensityType, intensityLabel(record.activityIntensityType))
            else -> error("mapper_missing:${record::class.qualifiedName}")
        }
    }

    private fun JsonObjectBuilder.exercise(record: ExerciseSessionRecord) {
        enum("exerciseType", record.exerciseType, exerciseTypeLabel(record.exerciseType))
        nullable("title", record.title); nullable("notes", record.notes)
        nullable("plannedExerciseSessionId", record.plannedExerciseSessionId)
        put("segments", array(record.segments.sortedBy { it.startTime }) { segment ->
            obj(
                "startTime" to segment.startTime.rawJson(), "endTime" to segment.endTime.rawJson(),
                "segmentType" to enumJson(segment.segmentType, segmentTypeLabel(segment.segmentType)),
                "repetitions" to JsonPrimitive(segment.repetitions),
            )
        })
        put("laps", array(record.laps.sortedBy { it.startTime }) { lap ->
            obj(
                "startTime" to lap.startTime.rawJson(), "endTime" to lap.endTime.rawJson(),
                "length" to (lap.length?.quantityJson("Length", "m") ?: JsonNull),
            )
        })
        put("route", when (val route = record.exerciseRouteResult) {
            is ExerciseRouteResult.ConsentRequired -> obj("state" to JsonPrimitive("consent_required"), "locations" to JsonArray(emptyList()))
            is ExerciseRouteResult.NoData -> obj("state" to JsonPrimitive("no_data"), "locations" to JsonArray(emptyList()))
            is ExerciseRouteResult.Data -> obj(
                "state" to JsonPrimitive("data"),
                "locations" to array(route.exerciseRoute.route.sortedBy { it.time }) { location ->
                    obj(
                        "time" to location.time.rawJson(),
                        "latitude" to decimalJson(location.latitude),
                        "longitude" to decimalJson(location.longitude),
                        "horizontalAccuracy" to (location.horizontalAccuracy?.quantityJson("Length", "m") ?: JsonNull),
                        "verticalAccuracy" to (location.verticalAccuracy?.quantityJson("Length", "m") ?: JsonNull),
                        "altitude" to (location.altitude?.quantityJson("Length", "m") ?: JsonNull),
                    )
                },
            )
            else -> error("Unknown route state in pinned SDK")
        })
    }

    private fun JsonObjectBuilder.planned(record: PlannedExerciseSessionRecord) {
        put("hasExplicitTime", record.hasExplicitTime)
        enum("exerciseType", record.exerciseType, exerciseTypeLabel(record.exerciseType))
        nullable("completedExerciseSessionId", record.completedExerciseSessionId)
        nullable("title", record.title); nullable("notes", record.notes)
        put("blocks", array(record.blocks) { block ->
            obj(
                "repetitions" to JsonPrimitive(block.repetitions),
                "description" to (block.description?.let(::JsonPrimitive) ?: JsonNull),
                "steps" to array(block.steps) { step -> plannedStep(step) },
            )
        })
    }

    private fun plannedStep(step: PlannedExerciseStep): JsonObject = obj(
        "exerciseType" to enumJson(step.exerciseType, segmentTypeLabel(step.exerciseType)),
        "exercisePhase" to enumJson(step.exercisePhase, exercisePhaseLabel(step.exercisePhase)),
        "completionGoal" to completionGoal(step.completionGoal),
        "performanceTargets" to array(step.performanceTargets, ::performanceTarget),
        "description" to (step.description?.let(::JsonPrimitive) ?: JsonNull),
    )

    private fun completionGoal(goal: ExerciseCompletionGoal): JsonObject = when (goal) {
        is ExerciseCompletionGoal.DistanceGoal -> typed("distance", "distance" to goal.distance.quantityJson("Length", "m"))
        is ExerciseCompletionGoal.DistanceAndDurationGoal -> typed("distance_and_duration", "distance" to goal.distance.quantityJson("Length", "m"), "duration" to goal.duration.rawJson())
        is ExerciseCompletionGoal.StepsGoal -> typed("steps", "steps" to JsonPrimitive(goal.steps))
        is ExerciseCompletionGoal.DurationGoal -> typed("duration", "duration" to goal.duration.rawJson())
        is ExerciseCompletionGoal.RepetitionsGoal -> typed("repetitions", "repetitions" to JsonPrimitive(goal.repetitions))
        is ExerciseCompletionGoal.TotalCaloriesBurnedGoal -> typed("total_calories", "totalCalories" to goal.totalCalories.quantityJson("Energy", "kcal"))
        is ExerciseCompletionGoal.ActiveCaloriesBurnedGoal -> typed("active_calories", "activeCalories" to goal.activeCalories.quantityJson("Energy", "kcal"))
        ExerciseCompletionGoal.ManualCompletion -> typed("manual_completion")
        ExerciseCompletionGoal.UnknownGoal -> typed("unknown")
        else -> error("Unknown completion goal in pinned SDK")
    }

    private fun performanceTarget(target: ExercisePerformanceTarget): JsonObject = when (target) {
        is ExercisePerformanceTarget.PowerTarget -> typed("power", "minPower" to target.minPower.quantityJson("Power", "W"), "maxPower" to target.maxPower.quantityJson("Power", "W"))
        is ExercisePerformanceTarget.SpeedTarget -> typed("speed", "minSpeed" to target.minSpeed.quantityJson("Velocity", "m/s"), "maxSpeed" to target.maxSpeed.quantityJson("Velocity", "m/s"))
        is ExercisePerformanceTarget.CadenceTarget -> typed("cadence", "minCadence" to decimalJson(target.minCadence), "maxCadence" to decimalJson(target.maxCadence))
        is ExercisePerformanceTarget.HeartRateTarget -> typed("heart_rate", "minHeartRate" to decimalJson(target.minHeartRate), "maxHeartRate" to decimalJson(target.maxHeartRate))
        is ExercisePerformanceTarget.WeightTarget -> typed("weight", "mass" to target.mass.quantityJson("Mass", "kg"))
        is ExercisePerformanceTarget.RateOfPerceivedExertionTarget -> typed("rpe", "rpe" to JsonPrimitive(target.rpe))
        ExercisePerformanceTarget.AmrapTarget -> typed("amrap")
        ExercisePerformanceTarget.UnknownTarget -> typed("unknown")
        else -> error("Unknown performance target in pinned SDK")
    }

    private fun JsonObjectBuilder.nutrition(r: NutritionRecord) {
        nullable("name", r.name); enum("mealType", r.mealType, mealLabel(r.mealType))
        nullableQuantity("biotin", r.biotin, "Mass", "g"); nullableQuantity("caffeine", r.caffeine, "Mass", "g")
        nullableQuantity("calcium", r.calcium, "Mass", "g"); nullableQuantity("energy", r.energy, "Energy", "kcal")
        nullableQuantity("energyFromFat", r.energyFromFat, "Energy", "kcal"); nullableQuantity("chloride", r.chloride, "Mass", "g")
        nullableQuantity("cholesterol", r.cholesterol, "Mass", "g"); nullableQuantity("chromium", r.chromium, "Mass", "g")
        nullableQuantity("copper", r.copper, "Mass", "g"); nullableQuantity("dietaryFiber", r.dietaryFiber, "Mass", "g")
        nullableQuantity("folate", r.folate, "Mass", "g"); nullableQuantity("folicAcid", r.folicAcid, "Mass", "g")
        nullableQuantity("iodine", r.iodine, "Mass", "g"); nullableQuantity("iron", r.iron, "Mass", "g")
        nullableQuantity("magnesium", r.magnesium, "Mass", "g"); nullableQuantity("manganese", r.manganese, "Mass", "g")
        nullableQuantity("molybdenum", r.molybdenum, "Mass", "g"); nullableQuantity("monounsaturatedFat", r.monounsaturatedFat, "Mass", "g")
        nullableQuantity("niacin", r.niacin, "Mass", "g"); nullableQuantity("pantothenicAcid", r.pantothenicAcid, "Mass", "g")
        nullableQuantity("phosphorus", r.phosphorus, "Mass", "g"); nullableQuantity("polyunsaturatedFat", r.polyunsaturatedFat, "Mass", "g")
        nullableQuantity("potassium", r.potassium, "Mass", "g"); nullableQuantity("protein", r.protein, "Mass", "g")
        nullableQuantity("riboflavin", r.riboflavin, "Mass", "g"); nullableQuantity("saturatedFat", r.saturatedFat, "Mass", "g")
        nullableQuantity("selenium", r.selenium, "Mass", "g"); nullableQuantity("sodium", r.sodium, "Mass", "g")
        nullableQuantity("sugar", r.sugar, "Mass", "g"); nullableQuantity("thiamin", r.thiamin, "Mass", "g")
        nullableQuantity("totalCarbohydrate", r.totalCarbohydrate, "Mass", "g"); nullableQuantity("totalFat", r.totalFat, "Mass", "g")
        nullableQuantity("transFat", r.transFat, "Mass", "g"); nullableQuantity("unsaturatedFat", r.unsaturatedFat, "Mass", "g")
        nullableQuantity("vitaminA", r.vitaminA, "Mass", "g"); nullableQuantity("vitaminB12", r.vitaminB12, "Mass", "g")
        nullableQuantity("vitaminB6", r.vitaminB6, "Mass", "g"); nullableQuantity("vitaminC", r.vitaminC, "Mass", "g")
        nullableQuantity("vitaminD", r.vitaminD, "Mass", "g"); nullableQuantity("vitaminE", r.vitaminE, "Mass", "g")
        nullableQuantity("vitaminK", r.vitaminK, "Mass", "g"); nullableQuantity("zinc", r.zinc, "Mass", "g")
    }

    private fun Metadata.raw() = RawMetadata(
        id = id, clientRecordId = clientRecordId, clientRecordVersion = clientRecordVersion,
        lastModifiedTime = lastModifiedTime.raw(), dataOriginPackageName = dataOrigin.packageName,
        recordingMethod = RawEnumValue(recordingMethod, recordingMethodLabel(recordingMethod)),
        device = device?.let { RawDevice(RawEnumValue(it.type, deviceLabel(it.type)), it.manufacturer, it.model) },
    )

    private fun JsonObjectBuilder.quantity(key: String, value: Any, type: String, unit: String) = put(key, quantityElement(value, type, unit))
    private fun JsonObjectBuilder.nullableQuantity(key: String, value: Any?, type: String, unit: String) = put(key, value?.let { quantityElement(it, type, unit) } ?: JsonNull)
    private fun quantityElement(value: Any, type: String, unit: String): JsonObject {
        val number = when (value) {
            is Length -> value.inMeters; is Energy -> value.inKilocalories; is Power -> value.inWatts
            is Pressure -> value.inMillimetersOfMercury; is BloodGlucose -> value.inMillimolesPerLiter
            is Percentage -> value.value; is Temperature -> value.inCelsius; is TemperatureDelta -> value.inCelsius
            is Mass -> if (unit == "kg") value.inKilograms else value.inGrams
            is Volume -> value.inLiters; is Velocity -> value.inMetersPerSecond
            else -> error("No explicit quantity conversion for ${value::class}")
        }
        return RawJson.codec.encodeToJsonElement(RawQuantity.serializer(), RawQuantity(number, number.toString(), type, unit)).jsonObject
    }
    private fun Any.quantityJson(type: String, unit: String) = quantityElement(this, type, unit)
    private fun JsonObjectBuilder.scalar(key: String, value: Double, unit: String) = put(key, obj("number" to decimalJson(value), "decimal" to JsonPrimitive(value.toString()), "unit" to JsonPrimitive(unit)))
    private fun JsonObjectBuilder.enum(key: String, raw: Int, label: String) = put(key, enumJson(raw, label))
    private fun JsonObjectBuilder.nullable(key: String, value: String?) = put(key, value?.let(::JsonPrimitive) ?: JsonNull)

    private fun Instant.raw() = RawInstant(epochSecond, nano)
    private fun Instant.rawJson() = RawJson.codec.encodeToJsonElement(RawInstant.serializer(), raw())
    private fun Duration.rawJson() = obj("seconds" to JsonPrimitive(seconds), "nano" to JsonPrimitive(nano))
    private fun enumJson(raw: Int, label: String) = RawJson.codec.encodeToJsonElement(RawEnumValue.serializer(), RawEnumValue(raw, label))
    private fun decimalJson(value: Double): JsonPrimitive {
        require(value.isFinite()) { "Raw numeric values must be finite" }
        return JsonPrimitive(value)
    }
    private fun <T> array(values: List<T>, mapper: (T) -> JsonElement) = JsonArray(values.map(mapper))
    private fun obj(vararg fields: Pair<String, JsonElement>) = JsonObject(linkedMapOf(*fields))
    private fun typed(type: String, vararg fields: Pair<String, JsonElement>) = obj("type" to JsonPrimitive(type), *fields)

    private fun unknown(raw: Int) = "unknown_$raw"
    private fun recordingMethodLabel(v: Int) = mapOf(0 to "unknown", 1 to "actively_recorded", 2 to "automatically_recorded", 3 to "manual_entry")[v] ?: unknown(v)
    private fun deviceLabel(v: Int) = mapOf(0 to "unknown",1 to "watch",2 to "phone",3 to "scale",4 to "ring",5 to "head_mounted",6 to "fitness_band",7 to "chest_strap",8 to "smart_display",9 to "consumer_medical_device",10 to "glasses",11 to "hearable",12 to "fitness_machine",13 to "fitness_equipment",14 to "portable_computer",15 to "meter")[v] ?: unknown(v)
    private fun sleepStageLabel(v: Int) = mapOf(0 to "unknown",1 to "awake",2 to "sleeping",3 to "out_of_bed",4 to "light",5 to "deep",6 to "rem",7 to "awake_in_bed")[v] ?: unknown(v)
    private fun menstrualFlowLabel(v: Int) = mapOf(0 to "unknown",1 to "light",2 to "medium",3 to "heavy")[v] ?: unknown(v)
    private fun ovulationLabel(v: Int) = mapOf(0 to "inconclusive",1 to "positive",2 to "high",3 to "negative")[v] ?: unknown(v)
    private fun protectionLabel(v: Int) = mapOf(0 to "unknown",1 to "protected",2 to "unprotected")[v] ?: unknown(v)
    private fun cervicalAppearanceLabel(v: Int) = mapOf(0 to "unknown",1 to "dry",2 to "sticky",3 to "creamy",4 to "watery",5 to "egg_white",6 to "unusual")[v] ?: unknown(v)
    private fun cervicalSensationLabel(v: Int) = mapOf(0 to "unknown",1 to "light",2 to "medium",3 to "heavy")[v] ?: unknown(v)
    private fun mealLabel(v: Int) = mapOf(0 to "unknown",1 to "breakfast",2 to "lunch",3 to "dinner",4 to "snack")[v] ?: unknown(v)
    private fun relationToMealLabel(v: Int) = mapOf(0 to "unknown",1 to "general",2 to "fasting",3 to "before_meal",4 to "after_meal")[v] ?: unknown(v)
    private fun glucoseSpecimenLabel(v: Int) = mapOf(0 to "unknown",1 to "interstitial_fluid",2 to "capillary_blood",3 to "plasma",4 to "serum",5 to "tears",6 to "whole_blood")[v] ?: unknown(v)
    private fun bodyPositionLabel(v: Int) = mapOf(0 to "unknown",1 to "standing_up",2 to "sitting_down",3 to "lying_down",4 to "reclining")[v] ?: unknown(v)
    private fun pressureLocationLabel(v: Int) = mapOf(0 to "unknown",1 to "left_wrist",2 to "right_wrist",3 to "left_upper_arm",4 to "right_upper_arm")[v] ?: unknown(v)
    private fun temperatureLocationLabel(v: Int) = mapOf(0 to "unknown",1 to "armpit",2 to "finger",3 to "forehead",4 to "mouth",5 to "rectum",6 to "temporal_artery",7 to "toe",8 to "ear",9 to "wrist",10 to "vagina")[v] ?: unknown(v)
    private fun skinLocationLabel(v: Int) = mapOf(0 to "unknown",1 to "finger",2 to "toe",3 to "wrist")[v] ?: unknown(v)
    private fun vo2MethodLabel(v: Int) = mapOf(0 to "other",1 to "metabolic_cart",2 to "heart_rate_ratio",3 to "cooper_test",4 to "multistage_fitness_test",5 to "rockport_fitness_test")[v] ?: unknown(v)
    private fun mindfulnessLabel(v: Int) = mapOf(0 to "unknown",1 to "meditation",2 to "breathing",3 to "music",4 to "movement",5 to "unguided")[v] ?: unknown(v)
    private fun intensityLabel(v: Int) = mapOf(0 to "moderate", 1 to "vigorous")[v] ?: unknown(v)
    private fun exercisePhaseLabel(v: Int) = mapOf(0 to "unknown",1 to "warmup",2 to "rest",3 to "active",4 to "cooldown",5 to "recovery")[v] ?: unknown(v)
    private fun exerciseTypeLabel(v: Int) = mapOf(
        0 to "other_workout", 2 to "badminton", 4 to "baseball", 5 to "basketball", 8 to "biking",
        9 to "biking_stationary", 10 to "boot_camp", 11 to "boxing", 13 to "calisthenics", 14 to "cricket",
        16 to "dancing", 25 to "elliptical", 26 to "exercise_class", 27 to "fencing", 28 to "football_american",
        29 to "football_australian", 31 to "frisbee_disc", 32 to "golf", 33 to "guided_breathing",
        34 to "gymnastics", 35 to "handball", 36 to "high_intensity_interval_training", 37 to "hiking",
        38 to "ice_hockey", 39 to "ice_skating", 44 to "martial_arts", 46 to "paddling",
        47 to "paragliding", 48 to "pilates", 50 to "racquetball", 51 to "rock_climbing",
        52 to "roller_hockey", 53 to "rowing", 54 to "rowing_machine", 55 to "rugby", 56 to "running",
        57 to "running_treadmill", 58 to "sailing", 59 to "scuba_diving", 60 to "skating", 61 to "skiing",
        62 to "snowboarding", 63 to "snowshoeing", 64 to "soccer", 65 to "softball", 66 to "squash",
        68 to "stair_climbing", 69 to "stair_climbing_machine", 70 to "strength_training", 71 to "stretching",
        72 to "surfing", 73 to "swimming_open_water", 74 to "swimming_pool", 75 to "table_tennis",
        76 to "tennis", 78 to "volleyball", 79 to "walking", 80 to "water_polo", 81 to "weightlifting",
        82 to "wheelchair", 83 to "yoga",
    )[v] ?: unknown(v)
    private fun segmentTypeLabel(v: Int) = mapOf(
        0 to "unknown", 1 to "arm_curl", 2 to "back_extension", 3 to "ball_slam",
        4 to "barbell_shoulder_press", 5 to "bench_press", 6 to "bench_sit_up", 7 to "biking",
        8 to "biking_stationary", 9 to "burpee", 10 to "crunch", 11 to "deadlift",
        12 to "double_arm_triceps_extension", 13 to "dumbbell_curl_left_arm", 14 to "dumbbell_curl_right_arm",
        15 to "dumbbell_front_raise", 16 to "dumbbell_lateral_raise", 17 to "dumbbell_row",
        18 to "dumbbell_triceps_extension_left_arm", 19 to "dumbbell_triceps_extension_right_arm",
        20 to "dumbbell_triceps_extension_two_arm", 21 to "elliptical", 22 to "forward_twist",
        23 to "front_raise", 24 to "high_intensity_interval_training", 25 to "hip_thrust", 26 to "hula_hoop",
        27 to "jumping_jack", 28 to "jump_rope", 29 to "kettlebell_swing", 30 to "lateral_raise",
        31 to "lat_pull_down", 32 to "leg_curl", 33 to "leg_extension", 34 to "leg_press", 35 to "leg_raise",
        36 to "lunge", 37 to "mountain_climber", 38 to "other_workout", 39 to "pause", 40 to "pilates",
        41 to "plank", 42 to "pull_up", 43 to "punch", 44 to "rest", 45 to "rowing_machine",
        46 to "running", 47 to "running_treadmill", 48 to "shoulder_press", 49 to "single_arm_triceps_extension",
        50 to "sit_up", 51 to "squat", 52 to "stair_climbing", 53 to "stair_climbing_machine",
        54 to "stretching", 55 to "swimming_backstroke", 56 to "swimming_breaststroke",
        57 to "swimming_butterfly", 58 to "swimming_freestyle", 59 to "swimming_mixed",
        60 to "swimming_open_water", 61 to "swimming_other", 62 to "swimming_pool", 63 to "upper_twist",
        64 to "walking", 65 to "weightlifting", 66 to "wheelchair", 67 to "yoga",
    )[v] ?: unknown(v)
}
