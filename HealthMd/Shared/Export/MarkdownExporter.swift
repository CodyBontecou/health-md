import Foundation

// MARK: - Markdown Export

extension HealthData {
    func toMarkdown(includeMetadata: Bool = true, groupByCategory: Bool = true, customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let snapshot = exportSnapshot(customization: config)
        let template = config.markdownTemplate
        let bullet = template.bulletStyle.rawValue
        let headerPrefix = String(repeating: "#", count: template.sectionHeaderLevel)

        // Emoji prefixes based on settings
        let sleepEmoji = template.useEmoji ? "😴 " : ""
        let activityEmoji = template.useEmoji ? "🏃 " : ""
        let heartEmoji = template.useEmoji ? "❤️ " : ""
        let vitalsEmoji = template.useEmoji ? "🩺 " : ""
        let bodyEmoji = template.useEmoji ? "📏 " : ""
        let nutritionEmoji = template.useEmoji ? "🍎 " : ""
        let mindfulnessEmoji = template.useEmoji ? "🧘 " : ""
        let mobilityEmoji = template.useEmoji ? "🚶 " : ""
        let hearingEmoji = template.useEmoji ? "👂 " : ""
        let workoutsEmoji = template.useEmoji ? "💪 " : ""

        var markdown = ""

        if includeMetadata {
            let fmConfig = config.frontmatterConfig
            markdown += "---\n"
            if fmConfig.includeDate {
                markdown += "\(fmConfig.customDateKey): \(snapshot.dateString)\n"
            }
            if fmConfig.includeType {
                markdown += "\(fmConfig.customTypeKey): \(fmConfig.customTypeValue)\n"
            }
            // Add custom static fields (with fixed values)
            for (key, value) in fmConfig.customFields.sorted(by: { $0.key < $1.key }) {
                markdown += "\(key): \(value)\n"
            }
            // Add placeholder fields (empty values for manual entry)
            for key in fmConfig.placeholderFields.sorted() {
                markdown += "\(key): \n"
            }
            markdown += "---\n\n"
        }

        if template.style == .custom {
            markdown += renderCustomMarkdown(
                snapshot: snapshot,
                template: template,
                bullet: bullet,
                headerPrefix: headerPrefix,
                sleepEmoji: sleepEmoji,
                activityEmoji: activityEmoji,
                heartEmoji: heartEmoji,
                vitalsEmoji: vitalsEmoji,
                bodyEmoji: bodyEmoji,
                nutritionEmoji: nutritionEmoji,
                mindfulnessEmoji: mindfulnessEmoji,
                mobilityEmoji: mobilityEmoji,
                hearingEmoji: hearingEmoji,
                workoutsEmoji: workoutsEmoji
            )
        } else {
            markdown += renderStandardMarkdown(
                snapshot: snapshot,
                template: template,
                bullet: bullet,
                headerPrefix: headerPrefix,
                sleepEmoji: sleepEmoji,
                activityEmoji: activityEmoji,
                heartEmoji: heartEmoji,
                vitalsEmoji: vitalsEmoji,
                bodyEmoji: bodyEmoji,
                nutritionEmoji: nutritionEmoji,
                mindfulnessEmoji: mindfulnessEmoji,
                mobilityEmoji: mobilityEmoji,
                hearingEmoji: hearingEmoji,
                workoutsEmoji: workoutsEmoji
            )
        }

        return markdown
    }

    private func renderStandardMarkdown(
        snapshot: ExportDataSnapshot,
        template: MarkdownTemplateConfig,
        bullet: String,
        headerPrefix: String,
        sleepEmoji: String,
        activityEmoji: String,
        heartEmoji: String,
        vitalsEmoji: String,
        bodyEmoji: String,
        nutritionEmoji: String,
        mindfulnessEmoji: String,
        mobilityEmoji: String,
        hearingEmoji: String,
        workoutsEmoji: String
    ) -> String {
        var markdown = "# Health Data — \(snapshot.dateString)\n"

        let summary = summaryText(snapshot: snapshot, template: template)
        if !summary.isEmpty {
            markdown += "\n\(summary)\n"
        }

        markdown += allSectionsMarkdown(
            snapshot: snapshot,
            template: template,
            bullet: bullet,
            headerPrefix: headerPrefix,
            sleepEmoji: sleepEmoji,
            activityEmoji: activityEmoji,
            heartEmoji: heartEmoji,
            vitalsEmoji: vitalsEmoji,
            bodyEmoji: bodyEmoji,
            nutritionEmoji: nutritionEmoji,
            mindfulnessEmoji: mindfulnessEmoji,
            mobilityEmoji: mobilityEmoji,
            hearingEmoji: hearingEmoji,
            workoutsEmoji: workoutsEmoji
        )

        return markdown
    }

    private func renderCustomMarkdown(
        snapshot: ExportDataSnapshot,
        template: MarkdownTemplateConfig,
        bullet: String,
        headerPrefix: String,
        sleepEmoji: String,
        activityEmoji: String,
        heartEmoji: String,
        vitalsEmoji: String,
        bodyEmoji: String,
        nutritionEmoji: String,
        mindfulnessEmoji: String,
        mobilityEmoji: String,
        hearingEmoji: String,
        workoutsEmoji: String
    ) -> String {
        var rendered = template.customTemplate

        // Conditional blocks: {{#sleep}}...{{/sleep}}
        let sectionPresence: [(name: String, include: Bool)] = [
            ("sleep", snapshot.sleep.hasData),
            ("activity", snapshot.activity.hasData),
            ("heart", snapshot.heart.hasData),
            ("vitals", snapshot.vitals.hasData),
            ("body", snapshot.body.hasData),
            ("nutrition", snapshot.nutrition.hasData),
            ("mindfulness", snapshot.mindfulness.hasData),
            ("mobility", snapshot.mobility.hasData),
            ("hearing", snapshot.hearing.hasData),
            ("workouts", !snapshot.workouts.isEmpty),
            ("reproductiveHealth", snapshot.reproductiveHealth.hasData),
            ("cycling", snapshot.cyclingPerformance.hasData),
            ("vitamins", snapshot.vitamins.hasData),
            ("minerals", snapshot.minerals.hasData),
            ("symptoms", snapshot.symptoms.hasData),
            ("other", snapshot.otherHealth.hasData)
        ]

        for section in sectionPresence {
            rendered = applyConditionalSection(in: rendered, section: section.name, include: section.include)
        }

        let summary = summaryText(snapshot: snapshot, template: template)
        let sleepMetrics = sleepMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        let activityMetrics = activityMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        let heartMetrics = heartMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        let vitalsMetrics = vitalsMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        let bodyMetrics = bodyMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        let nutritionMetrics = nutritionMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        let mindfulnessMetrics = mindfulnessMetricsMarkdown(snapshot: snapshot, bullet: bullet, template: template)
        let mobilityMetrics = mobilityMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        let hearingMetrics = hearingMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        let workoutList = workoutsListMarkdown(snapshot: snapshot, bullet: bullet, template: template)

        let allMetrics = allSectionsMarkdown(
            snapshot: snapshot,
            template: template,
            bullet: bullet,
            headerPrefix: headerPrefix,
            sleepEmoji: sleepEmoji,
            activityEmoji: activityEmoji,
            heartEmoji: heartEmoji,
            vitalsEmoji: vitalsEmoji,
            bodyEmoji: bodyEmoji,
            nutritionEmoji: nutritionEmoji,
            mindfulnessEmoji: mindfulnessEmoji,
            mobilityEmoji: mobilityEmoji,
            hearingEmoji: hearingEmoji,
            workoutsEmoji: workoutsEmoji
        )

        let replacements: [String: String] = [
            "date": snapshot.dateString,
            "summary": summary,
            "metrics": allMetrics,
            "sleep_metrics": sleepMetrics,
            "activity_metrics": activityMetrics,
            "heart_metrics": heartMetrics,
            "vitals_metrics": vitalsMetrics,
            "body_metrics": bodyMetrics,
            "nutrition_metrics": nutritionMetrics,
            "mindfulness_metrics": mindfulnessMetrics,
            "mobility_metrics": mobilityMetrics,
            "hearing_metrics": hearingMetrics,
            "workout_list": workoutList,
            "workouts_metrics": workoutList
        ]

        for (key, value) in replacements {
            rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        return rendered
    }

    private func allSectionsMarkdown(
        snapshot: ExportDataSnapshot,
        template: MarkdownTemplateConfig,
        bullet: String,
        headerPrefix: String,
        sleepEmoji: String,
        activityEmoji: String,
        heartEmoji: String,
        vitalsEmoji: String,
        bodyEmoji: String,
        nutritionEmoji: String,
        mindfulnessEmoji: String,
        mobilityEmoji: String,
        hearingEmoji: String,
        workoutsEmoji: String
    ) -> String {
        var markdown = ""

        if snapshot.sleep.hasData {
            markdown += "\n\(headerPrefix) \(sleepEmoji)Sleep\n\n"
            markdown += sleepMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        }

        if snapshot.activity.hasData || snapshot.hasCategoryData(.activity) {
            markdown += "\n\(headerPrefix) \(activityEmoji)Activity\n\n"
            markdown += activityMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        }

        if snapshot.heart.hasData || snapshot.hasCategoryData(.heart) {
            markdown += "\n\(headerPrefix) \(heartEmoji)Heart\n\n"
            markdown += heartMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        }

        if snapshot.vitals.hasData || snapshot.hasCategoryData(.vitals) || snapshot.hasCategoryData(.respiratory) {
            markdown += "\n\(headerPrefix) \(vitalsEmoji)Vitals\n\n"
            markdown += vitalsMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        }

        if snapshot.body.hasData {
            markdown += "\n\(headerPrefix) \(bodyEmoji)Body\n\n"
            markdown += bodyMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        }

        if snapshot.nutrition.hasData || snapshot.hasCategoryData(.nutrition) {
            markdown += "\n\(headerPrefix) \(nutritionEmoji)Nutrition\n\n"
            markdown += nutritionMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        }

        if snapshot.mindfulness.hasData {
            markdown += "\n\(headerPrefix) \(mindfulnessEmoji)Mindfulness\n\n"
            markdown += mindfulnessMetricsMarkdown(snapshot: snapshot, bullet: bullet, template: template)
        }

        if snapshot.mobility.hasData || snapshot.hasCategoryData(.mobility) {
            markdown += "\n\(headerPrefix) \(mobilityEmoji)Mobility\n\n"
            markdown += mobilityMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        }

        if snapshot.hearing.hasData {
            markdown += "\n\(headerPrefix) \(hearingEmoji)Hearing\n\n"
            markdown += hearingMetricsMarkdown(snapshot: snapshot, bullet: bullet)
        }

        if !snapshot.workouts.isEmpty {
            markdown += "\n\(headerPrefix) \(workoutsEmoji)Workouts\n"
            markdown += workoutsListMarkdown(snapshot: snapshot, bullet: bullet, template: template)
        }

        if snapshot.reproductiveHealth.hasData {
            markdown += "\n\(headerPrefix) Reproductive Health\n\n"
            for m in snapshot.metricsForCategory(.reproductiveHealth) {
                markdown += "\(bullet) **\(m.label):** \(m.value)\n"
            }
        }

        if snapshot.cyclingPerformance.hasData {
            markdown += "\n\(headerPrefix) Cycling Performance\n\n"
            for m in snapshot.metricsForCategory(.cycling) {
                markdown += "\(bullet) **\(m.label):** \(m.value)\n"
            }
        }

        if snapshot.vitamins.hasData {
            markdown += "\n\(headerPrefix) Vitamins\n\n"
            for m in snapshot.metricsForCategory(.vitamins) {
                markdown += "\(bullet) **\(m.label):** \(m.value)\n"
            }
        }

        if snapshot.minerals.hasData {
            markdown += "\n\(headerPrefix) Minerals\n\n"
            for m in snapshot.metricsForCategory(.minerals) {
                markdown += "\(bullet) **\(m.label):** \(m.value)\n"
            }
        }

        if snapshot.symptoms.hasData {
            markdown += "\n\(headerPrefix) Symptoms\n\n"
            for (key, count) in snapshot.symptoms.counts.sorted(by: { $0.key < $1.key }) {
                let label = key.replacingOccurrences(of: "symptom_", with: "").replacingOccurrences(of: "_", with: " ").capitalized
                markdown += "\(bullet) **\(label):** \(count)\n"
            }
        }

        if snapshot.otherHealth.hasData {
            markdown += "\n\(headerPrefix) Other\n\n"
            for m in snapshot.metricsForCategory(.other) {
                markdown += "\(bullet) **\(m.label):** \(m.value)\n"
            }
        }

        return markdown
    }

    private func summaryText(snapshot: ExportDataSnapshot, template: MarkdownTemplateConfig) -> String {
        guard template.includeSummary else { return "" }

        var summaryParts: [String] = []
        if snapshot.sleep.totalDurationSeconds > 0 {
            summaryParts.append(formatDuration(snapshot.sleep.totalDurationSeconds) + " sleep")
        }
        if let steps = snapshot.activity.steps {
            summaryParts.append(formatNumber(steps) + " steps")
        }
        if !snapshot.workouts.isEmpty {
            summaryParts.append("\(snapshot.workouts.count) workout\(snapshot.workouts.count > 1 ? "s" : "")")
        }
        if let avgValence = snapshot.mindfulness.averageValence,
           let valencePercent = snapshot.mindfulness.averageValencePercent {
            let moodEmoji = template.useEmoji ? (avgValence >= 0.2 ? "🙂" : avgValence <= -0.2 ? "😔" : "😐") + " " : ""
            summaryParts.append("\(moodEmoji)mood \(valencePercent)%")
        }

        return summaryParts.joined(separator: " · ")
    }

    private func sleepMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String) -> String {
        var markdown = ""
        if snapshot.sleep.totalDurationSeconds > 0 {
            markdown += "\(bullet) **Total:** \(formatDuration(snapshot.sleep.totalDurationSeconds))\n"
        }
        if let bedtime = snapshot.sleep.bedtime {
            markdown += "\(bullet) **Bedtime:** \(snapshot.timeFormat.format(date: bedtime))\n"
        }
        if let wake = snapshot.sleep.wakeTime {
            markdown += "\(bullet) **Wake:** \(snapshot.timeFormat.format(date: wake))\n"
        }
        if snapshot.sleep.inBedSeconds > 0 {
            markdown += "\(bullet) **In Bed:** \(formatDuration(snapshot.sleep.inBedSeconds))\n"
        }
        if snapshot.sleep.deepSleepSeconds > 0 {
            markdown += "\(bullet) **Deep:** \(formatDuration(snapshot.sleep.deepSleepSeconds))\n"
        }
        if snapshot.sleep.remSleepSeconds > 0 {
            markdown += "\(bullet) **REM:** \(formatDuration(snapshot.sleep.remSleepSeconds))\n"
        }
        if snapshot.sleep.coreSleepSeconds > 0 {
            markdown += "\(bullet) **Core:** \(formatDuration(snapshot.sleep.coreSleepSeconds))\n"
        }
        if snapshot.sleep.awakeSeconds > 0 {
            markdown += "\(bullet) **Awake:** \(formatDuration(snapshot.sleep.awakeSeconds))\n"
        }
        if !snapshot.sleep.stages.isEmpty {
            markdown += "\n<details>\n<summary>Sleep Stages Timeline (\(snapshot.sleep.stages.count) intervals)</summary>\n\n"
            markdown += "| Time | Stage | Duration |\n|------|-------|----------|\n"
            for stage in snapshot.sleep.stages {
                let time = snapshot.timeFormat.format(date: stage.startDate)
                let duration = stage.endDate.timeIntervalSince(stage.startDate)
                markdown += "| \(time) | \(stage.stage) | \(formatDuration(duration)) |\n"
            }
            markdown += "\n</details>\n"
        }
        return markdown
    }

    private func activityMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String) -> String {
        var markdown = ""
        if let steps = snapshot.activity.steps {
            markdown += "\(bullet) **Steps:** \(formatNumber(steps))\n"
        }
        if let calories = snapshot.activity.activeCalories {
            markdown += "\(bullet) **Active Calories:** \(formatNumber(Int(calories))) kcal\n"
        }
        if let basal = snapshot.activity.basalEnergyBurned {
            markdown += "\(bullet) **Basal Energy:** \(formatNumber(Int(basal))) kcal\n"
        }
        if let exercise = snapshot.activity.exerciseMinutes {
            markdown += "\(bullet) **Exercise:** \(Int(exercise)) min\n"
        }
        if let standHours = snapshot.activity.standHours {
            markdown += "\(bullet) **Stand Hours:** \(standHours)\n"
        }
        if let flights = snapshot.activity.flightsClimbed {
            markdown += "\(bullet) **Flights Climbed:** \(flights)\n"
        }
        if let distance = snapshot.activity.walkingRunningDistanceMeters {
            markdown += "\(bullet) **Walking/Running Distance:** \(snapshot.converter.formatDistance(distance))\n"
        }
        if let cycling = snapshot.activity.cyclingDistanceMeters {
            markdown += "\(bullet) **Cycling Distance:** \(snapshot.converter.formatDistance(cycling))\n"
        }
        if let swimming = snapshot.activity.swimmingDistanceMeters {
            markdown += "\(bullet) **Swimming Distance:** \(snapshot.converter.formatDistance(swimming))\n"
        }
        if let strokes = snapshot.activity.swimmingStrokes {
            markdown += "\(bullet) **Swimming Strokes:** \(formatNumber(strokes))\n"
        }
        if let pushes = snapshot.activity.wheelchairPushes {
            markdown += "\(bullet) **Wheelchair Pushes:** \(formatNumber(pushes))\n"
        }
        if let vo2 = snapshot.activity.vo2Max {
            markdown += "\(bullet) **Cardio Fitness (VO2 Max):** \(String(format: "%.1f", vo2)) mL/kg/min\n"
        }
        if let v = snapshot.frontmatterMetrics["wheelchair_km"] {
            markdown += "\(bullet) **Wheelchair Distance:** \(v) km\n"
        }
        if let v = snapshot.frontmatterMetrics["downhill_snow_km"] {
            markdown += "\(bullet) **Downhill Snow Distance:** \(v) km\n"
        }
        if let v = snapshot.frontmatterMetrics["move_minutes"] {
            markdown += "\(bullet) **Move Minutes:** \(v) min\n"
        }
        if let v = snapshot.frontmatterMetrics["physical_effort"] {
            markdown += "\(bullet) **Physical Effort:** \(v)\n"
        }
        return markdown
    }

    private func heartMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String) -> String {
        var markdown = ""
        if let hr = snapshot.heart.restingHeartRate {
            markdown += "\(bullet) **Resting HR:** \(Int(hr)) bpm\n"
        }
        if let walkingHR = snapshot.heart.walkingHeartRateAverage {
            markdown += "\(bullet) **Walking HR Average:** \(Int(walkingHR)) bpm\n"
        }
        if let avgHR = snapshot.heart.averageHeartRate {
            markdown += "\(bullet) **Average HR:** \(Int(avgHR)) bpm\n"
        }
        if let minHR = snapshot.heart.minHeartRate {
            markdown += "\(bullet) **Min HR:** \(Int(minHR)) bpm\n"
        }
        if let maxHR = snapshot.heart.maxHeartRate {
            markdown += "\(bullet) **Max HR:** \(Int(maxHR)) bpm\n"
        }
        if let hrv = snapshot.heart.hrvMilliseconds {
            markdown += "\(bullet) **HRV:** \(String(format: "%.1f", hrv)) ms\n"
        }
        if !snapshot.heart.heartRateSamples.isEmpty {
            markdown += "\n<details>\n<summary>Heart Rate Samples (\(snapshot.heart.heartRateSamples.count) readings)</summary>\n\n"
            markdown += "| Time | BPM |\n|------|-----|\n"
            for sample in snapshot.heart.heartRateSamples {
                markdown += "| \(snapshot.timeFormat.format(date: sample.timestamp)) | \(Int(sample.value)) |\n"
            }
            markdown += "\n</details>\n"
        }
        if !snapshot.heart.hrvSamples.isEmpty {
            markdown += "\n<details>\n<summary>HRV Samples (\(snapshot.heart.hrvSamples.count) readings)</summary>\n\n"
            markdown += "| Time | ms |\n|------|----|\n"
            for sample in snapshot.heart.hrvSamples {
                markdown += "| \(snapshot.timeFormat.format(date: sample.timestamp)) | \(String(format: "%.1f", sample.value)) |\n"
            }
            markdown += "\n</details>\n"
        }
        if let v = snapshot.frontmatterMetrics["heart_rate_recovery"] {
            markdown += "\(bullet) **Heart Rate Recovery:** \(v) bpm\n"
        }
        if let v = snapshot.frontmatterMetrics["afib_burden_percent"] {
            markdown += "\(bullet) **AFib Burden:** \(v)%\n"
        }
        return markdown
    }

    private func vitalsMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String) -> String {
        var markdown = ""

        if let rrAvg = snapshot.vitals.respiratoryRateAvg {
            var rrStr = "\(bullet) **Respiratory Rate:** \(String(format: "%.1f", rrAvg)) breaths/min"
            if let rrMin = snapshot.vitals.respiratoryRateMin,
               let rrMax = snapshot.vitals.respiratoryRateMax,
               rrMin != rrMax {
                rrStr += " (range: \(String(format: "%.1f", rrMin))–\(String(format: "%.1f", rrMax)))"
            }
            markdown += rrStr + "\n"
        }

        if let spo2Avg = snapshot.vitals.bloodOxygenAvg {
            var spo2Str = "\(bullet) **SpO2:** \(Int(spo2Avg * 100))%"
            if let spo2Min = snapshot.vitals.bloodOxygenMin,
               let spo2Max = snapshot.vitals.bloodOxygenMax,
               spo2Min != spo2Max {
                spo2Str += " (range: \(Int(spo2Min * 100))%–\(Int(spo2Max * 100))%)"
            }
            markdown += spo2Str + "\n"
        }

        if let tempAvg = snapshot.vitals.bodyTemperatureAvgCelsius {
            var tempStr = "\(bullet) **Body Temperature:** \(snapshot.converter.formatTemperature(tempAvg))"
            if let tempMin = snapshot.vitals.bodyTemperatureMinCelsius,
               let tempMax = snapshot.vitals.bodyTemperatureMaxCelsius,
               tempMin != tempMax {
                tempStr += " (range: \(snapshot.converter.formatTemperature(tempMin))–\(snapshot.converter.formatTemperature(tempMax)))"
            }
            markdown += tempStr + "\n"
        }

        if let systolicAvg = snapshot.vitals.bloodPressureSystolicAvg,
           let diastolicAvg = snapshot.vitals.bloodPressureDiastolicAvg {
            var bpStr = "\(bullet) **Blood Pressure:** \(Int(systolicAvg))/\(Int(diastolicAvg)) mmHg"
            if let sysMin = snapshot.vitals.bloodPressureSystolicMin,
               let sysMax = snapshot.vitals.bloodPressureSystolicMax,
               let diaMin = snapshot.vitals.bloodPressureDiastolicMin,
               let diaMax = snapshot.vitals.bloodPressureDiastolicMax,
               (sysMin != sysMax || diaMin != diaMax) {
                bpStr += " (range: \(Int(sysMin))/\(Int(diaMin))–\(Int(sysMax))/\(Int(diaMax)))"
            }
            markdown += bpStr + "\n"
        }

        if let glucoseAvg = snapshot.vitals.bloodGlucoseAvg {
            var glucoseStr = "\(bullet) **Blood Glucose:** \(String(format: "%.1f", glucoseAvg)) mg/dL"
            if let glucoseMin = snapshot.vitals.bloodGlucoseMin,
               let glucoseMax = snapshot.vitals.bloodGlucoseMax,
               glucoseMin != glucoseMax {
                glucoseStr += " (range: \(String(format: "%.1f", glucoseMin))–\(String(format: "%.1f", glucoseMax)))"
            }
            markdown += glucoseStr + "\n"
        }

        if !snapshot.vitals.bloodOxygenSamples.isEmpty {
            markdown += "\n<details>\n<summary>Blood Oxygen Samples (\(snapshot.vitals.bloodOxygenSamples.count) readings)</summary>\n\n"
            markdown += "| Time | SpO2 |\n|------|------|\n"
            for sample in snapshot.vitals.bloodOxygenSamples {
                markdown += "| \(snapshot.timeFormat.format(date: sample.timestamp)) | \(String(format: "%.1f", sample.value * 100))% |\n"
            }
            markdown += "\n</details>\n"
        }
        if !snapshot.vitals.bloodGlucoseSamples.isEmpty {
            markdown += "\n<details>\n<summary>Blood Glucose Samples (\(snapshot.vitals.bloodGlucoseSamples.count) readings)</summary>\n\n"
            markdown += "| Time | mg/dL |\n|------|-------|\n"
            for sample in snapshot.vitals.bloodGlucoseSamples {
                markdown += "| \(snapshot.timeFormat.format(date: sample.timestamp)) | \(String(format: "%.1f", sample.value)) |\n"
            }
            markdown += "\n</details>\n"
        }
        if !snapshot.vitals.respiratoryRateSamples.isEmpty {
            markdown += "\n<details>\n<summary>Respiratory Rate Samples (\(snapshot.vitals.respiratoryRateSamples.count) readings)</summary>\n\n"
            markdown += "| Time | breaths/min |\n|------|-------------|\n"
            for sample in snapshot.vitals.respiratoryRateSamples {
                markdown += "| \(snapshot.timeFormat.format(date: sample.timestamp)) | \(String(format: "%.1f", sample.value)) |\n"
            }
            markdown += "\n</details>\n"
        }
        if let v = snapshot.frontmatterMetrics["basal_body_temperature"] {
            markdown += "\(bullet) **Basal Body Temperature:** \(v)\n"
        }
        if let v = snapshot.frontmatterMetrics["wrist_temperature"] {
            markdown += "\(bullet) **Wrist Temperature:** \(v)\n"
        }
        if let v = snapshot.frontmatterMetrics["electrodermal_activity"] {
            markdown += "\(bullet) **Electrodermal Activity:** \(v)\n"
        }
        if let v = snapshot.frontmatterMetrics["forced_vital_capacity_l"] {
            markdown += "\(bullet) **Forced Vital Capacity:** \(v) L\n"
        }
        if let v = snapshot.frontmatterMetrics["fev1_l"] {
            markdown += "\(bullet) **FEV1:** \(v) L\n"
        }
        if let v = snapshot.frontmatterMetrics["peak_expiratory_flow"] {
            markdown += "\(bullet) **Peak Expiratory Flow:** \(v)\n"
        }
        if let v = snapshot.frontmatterMetrics["inhaler_usage"] {
            markdown += "\(bullet) **Inhaler Usage:** \(v)\n"
        }

        return markdown
    }

    private func bodyMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String) -> String {
        var markdown = ""
        if let weight = snapshot.body.weightKg {
            markdown += "\(bullet) **Weight:** \(snapshot.converter.formatWeight(weight))\n"
        }
        if let height = snapshot.body.heightMeters {
            markdown += "\(bullet) **Height:** \(snapshot.converter.formatHeight(height))\n"
        }
        if let bmi = snapshot.body.bmi {
            markdown += "\(bullet) **BMI:** \(String(format: "%.1f", bmi))\n"
        }
        if let bodyFat = snapshot.body.bodyFatRatio {
            markdown += "\(bullet) **Body Fat:** \(String(format: "%.1f", bodyFat * 100))%\n"
        }
        if let lean = snapshot.body.leanBodyMassKg {
            markdown += "\(bullet) **Lean Body Mass:** \(snapshot.converter.formatWeight(lean))\n"
        }
        if let waist = snapshot.body.waistCircumferenceMeters {
            markdown += "\(bullet) **Waist Circumference:** \(snapshot.converter.formatLength(waist))\n"
        }
        return markdown
    }

    private func nutritionMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String) -> String {
        var markdown = ""
        if let energy = snapshot.nutrition.dietaryEnergyKcal {
            markdown += "\(bullet) **Calories:** \(formatNumber(Int(energy))) kcal\n"
        }
        if let protein = snapshot.nutrition.proteinGrams {
            markdown += "\(bullet) **Protein:** \(String(format: "%.1f", protein)) g\n"
        }
        if let carbs = snapshot.nutrition.carbohydratesGrams {
            markdown += "\(bullet) **Carbohydrates:** \(String(format: "%.1f", carbs)) g\n"
        }
        if let fat = snapshot.nutrition.fatGrams {
            markdown += "\(bullet) **Fat:** \(String(format: "%.1f", fat)) g\n"
        }
        if let saturatedFat = snapshot.nutrition.saturatedFatGrams {
            markdown += "\(bullet) **Saturated Fat:** \(String(format: "%.1f", saturatedFat)) g\n"
        }
        if let fiber = snapshot.nutrition.fiberGrams {
            markdown += "\(bullet) **Fiber:** \(String(format: "%.1f", fiber)) g\n"
        }
        if let sugar = snapshot.nutrition.sugarGrams {
            markdown += "\(bullet) **Sugar:** \(String(format: "%.1f", sugar)) g\n"
        }
        if let sodium = snapshot.nutrition.sodiumMg {
            markdown += "\(bullet) **Sodium:** \(formatNumber(Int(sodium))) mg\n"
        }
        if let cholesterol = snapshot.nutrition.cholesterolMg {
            markdown += "\(bullet) **Cholesterol:** \(String(format: "%.1f", cholesterol)) mg\n"
        }
        if let water = snapshot.nutrition.waterLiters {
            markdown += "\(bullet) **Water:** \(snapshot.converter.formatVolume(water))\n"
        }
        if let caffeine = snapshot.nutrition.caffeineMg {
            markdown += "\(bullet) **Caffeine:** \(String(format: "%.1f", caffeine)) mg\n"
        }
        if let v = snapshot.frontmatterMetrics["monounsaturated_fat_g"] {
            markdown += "\(bullet) **Monounsaturated Fat:** \(v) g\n"
        }
        if let v = snapshot.frontmatterMetrics["polyunsaturated_fat_g"] {
            markdown += "\(bullet) **Polyunsaturated Fat:** \(v) g\n"
        }
        return markdown
    }

    private func mindfulnessMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String, template: MarkdownTemplateConfig) -> String {
        var markdown = ""

        if let minutes = snapshot.mindfulness.mindfulMinutes {
            markdown += "\(bullet) **Mindful Minutes:** \(Int(minutes)) min\n"
        }
        if let sessions = snapshot.mindfulness.mindfulSessions {
            markdown += "\(bullet) **Sessions:** \(sessions)\n"
        }

        if !snapshot.mindfulness.stateOfMindEntries.isEmpty {
            markdown += "\n"

            if let avgValence = snapshot.mindfulness.averageValence,
               let valencePercent = snapshot.mindfulness.averageValencePercent {
                markdown += "\(bullet) **Average Mood:** \(valencePercent)% (\(valenceDescription(avgValence)))\n"
            }

            if !snapshot.mindfulness.dailyMoods.isEmpty {
                markdown += "\(bullet) **Daily Mood Entries:** \(snapshot.mindfulness.dailyMoods.count)\n"
            }

            if !snapshot.mindfulness.momentaryEmotions.isEmpty {
                markdown += "\(bullet) **Momentary Emotions:** \(snapshot.mindfulness.momentaryEmotions.count)\n"
            }

            if !snapshot.mindfulness.emotionLabels.isEmpty {
                markdown += "\(bullet) **Emotions/Moods:** \(snapshot.mindfulness.emotionLabels.joined(separator: ", "))\n"
            }

            if !snapshot.mindfulness.associations.isEmpty {
                markdown += "\(bullet) **Associated With:** \(snapshot.mindfulness.associations.joined(separator: ", "))\n"
            }

            if template.includeSummary && snapshot.mindfulness.stateOfMindEntries.count <= 5 {
                let subHeaderPrefix = String(repeating: "#", count: template.sectionHeaderLevel + 1)
                markdown += "\n\(subHeaderPrefix) Mood Entries\n\n"

                for entry in snapshot.mindfulness.stateOfMindEntries {
                    let timeStr = snapshot.timeFormat.format(date: entry.timestamp)
                    let emoji = template.useEmoji ? entry.valenceEmoji + " " : ""
                    markdown += "\(bullet) **\(timeStr)** \(emoji)(\(entry.kind.rawValue)): \(entry.valencePercent)%"
                    if !entry.labels.isEmpty {
                        markdown += " — \(entry.labels.joined(separator: ", "))"
                    }
                    markdown += "\n"
                }
            }
        }

        return markdown
    }

    private func mobilityMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String) -> String {
        var markdown = ""
        if let speed = snapshot.mobility.walkingSpeedMps {
            markdown += "\(bullet) **Walking Speed:** \(snapshot.converter.formatSpeed(speed))\n"
        }
        if let stepLength = snapshot.mobility.walkingStepLengthMeters {
            markdown += "\(bullet) **Step Length:** \(snapshot.converter.formatLength(stepLength))\n"
        }
        if let doubleSupport = snapshot.mobility.walkingDoubleSupportRatio {
            markdown += "\(bullet) **Double Support:** \(String(format: "%.1f", doubleSupport * 100))%\n"
        }
        if let asymmetry = snapshot.mobility.walkingAsymmetryRatio {
            markdown += "\(bullet) **Walking Asymmetry:** \(String(format: "%.1f", asymmetry * 100))%\n"
        }
        if let ascent = snapshot.mobility.stairAscentSpeedMps {
            markdown += "\(bullet) **Stair Ascent Speed:** \(snapshot.converter.formatSpeed(ascent))\n"
        }
        if let descent = snapshot.mobility.stairDescentSpeedMps {
            markdown += "\(bullet) **Stair Descent Speed:** \(snapshot.converter.formatSpeed(descent))\n"
        }
        if let sixMin = snapshot.mobility.sixMinuteWalkDistanceMeters {
            markdown += "\(bullet) **6-Min Walk Distance:** \(snapshot.converter.formatDistance(sixMin))\n"
        }
        if let v = snapshot.frontmatterMetrics["walking_steadiness_percent"] {
            markdown += "\(bullet) **Walking Steadiness:** \(v)%\n"
        }
        if let v = snapshot.frontmatterMetrics["running_speed"] {
            markdown += "\(bullet) **Running Speed:** \(v)\n"
        }
        if let v = snapshot.frontmatterMetrics["running_stride_length_m"] {
            markdown += "\(bullet) **Running Stride Length:** \(v) m\n"
        }
        if let v = snapshot.frontmatterMetrics["running_ground_contact_ms"] {
            markdown += "\(bullet) **Running Ground Contact:** \(v) ms\n"
        }
        if let v = snapshot.frontmatterMetrics["running_vertical_oscillation_cm"] {
            markdown += "\(bullet) **Running Vertical Oscillation:** \(v) cm\n"
        }
        if let v = snapshot.frontmatterMetrics["running_power_w"] {
            markdown += "\(bullet) **Running Power:** \(v) W\n"
        }
        return markdown
    }

    private func hearingMetricsMarkdown(snapshot: ExportDataSnapshot, bullet: String) -> String {
        var markdown = ""
        if let headphone = snapshot.hearing.headphoneAudioLevelDb {
            markdown += "\(bullet) **Headphone Audio Level:** \(String(format: "%.1f", headphone)) dB\n"
        }
        if let environmental = snapshot.hearing.environmentalSoundLevelDb {
            markdown += "\(bullet) **Environmental Sound Level:** \(String(format: "%.1f", environmental)) dB\n"
        }
        return markdown
    }

    private func workoutsListMarkdown(snapshot: ExportDataSnapshot, bullet: String, template: MarkdownTemplateConfig) -> String {
        var markdown = ""
        let subHeaderPrefix = String(repeating: "#", count: template.sectionHeaderLevel + 1)

        for (index, workout) in snapshot.workouts.enumerated() {
            markdown += "\n\(subHeaderPrefix) \(index + 1). \(workout.workoutTypeName)\n\n"
            markdown += "\(bullet) **Time:** \(snapshot.timeFormat.format(date: workout.startTime))\n"
            markdown += "\(bullet) **Duration:** \(formatDurationShort(workout.duration))\n"
            if let distance = workout.distance, distance > 0 {
                markdown += "\(bullet) **Distance:** \(snapshot.converter.formatDistance(distance))\n"
                if let rate = workout.paceOrSpeed(using: snapshot.converter) {
                    markdown += "\(bullet) **\(rate.label):** \(rate.value)\n"
                }
            }
            if let calories = workout.calories, calories > 0 {
                markdown += "\(bullet) **Calories:** \(Int(calories)) kcal\n"
            }
            if let avgHR = workout.avgHeartRate {
                markdown += "\(bullet) **Avg Heart Rate:** \(Int(avgHR.rounded())) bpm\n"
            }
            if let maxHR = workout.maxHeartRate {
                markdown += "\(bullet) **Max Heart Rate:** \(Int(maxHR.rounded())) bpm\n"
            }
            if let minHR = workout.minHeartRate {
                markdown += "\(bullet) **Min Heart Rate:** \(Int(minHR.rounded())) bpm\n"
            }
            if let cadence = workout.avgRunningCadence {
                markdown += "\(bullet) **Avg Cadence:** \(Int(cadence.rounded())) spm\n"
            }
            if let stride = workout.avgStrideLength {
                markdown += "\(bullet) **Avg Stride Length:** \(String(format: "%.2f", stride)) m\n"
            }
            if let gct = workout.avgGroundContactTime {
                markdown += "\(bullet) **Avg Ground Contact:** \(Int(gct.rounded())) ms\n"
            }
            if let vertOsc = workout.avgVerticalOscillation {
                markdown += "\(bullet) **Avg Vertical Oscillation:** \(String(format: "%.1f", vertOsc)) cm\n"
            }
            if let cyclingCadence = workout.avgCyclingCadence {
                markdown += "\(bullet) **Avg Cadence:** \(Int(cyclingCadence.rounded())) rpm\n"
            }
            if let avgPow = workout.avgPower {
                markdown += "\(bullet) **Avg Power:** \(Int(avgPow.rounded())) W\n"
            }
            if let maxPow = workout.maxPower {
                markdown += "\(bullet) **Max Power:** \(Int(maxPow.rounded())) W\n"
            }
            if let elevation = workout.elevationGainMeters {
                markdown += "\(bullet) **Elevation Gain:** \(formatElevation(elevation, converter: snapshot.converter))\n"
            }
            if !workout.route.isEmpty {
                markdown += "\(bullet) **GPS Route:** \(workout.route.count) points\n"
            }
            if !workout.laps.isEmpty {
                markdown += "\n\(bullet) **Laps:**\n\n"
                markdown += "| # | Distance | Time | Pace |\n"
                markdown += "|---|---|---|---|\n"
                for (i, lap) in workout.laps.enumerated() {
                    let distStr = lap.distanceMeters.map { snapshot.converter.formatDistance($0) } ?? "—"
                    let timeStr = formatLapTime(lap.duration)
                    let paceStr: String
                    if let d = lap.distanceMeters, d > 0 {
                        paceStr = snapshot.converter.formatPace(meters: d, duration: lap.duration) ?? "—"
                    } else {
                        paceStr = "—"
                    }
                    markdown += "| \(i + 1) | \(distStr) | \(timeStr) | \(paceStr) |\n"
                }
            }
            if !workout.splits.isEmpty {
                markdown += "\n\(bullet) **Splits:**\n\n"
                markdown += "| # | Time | Pace | Avg HR |\n"
                markdown += "|---|---|---|---|\n"
                for split in workout.splits {
                    let timeStr = formatLapTime(split.duration)
                    let paceStr = snapshot.converter.formatPace(meters: split.distanceMeters, duration: split.duration) ?? "—"
                    let hrStr = split.avgHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—"
                    markdown += "| \(split.index) | \(timeStr) | \(paceStr) | \(hrStr) |\n"
                }
            }
            // Time-series sample summary — full per-sample data lives in JSON.
            // Markdown gets a compact "metric: N samples" line per populated series.
            if !workout.timeSeries.isEmpty {
                let series = workout.timeSeries
                let entries: [(String, Int)] = [
                    ("Heart Rate",            series.heartRate.count),
                    ("Speed",                 series.speed.count),
                    ("Power",                 series.power.count),
                    ("Cadence",               series.cadence.count),
                    ("Stride Length",         series.strideLength.count),
                    ("Ground Contact",        series.groundContactTime.count),
                    ("Vertical Oscillation",  series.verticalOscillation.count),
                    ("Altitude",              series.altitude.count),
                ]
                for (label, count) in entries where count > 0 {
                    markdown += "\(bullet) **\(label) Samples:** \(count)\n"
                }
            }
        }

        return markdown
    }

    /// Renders a lap/split duration as "M:SS" (e.g. 360s → "6:00") for table cells.
    private func formatLapTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Renders an elevation in meters to a string in the user's preferred unit
    /// without converting to km/mi. e.g. 152 m → "152 m" / "499 ft".
    private func formatElevation(_ meters: Double, converter: UnitConverter) -> String {
        switch converter.preference {
        case .metric:
            return "\(Int(meters.rounded())) m"
        case .imperial:
            return "\(Int((meters * 3.28084).rounded())) ft"
        }
    }

    private func applyConditionalSection(in template: String, section: String, include: Bool) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: section)
        let pattern = "\\{\\{#\(escaped)\\}\\}([\\s\\S]*?)\\{\\{/\(escaped)\\}\\}"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return template
        }

        var output = template
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, options: [], range: range)

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: output) else { continue }

            if include, let innerRange = Range(match.range(at: 1), in: output) {
                let inner = String(output[innerRange])
                output.replaceSubrange(fullRange, with: inner)
            } else {
                output.replaceSubrange(fullRange, with: "")
            }
        }

        return output
    }
}
