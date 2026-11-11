import Foundation

/// Static onboarding examples, kept independent of the screen so structured text can be validated.
nonisolated enum SampleExportPreviewFormat: String, CaseIterable, Identifiable {
    case markdown
    case json
    case csv
    case obsidianBases

    var id: Self { self }

    var pickerTitle: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .csv: return "CSV"
        case .obsidianBases: return "Bases"
        }
    }

    var fileName: String {
        switch self {
        case .markdown: return "2026-06-19 Health.md"
        case .json: return "2026-06-19 Health.json"
        case .csv: return "2026-06-19 Health.csv"
        case .obsidianBases: return "2026-06-19 Health.md"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown, .obsidianBases: return "md"
        case .json: return "json"
        case .csv: return "csv"
        }
    }

    var subtitle: String {
        switch self {
        case .markdown: return "Readable daily note"
        case .json: return "Structured nested data"
        case .csv: return "Rows for spreadsheets"
        case .obsidianBases: return "Query-ready frontmatter"
        }
    }

    var icon: String {
        switch self {
        case .markdown, .obsidianBases: return "doc.text"
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        }
    }

    var content: String {
        switch self {
        case .markdown: return markdownContent
        case .json: return jsonContent
        case .csv: return csvContent
        case .obsidianBases: return obsidianBasesContent
        }
    }

    private var markdownContent: String {
        """
        ---
        schema: healthmd.health_data
        schema_version: \(HealthMdExportSchema.version)
        time_context:
          calendar_timezone: America/Los_Angeles
          timestamp_timezone: UTC
        date: 2026-06-19
        type: health-data
        active_calories: 624
        exercise_minutes: 42
        hrv_ms: 62.0
        resting_heart_rate: 58
        sleep_deep_hours: 1.30
        sleep_rem_hours: 1.87
        sleep_total_hours: 7.70
        sleep_bedtime: 10:44 PM
        sleep_wake: 6:32 AM
        steps: 8432
        walking_running_mi: 4.10
        workout_minutes: 35
        workouts: 1
        units:
          active_calories: kcal
          exercise_minutes: min
          hrv_ms: ms
          resting_heart_rate: bpm
          sleep_total_hours: hr
          steps: count
          walking_running_mi: mi
          workout_minutes: min
        ---

        # Health Data — 2026-06-19

        7h 42m sleep · 8,432 steps · 1 workout

        ## 😴 Sleep

        - **Total:** 7h 42m
        - **Bedtime:** 10:44 PM
        - **Wake:** 6:32 AM
        - **Deep:** 1h 18m
        - **REM:** 1h 52m
        - **Core:** 4h 12m
        - **Awake:** 18m

        <details>
        <summary>Sleep Stages Timeline (4 intervals)</summary>

        | Time | Stage | Duration |
        |------|-------|----------|
        | 10:44 PM | Core | 2h 10m |
        | 12:54 AM | Deep | 1h 18m |
        | 2:12 AM | REM | 1h 52m |
        | 4:04 AM | Core | 2h 02m |

        </details>

        ## 🏃 Activity

        - **Steps:** 8,432
        - **Active Calories:** 624 kcal
        - **Exercise:** 42 min
        - **Stand Hours:** 11
        - **Walking/Running Distance:** 4.10 mi

        ## ❤️ Heart

        - **Resting HR:** 58 bpm
        - **Average HR:** 74 bpm
        - **HRV:** 62.0 ms

        ## 💪 Workouts
        - **Outdoor Run** — 35m 12s, 3.2 mi, 312 kcal
          - Avg HR: 146 bpm
          - Max HR: 174 bpm
          - Pace: 11'00" /mi
        """
    }

    private var jsonContent: String {
        """
        {
          "schema": "healthmd.health_data",
          "schema_version": \(HealthMdExportSchema.version),
          "date": "2026-06-19",
          "type": "health-data",
          "time_context": {
            "calendar_timezone": "America/Los_Angeles",
            "timestamp_timezone": "UTC"
          },
          "unit_system": "metric",
          "units": {
            "active_calories": "kcal",
            "exercise_minutes": "min",
            "hrv_ms": "ms",
            "resting_heart_rate": "bpm",
            "sleep_total_hours": "hr",
            "steps": "count",
            "walking_running_mi": "mi"
          },
          "sleep": {
            "totalDuration": 27720,
            "totalDurationFormatted": "7h 42m",
            "bedtime": "10:44 PM",
            "wakeTime": "6:32 AM",
            "deepSleep": 4680,
            "deepSleepFormatted": "1h 18m",
            "remSleep": 6720,
            "remSleepFormatted": "1h 52m"
          },
          "activity": {
            "steps": 8432,
            "activeCalories": 624,
            "exerciseMinutes": 42,
            "walkingRunningDistanceKm": 6.60,
            "walkingRunningDistanceMi": 4.10
          },
          "heart": {
            "restingHeartRate": 58,
            "averageHeartRate": 74,
            "hrv": 62.0,
            "heartRateSamples": [
              { "timestamp": "2026-06-19T08:15:00Z", "value": 62 },
              { "timestamp": "2026-06-19T12:30:00Z", "value": 78 },
              { "timestamp": "2026-06-19T18:45:00Z", "value": 91 }
            ]
          },
          "workouts": [
            {
              "type": "Running",
              "sport": "running",
              "healthKitActivityType": "running",
              "healthKitActivityTypeRawValue": 37,
              "duration": 2112,
              "durationFormatted": "35m 12s",
              "distanceKm": 5.15,
              "distanceMi": 3.20,
              "activeCalories": 312,
              "avgHeartRate": 146,
              "maxHeartRate": 174,
              "avgPacePerMiFormatted": "11'00\\\" /mi"
            }
          ]
        }
        """
    }

    private var csvContent: String {
        """
        Date,Category,Metric,Value,Unit,Timestamp
        2026-06-19,Metadata,schema,healthmd.health_data,,
        2026-06-19,Metadata,schema_version,\(HealthMdExportSchema.version),,
        2026-06-19,Metadata,unit_system,metric,,
        2026-06-19,Metadata,time_context.calendar_timezone,America/Los_Angeles,,
        2026-06-19,Metadata,time_context.timestamp_timezone,UTC,,
        2026-06-19,Sleep,Total Duration,27720,seconds,
        2026-06-19,Sleep,Bedtime,10:44 PM,time,
        2026-06-19,Sleep,Wake Time,6:32 AM,time,
        2026-06-19,Sleep,Deep Sleep,4680,seconds,
        2026-06-19,Sleep,REM Sleep,6720,seconds,
        2026-06-19,Activity,Steps,8432,count,
        2026-06-19,Activity,Active Calories,624,kcal,
        2026-06-19,Activity,Exercise Minutes,42,minutes,
        2026-06-19,Activity,Walking Running Distance,6600,meters,
        2026-06-19,Heart,Resting Heart Rate,58,bpm,
        2026-06-19,Heart,Average Heart Rate,74,bpm,
        2026-06-19,Heart,HRV,62.0,ms,
        2026-06-19,Heart,Heart Rate Sample,62,bpm,2026-06-19T08:15:00Z
        2026-06-19,Heart,Heart Rate Sample,78,bpm,2026-06-19T12:30:00Z
        2026-06-19,Workouts,Workout Activity Type,Running,,2026-06-19T14:10:00Z
        2026-06-19,Workouts,Workout Sport,running,,2026-06-19T14:10:00Z
        2026-06-19,Workouts,HealthKit Activity Type,running,,2026-06-19T14:10:00Z
        2026-06-19,Workouts,HealthKit Activity Type Raw Value,37,,2026-06-19T14:10:00Z
        2026-06-19,Workouts,Running Duration,2112,seconds,
        2026-06-19,Workouts,Running Distance,5150,meters,
        2026-06-19,Workouts,Running Calories,312,kcal,
        2026-06-19,Workouts,Running Avg Heart Rate,146,bpm,
        """
    }

    private var obsidianBasesContent: String {
        """
        ---
        schema: healthmd.health_data
        schema_version: \(HealthMdExportSchema.version)
        time_context:
          calendar_timezone: America/Los_Angeles
          timestamp_timezone: UTC
        date: 2026-06-19
        type: health-data
        active_calories: 624
        exercise_minutes: 42
        hrv_ms: 62.0
        resting_heart_rate: 58
        sleep_deep_hours: 1.30
        sleep_rem_hours: 1.87
        sleep_total_hours: 7.70
        sleep_bedtime: 10:44 PM
        sleep_wake: 6:32 AM
        steps: 8432
        walking_running_mi: 4.10
        workout_minutes: 35
        workouts: 1
        workout_details:
          - workout: 1
            activity_type: "Running"
            sport: running
            healthkit_activity_type: running
            healthkit_activity_type_raw_value: 37
            start: 2026-06-19 07:10:00
            end: 2026-06-19 07:45:12
            duration_sec: 2112
            duration: "35:12"
            distance_m: 5150
            distance_km: 5.15
            distance_mi: 3.20
            active_energy_kcal: 312
            avg_heart_rate: 146
            max_heart_rate: 174
            avg_pace_per_mi: "11'00\\\" /mi"
            sample_counts:
              heart_rate: 840
              speed: 840
        units:
          active_calories: kcal
          exercise_minutes: min
          hrv_ms: ms
          resting_heart_rate: bpm
          sleep_total_hours: hr
          steps: count
          walking_running_mi: mi
          workout_minutes: min
        ---
        """
    }
}
