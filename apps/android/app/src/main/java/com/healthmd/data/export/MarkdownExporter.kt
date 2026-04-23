package com.healthmd.data.export

import com.healthmd.domain.model.*
import kotlin.time.Duration

class MarkdownExporter {

    fun export(
        data: HealthData,
        includeMetadata: Boolean = true,
        groupByCategory: Boolean = true,
        customization: FormatCustomization = FormatCustomization(),
        includeGranularData: Boolean = false,
    ): String {
        val dateString = customization.dateFormat.format(data.date)
        val converter = customization.unitConverter
        val template = customization.markdownTemplate
        val bullet = template.bulletStyle.symbol
        val headerPrefix = "#".repeat(template.sectionHeaderLevel)

        val emojis = if (template.useEmoji) SectionEmojis.WITH_EMOJI else SectionEmojis.NONE

        val markdown = buildString {
            if (includeMetadata) {
                append(buildFrontmatter(data, dateString, customization))
            }

            if (template.style == MarkdownTemplateStyle.CUSTOM) {
                append(renderCustomTemplate(data, dateString, customization, converter, bullet, headerPrefix, emojis, includeGranularData))
            } else {
                append("# Health Data \u2014 $dateString\n")
                append(renderAllSections(data, converter, bullet, headerPrefix, emojis, customization, includeGranularData))
            }
        }

        return markdown
    }

    private fun buildFrontmatter(
        data: HealthData,
        dateString: String,
        customization: FormatCustomization,
    ): String = buildString {
        val fmConfig = customization.frontmatterConfig
        val converter = customization.unitConverter

        append("---\n")
        if (fmConfig.includeDate) {
            append("${fmConfig.customDateKey}: $dateString\n")
        }
        if (fmConfig.includeType) {
            append("${fmConfig.customTypeKey}: ${fmConfig.customTypeValue}\n")
        }

        // Custom static fields
        for ((key, value) in fmConfig.customFields.toSortedMap()) {
            append("$key: $value\n")
        }

        // Placeholder fields
        for (key in fmConfig.placeholderFields.sorted()) {
            append("$key: \n")
        }

        // Health data frontmatter values — driven by HealthDataFields (single source of truth)
        for (field in HealthDataFields.extract(data, converter, customization.timeFormat)) {
            if (field.value == null) continue
            val outputKey = fmConfig.outputKey(field.key) ?: continue
            append("$outputKey: ${field.value}\n")
        }

        append("---\n\n")
    }

    private fun renderAllSections(
        data: HealthData,
        converter: UnitConverter,
        bullet: String,
        headerPrefix: String,
        emojis: SectionEmojis,
        customization: FormatCustomization,
        includeGranularData: Boolean = false,
    ): String = buildString {
        if (data.sleep.hasData) {
            append("\n$headerPrefix ${emojis.sleep}Sleep\n\n")
            append(sleepMetrics(data.sleep, bullet))
            if (includeGranularData && data.sleep.stages.isNotEmpty()) {
                append("\n| Start | End | Stage |\n|-------|-----|-------|\n")
                for (stage in data.sleep.stages) {
                    append("| ${customization.timeFormat.format(stage.startTime)} | ${customization.timeFormat.format(stage.endTime)} | ${stage.stage} |\n")
                }
            }
        }
        if (data.activity.hasData) {
            append("\n$headerPrefix ${emojis.activity}Activity\n\n")
            append(activityMetrics(data.activity, bullet, converter))
            if (includeGranularData && data.activity.stepSamples.isNotEmpty()) {
                append("\n| Time | Steps |\n|------|-------|\n")
                for (sample in data.activity.stepSamples) {
                    append("| ${customization.timeFormat.format(sample.time)} | ${sample.value.toInt()} |\n")
                }
            }
        }
        if (data.heart.hasData) {
            append("\n$headerPrefix ${emojis.heart}Heart\n\n")
            append(heartMetrics(data.heart, bullet))
            if (includeGranularData && data.heart.samples.isNotEmpty()) {
                append("\n| Time | BPM |\n|------|-----|\n")
                for (sample in data.heart.samples) {
                    append("| ${customization.timeFormat.format(sample.time)} | ${sample.value.toInt()} |\n")
                }
            }
            if (includeGranularData && data.heart.hrvSamples.isNotEmpty()) {
                append("\n| Time | HRV (ms) |\n|------|----------|\n")
                for (sample in data.heart.hrvSamples) {
                    append("| ${customization.timeFormat.format(sample.time)} | ${String.format("%.1f", sample.value)} |\n")
                }
            }
        }
        if (data.vitals.hasData) {
            append("\n$headerPrefix ${emojis.vitals}Vitals\n\n")
            append(vitalsMetrics(data.vitals, bullet, converter))
            if (includeGranularData) {
                appendVitalsSamples(data.vitals, customization, converter)
            }
        }
        if (data.body.hasData) {
            append("\n$headerPrefix ${emojis.body}Body\n\n")
            append(bodyMetrics(data.body, bullet, converter))
        }
        if (data.nutrition.hasData) {
            append("\n$headerPrefix ${emojis.nutrition}Nutrition\n\n")
            append(nutritionMetrics(data.nutrition, bullet, converter))
        }
        if (data.mobility.hasData) {
            append("\n$headerPrefix ${emojis.mobility}Mobility\n\n")
            append(mobilityMetrics(data.mobility, bullet, converter))
        }
        if (data.reproductiveHealth.hasData) {
            append("\n$headerPrefix ${emojis.reproductiveHealth}Reproductive Health\n\n")
            append(reproductiveHealthMetrics(data.reproductiveHealth, bullet))
        }
        if (data.mindfulness.hasData) {
            append("\n$headerPrefix ${emojis.mindfulness}Mindfulness\n\n")
            append(mindfulnessMetrics(data.mindfulness, bullet))
        }
        if (data.workouts.isNotEmpty()) {
            append("\n$headerPrefix ${emojis.workouts}Workouts\n\n")
            append(workoutsMarkdown(data.workouts, bullet, customization))
        }
    }

    private fun StringBuilder.appendVitalsSamples(
        vitals: VitalsData,
        customization: FormatCustomization,
        converter: UnitConverter,
    ) {
        if (vitals.bloodOxygenSamples.isNotEmpty()) {
            append("\n| Time | SpO2 (%) |\n|------|----------|\n")
            for (sample in vitals.bloodOxygenSamples) {
                append("| ${customization.timeFormat.format(sample.time)} | ${sample.value} |\n")
            }
        }
        if (vitals.bloodPressureSamples.isNotEmpty()) {
            append("\n| Time | Systolic | Diastolic |\n|------|----------|-----------|\n")
            for (sample in vitals.bloodPressureSamples) {
                append("| ${customization.timeFormat.format(sample.time)} | ${sample.systolic.toInt()} | ${sample.diastolic.toInt()} |\n")
            }
        }
        if (vitals.bloodGlucoseSamples.isNotEmpty()) {
            append("\n| Time | Glucose (mg/dL) |\n|------|-----------------|\n")
            for (sample in vitals.bloodGlucoseSamples) {
                append("| ${customization.timeFormat.format(sample.time)} | ${String.format("%.1f", sample.value)} |\n")
            }
        }
        if (vitals.respiratoryRateSamples.isNotEmpty()) {
            append("\n| Time | Respiratory Rate |\n|------|------------------|\n")
            for (sample in vitals.respiratoryRateSamples) {
                append("| ${customization.timeFormat.format(sample.time)} | ${String.format("%.1f", sample.value)} |\n")
            }
        }
        if (vitals.bodyTemperatureSamples.isNotEmpty()) {
            append("\n| Time | Temperature |\n|------|-------------|\n")
            for (sample in vitals.bodyTemperatureSamples) {
                append("| ${customization.timeFormat.format(sample.time)} | ${converter.formatTemperature(sample.value)} |\n")
            }
        }
    }

    private fun renderCustomTemplate(
        data: HealthData,
        dateString: String,
        customization: FormatCustomization,
        converter: UnitConverter,
        bullet: String,
        headerPrefix: String,
        emojis: SectionEmojis,
        includeGranularData: Boolean = false,
    ): String {
        var rendered = customization.markdownTemplate.customTemplate

        // Conditional blocks
        val sections = listOf(
            "sleep" to data.sleep.hasData,
            "activity" to data.activity.hasData,
            "heart" to data.heart.hasData,
            "vitals" to data.vitals.hasData,
            "body" to data.body.hasData,
            "nutrition" to data.nutrition.hasData,
            "mobility" to data.mobility.hasData,
            "reproductive_health" to data.reproductiveHealth.hasData,
            "mindfulness" to data.mindfulness.hasData,
            "workouts" to data.workouts.isNotEmpty(),
        )
        for ((name, include) in sections) {
            rendered = applyConditionalSection(rendered, name, include)
        }

        // Replacements
        val replacements = mapOf(
            "date" to dateString,
            "sleep_metrics" to sleepMetrics(data.sleep, bullet),
            "activity_metrics" to activityMetrics(data.activity, bullet, converter),
            "heart_metrics" to heartMetrics(data.heart, bullet),
            "vitals_metrics" to vitalsMetrics(data.vitals, bullet, converter),
            "body_metrics" to bodyMetrics(data.body, bullet, converter),
            "nutrition_metrics" to nutritionMetrics(data.nutrition, bullet, converter),
            "mobility_metrics" to mobilityMetrics(data.mobility, bullet, converter),
            "reproductive_health_metrics" to reproductiveHealthMetrics(data.reproductiveHealth, bullet),
            "mindfulness_metrics" to mindfulnessMetrics(data.mindfulness, bullet),
            "workout_list" to workoutsMarkdown(data.workouts, bullet, customization),
            "metrics" to renderAllSections(data, converter, bullet, headerPrefix, emojis, customization, includeGranularData),
        )
        for ((key, value) in replacements) {
            rendered = rendered.replace("{{$key}}", value)
        }
        return rendered
    }

    private fun applyConditionalSection(template: String, section: String, include: Boolean): String {
        val pattern = Regex("\\{\\{#$section}}(.*?)\\{\\{/$section}}", RegexOption.DOT_MATCHES_ALL)
        return if (include) {
            pattern.replace(template) { it.groupValues[1] }
        } else {
            pattern.replace(template, "")
        }
    }

    // MARK: - Section renderers

    private fun sleepMetrics(sleep: SleepData, bullet: String): String = buildString {
        if (sleep.totalDuration > Duration.ZERO) append("$bullet **Total:** ${ExportHelpers.formatDuration(sleep.totalDuration)}\n")
        if (sleep.inBedTime > Duration.ZERO) append("$bullet **In Bed:** ${ExportHelpers.formatDuration(sleep.inBedTime)}\n")
        if (sleep.deepSleep > Duration.ZERO) append("$bullet **Deep:** ${ExportHelpers.formatDuration(sleep.deepSleep)}\n")
        if (sleep.remSleep > Duration.ZERO) append("$bullet **REM:** ${ExportHelpers.formatDuration(sleep.remSleep)}\n")
        if (sleep.lightSleep > Duration.ZERO) append("$bullet **Light:** ${ExportHelpers.formatDuration(sleep.lightSleep)}\n")
        if (sleep.awakeTime > Duration.ZERO) append("$bullet **Awake:** ${ExportHelpers.formatDuration(sleep.awakeTime)}\n")
    }

    private fun activityMetrics(activity: ActivityData, bullet: String, converter: UnitConverter): String = buildString {
        activity.steps?.let { append("$bullet **Steps:** ${ExportHelpers.formatNumber(it)}\n") }
        activity.activeCalories?.let { append("$bullet **Active Calories:** ${ExportHelpers.formatNumber(it.toInt())} kcal\n") }
        activity.totalCalories?.let { append("$bullet **Total Calories:** ${ExportHelpers.formatNumber(it.toInt())} kcal\n") }
        activity.basalEnergyBurned?.let { append("$bullet **Basal Energy:** ${ExportHelpers.formatNumber(it.toInt())} kcal\n") }
        activity.exerciseMinutes?.let { append("$bullet **Exercise:** ${it.toInt()} min\n") }
        activity.flightsClimbed?.let { append("$bullet **Floors Climbed:** $it\n") }
        activity.walkingRunningDistance?.let { append("$bullet **Walking/Running Distance:** ${converter.formatDistance(it)}\n") }
        activity.cyclingDistance?.let { append("$bullet **Cycling Distance:** ${converter.formatDistance(it)}\n") }
        activity.elevationGained?.let { append("$bullet **Elevation Gained:** ${String.format("%.1f", it)} m\n") }
        activity.wheelchairPushes?.let { append("$bullet **Wheelchair Pushes:** $it\n") }
    }

    private fun heartMetrics(heart: HeartData, bullet: String): String = buildString {
        heart.restingHeartRate?.let { append("$bullet **Resting HR:** ${it.toInt()} bpm\n") }
        heart.averageHeartRate?.let { append("$bullet **Average HR:** ${it.toInt()} bpm\n") }
        heart.heartRateMin?.let { append("$bullet **Min HR:** ${it.toInt()} bpm\n") }
        heart.heartRateMax?.let { append("$bullet **Max HR:** ${it.toInt()} bpm\n") }
        heart.hrv?.let { append("$bullet **HRV (RMSSD):** ${String.format("%.1f", it)} ms\n") }
    }

    private fun vitalsMetrics(vitals: VitalsData, bullet: String, converter: UnitConverter): String = buildString {
        vitals.respiratoryRateAvg?.let { avg ->
            var line = "$bullet **Respiratory Rate:** ${String.format("%.1f", avg)} breaths/min"
            if (vitals.respiratoryRateMin != null && vitals.respiratoryRateMax != null && vitals.respiratoryRateMin != vitals.respiratoryRateMax) {
                line += " (range: ${String.format("%.1f", vitals.respiratoryRateMin)}\u2013${String.format("%.1f", vitals.respiratoryRateMax)})"
            }
            append("$line\n")
        }
        vitals.bloodOxygenAvg?.let { avg ->
            var line = "$bullet **SpO2:** ${(avg * 100).toInt()}%"
            if (vitals.bloodOxygenMin != null && vitals.bloodOxygenMax != null && vitals.bloodOxygenMin != vitals.bloodOxygenMax) {
                line += " (range: ${(vitals.bloodOxygenMin * 100).toInt()}%\u2013${(vitals.bloodOxygenMax * 100).toInt()}%)"
            }
            append("$line\n")
        }
        vitals.bodyTemperatureAvg?.let { avg ->
            var line = "$bullet **Body Temperature:** ${converter.formatTemperature(avg)}"
            if (vitals.bodyTemperatureMin != null && vitals.bodyTemperatureMax != null && vitals.bodyTemperatureMin != vitals.bodyTemperatureMax) {
                line += " (range: ${converter.formatTemperature(vitals.bodyTemperatureMin)}\u2013${converter.formatTemperature(vitals.bodyTemperatureMax)})"
            }
            append("$line\n")
        }
        if (vitals.bloodPressureSystolicAvg != null && vitals.bloodPressureDiastolicAvg != null) {
            var line = "$bullet **Blood Pressure:** ${vitals.bloodPressureSystolicAvg.toInt()}/${vitals.bloodPressureDiastolicAvg.toInt()} mmHg"
            if (vitals.bloodPressureSystolicMin != null && vitals.bloodPressureSystolicMax != null &&
                vitals.bloodPressureDiastolicMin != null && vitals.bloodPressureDiastolicMax != null) {
                line += " (range: ${vitals.bloodPressureSystolicMin.toInt()}/${vitals.bloodPressureDiastolicMin.toInt()}\u2013${vitals.bloodPressureSystolicMax.toInt()}/${vitals.bloodPressureDiastolicMax.toInt()})"
            }
            append("$line\n")
        }
        vitals.bloodGlucoseAvg?.let { avg ->
            var line = "$bullet **Blood Glucose:** ${String.format("%.1f", avg)} mg/dL"
            if (vitals.bloodGlucoseMin != null && vitals.bloodGlucoseMax != null && vitals.bloodGlucoseMin != vitals.bloodGlucoseMax) {
                line += " (range: ${String.format("%.1f", vitals.bloodGlucoseMin)}\u2013${String.format("%.1f", vitals.bloodGlucoseMax)})"
            }
            append("$line\n")
        }
        vitals.basalBodyTemperature?.let { append("$bullet **Basal Body Temperature:** ${converter.formatTemperature(it)}\n") }
        vitals.skinTemperatureDelta?.let { append("$bullet **Skin Temperature Delta:** ${String.format("%.2f", it)} \u00B0C\n") }
    }

    private fun bodyMetrics(body: BodyData, bullet: String, converter: UnitConverter): String = buildString {
        body.weight?.let { append("$bullet **Weight:** ${converter.formatWeight(it)}\n") }
        body.height?.let { append("$bullet **Height:** ${converter.formatHeight(it)}\n") }
        body.bmi?.let { append("$bullet **BMI:** ${String.format("%.1f", it)}\n") }
        body.bodyFatPercentage?.let { append("$bullet **Body Fat:** ${String.format("%.1f", it * 100)}%\n") }
        body.leanBodyMass?.let { append("$bullet **Lean Body Mass:** ${converter.formatWeight(it)}\n") }
        body.bodyWaterMass?.let { append("$bullet **Body Water Mass:** ${converter.formatWeight(it)}\n") }
        body.boneMass?.let { append("$bullet **Bone Mass:** ${converter.formatWeight(it)}\n") }
    }

    private fun nutritionMetrics(nutrition: NutritionData, bullet: String, converter: UnitConverter): String = buildString {
        nutrition.dietaryEnergy?.let { append("$bullet **Calories:** ${ExportHelpers.formatNumber(it.toInt())} kcal\n") }
        nutrition.protein?.let { append("$bullet **Protein:** ${String.format("%.1f", it)} g\n") }
        nutrition.carbohydrates?.let { append("$bullet **Carbohydrates:** ${String.format("%.1f", it)} g\n") }
        nutrition.fat?.let { append("$bullet **Fat:** ${String.format("%.1f", it)} g\n") }
        nutrition.saturatedFat?.let { append("$bullet **Saturated Fat:** ${String.format("%.1f", it)} g\n") }
        nutrition.fiber?.let { append("$bullet **Fiber:** ${String.format("%.1f", it)} g\n") }
        nutrition.sugar?.let { append("$bullet **Sugar:** ${String.format("%.1f", it)} g\n") }
        nutrition.sodium?.let { append("$bullet **Sodium:** ${ExportHelpers.formatNumber(it.toInt())} mg\n") }
        nutrition.cholesterol?.let { append("$bullet **Cholesterol:** ${String.format("%.1f", it)} mg\n") }
        nutrition.water?.let { append("$bullet **Water:** ${converter.formatVolume(it)}\n") }
        nutrition.caffeine?.let { append("$bullet **Caffeine:** ${String.format("%.1f", it)} mg\n") }
    }

    private fun mobilityMetrics(mobility: MobilityData, bullet: String, converter: UnitConverter): String = buildString {
        mobility.walkingSpeed?.let { append("$bullet **Walking Speed:** ${converter.formatSpeed(it)}\n") }
        mobility.vo2Max?.let { append("$bullet **VO2 Max:** ${String.format("%.1f", it)} mL/kg/min\n") }
        mobility.cyclingCadenceAvg?.let { append("$bullet **Cycling Cadence:** ${String.format("%.1f", it)} rpm\n") }
        mobility.stepsCadenceAvg?.let { append("$bullet **Steps Cadence:** ${String.format("%.1f", it)} steps/min\n") }
        mobility.powerAvg?.let { append("$bullet **Average Power:** ${String.format("%.1f", it)} W\n") }
        mobility.powerMax?.let { append("$bullet **Max Power:** ${String.format("%.1f", it)} W\n") }
    }

    private fun reproductiveHealthMetrics(repro: ReproductiveHealthData, bullet: String): String = buildString {
        repro.menstrualFlow?.let { append("$bullet **Menstrual Flow:** $it\n") }
        repro.cervicalMucusAppearance?.let { append("$bullet **Cervical Mucus Appearance:** $it\n") }
        repro.cervicalMucusSensation?.let { append("$bullet **Cervical Mucus Sensation:** $it\n") }
        repro.ovulationTestResult?.let { append("$bullet **Ovulation Test:** $it\n") }
        if (repro.intermenstrualBleeding) append("$bullet **Intermenstrual Bleeding:** yes\n")
        if (repro.sexualActivityRecorded) {
            append("$bullet **Sexual Activity:** yes")
            repro.sexualActivityProtectionUsed?.let { append(" ($it)") }
            append("\n")
        }
    }

    private fun mindfulnessMetrics(mindfulness: MindfulnessData, bullet: String): String = buildString {
        mindfulness.mindfulnessMinutes?.let { append("$bullet **Mindful Minutes:** ${it.toInt()} min\n") }
    }

    private fun workoutsMarkdown(workouts: List<WorkoutData>, bullet: String, customization: FormatCustomization): String = buildString {
        for (workout in workouts) {
            val timeStr = customization.timeFormat.format(workout.startTime)
            val durationStr = ExportHelpers.formatDurationShort(workout.duration)
            append("$bullet **${workout.workoutType.displayName()}** \u2014 $durationStr (at $timeStr)")
            workout.distance?.let { if (it > 0) append(" \u2014 ${customization.unitConverter.formatDistance(it)}") }
            workout.calories?.let { if (it > 0) append(" \u2014 ${it.toInt()} kcal") }
            append("\n")
        }
    }

}

private data class SectionEmojis(
    val sleep: String,
    val activity: String,
    val heart: String,
    val vitals: String,
    val body: String,
    val nutrition: String,
    val mobility: String,
    val reproductiveHealth: String,
    val mindfulness: String,
    val workouts: String,
) {
    companion object {
        val NONE = SectionEmojis("", "", "", "", "", "", "", "", "", "")
        val WITH_EMOJI = SectionEmojis(
            sleep = "\uD83D\uDE34 ", activity = "\uD83C\uDFC3 ", heart = "\u2764\uFE0F ",
            vitals = "\uD83E\uDE7A ", body = "\uD83D\uDCCF ", nutrition = "\uD83C\uDF4E ",
            mobility = "\uD83D\uDEB6 ", reproductiveHealth = "\uD83C\uDF38 ",
            mindfulness = "\uD83E\uDDD8 ", workouts = "\uD83D\uDCAA ",
        )
    }
}
