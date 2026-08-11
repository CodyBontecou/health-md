import Foundation

/// A locale-pinned, resource-backed vocabulary for the complete Clinician Report workflow.
/// The reviewed stable keys are validated by scripts/validate-clinician-report-localizations.py.
nonisolated struct ClinicianReportCopy: Equatable, Sendable {
    enum Key: String, CaseIterable, Sendable {
        case title = "clinician_report_title"
        case entry_subtitle = "clinician_report_entry_subtitle"
        case intro = "clinician_report_intro"
        case period = "clinician_report_period"
        case days_7 = "clinician_report_7_days"
        case days_30 = "clinician_report_30_days"
        case days_90 = "clinician_report_90_days"
        case custom = "clinician_report_custom"
        case select_date = "clinician_report_select_date"
        case start_date = "clinician_report_start_date"
        case end_date = "clinician_report_end_date"
        case metrics = "clinician_report_metrics"
        case detail = "clinician_report_detail"
        case summary_only = "clinician_report_summary_only"
        case summary_readings = "clinician_report_summary_readings"
        case display_name = "clinician_report_display_name"
        case display_name_hint = "clinician_report_display_name_hint"
        case preview = "clinician_report_preview"
        case select_metric = "clinician_report_select_metric"
        case recommended = "clinician_report_recommended"
        case select_all = "clinician_report_select_all"
        case clear = "clinician_report_clear"
        case selected_count = "clinician_report_selected_count"
        case summary_description = "clinician_report_summary_description"
        case readings_description = "clinician_report_readings_description"
        case edit = "clinician_report_edit"
        case data_available_count = "clinician_report_data_available_count"
        case no_reportable_data = "clinician_report_no_reportable_data"
        case unavailable_measurements = "clinician_report_unavailable_measurements"
        case summary = "clinician_report_summary"
        case preview_heading = "clinician_report_preview_heading"
        case generate_pdf = "clinician_report_generate_pdf"
        case share_pdf = "clinician_report_share_pdf"
        case save_pdf = "clinician_report_save_pdf"
        case share_or_save_pdf = "clinician_report_share_or_save_pdf"
        case preparing = "clinician_report_preparing"
        case generating = "clinician_report_generating"
        case close = "clinician_report_close"
        case selected = "clinician_report_selected"
        case not_selected = "clinician_report_not_selected"
        case metric_blood_pressure = "clinician_report_metric_blood_pressure"
        case metric_resting_heart_rate = "clinician_report_metric_resting_heart_rate"
        case metric_heart_rate = "clinician_report_metric_heart_rate"
        case metric_weight = "clinician_report_metric_weight"
        case metric_blood_glucose = "clinician_report_metric_blood_glucose"
        case metric_oxygen_saturation = "clinician_report_metric_oxygen_saturation"
        case metric_respiratory_rate = "clinician_report_metric_respiratory_rate"
        case metric_body_temperature = "clinician_report_metric_body_temperature"
        case metric_sleep_duration = "clinician_report_metric_sleep_duration"
        case metric_steps = "clinician_report_metric_steps"
        case metric_workouts = "clinician_report_metric_workouts"
        case document_title = "clinician_report_document_title"
        case no_data = "clinician_report_no_data"
        case disclaimer = "clinician_report_disclaimer"
        case attribution = "clinician_report_attribution"
        case practice_line = "clinician_report_practice_line"
        case manual_entry = "clinician_report_manual_entry"
        case manual_entry_source = "clinician_report_manual_entry_source"
        case fact_readings = "clinician_report_fact_readings"
        case fact_available_values = "clinician_report_fact_available_values"
        case fact_daily_values = "clinician_report_fact_daily_values"
        case fact_days_with_data = "clinician_report_fact_days_with_data"
        case fact_average = "clinician_report_fact_average"
        case fact_median = "clinician_report_fact_median"
        case fact_range = "clinician_report_fact_range"
        case fact_most_recent = "clinician_report_fact_most_recent"
        case fact_first = "clinician_report_fact_first"
        case fact_change = "clinician_report_fact_change"
        case fact_total = "clinician_report_fact_total"
        case fact_average_data_days = "clinician_report_fact_average_data_days"
        case fact_nights_with_data = "clinician_report_fact_nights_with_data"
        case fact_median_sleep = "clinician_report_fact_median_sleep"
        case fact_sessions = "clinician_report_fact_sessions"
        case fact_total_duration = "clinician_report_fact_total_duration"
        case fact_workout_type = "clinician_report_fact_workout_type"
        case table_blood_pressure = "clinician_report_table_blood_pressure"
        case table_metric_readings = "clinician_report_table_metric_readings"
        case table_sleep = "clinician_report_table_sleep"
        case table_workouts = "clinician_report_table_workouts"
        case column_date = "clinician_report_column_date"
        case column_time = "clinician_report_column_time"
        case column_systolic = "clinician_report_column_systolic"
        case column_diastolic = "clinician_report_column_diastolic"
        case column_source = "clinician_report_column_source"
        case column_value = "clinician_report_column_value"
        case column_weight = "clinician_report_column_weight"
        case column_steps = "clinician_report_column_steps"
        case column_night = "clinician_report_column_night"
        case column_duration = "clinician_report_column_duration"
        case column_type = "clinician_report_column_type"
        case value_on_date = "clinician_report_value_on_date"
        case coverage = "clinician_report_coverage"
        case sources = "clinician_report_sources"
        case step_total = "clinician_report_step_total"
        case step_average = "clinician_report_step_average"
        case duration_hours = "clinician_report_duration_hours"
        case duration_minutes = "clinician_report_duration_minutes"
        case duration_hours_minutes = "clinician_report_duration_hours_minutes"
        case workout_breakdown_item = "clinician_report_workout_breakdown_item"
        case detail_readings_count = "clinician_report_detail_readings_count"
        case metadata_period = "clinician_report_metadata_period"
        case metadata_generated = "clinician_report_metadata_generated"
        case metadata_timezone = "clinician_report_metadata_timezone"
        case metadata_patient = "clinician_report_metadata_patient"
        case availability_note = "clinician_report_availability_note"
        case about = "clinician_report_about"
        case page_footer = "clinician_report_page_footer"
        case warning_read_failure = "clinician_report_warning_read_failure"
        case warning_source_failure_date = "clinician_report_warning_source_failure_date"
        case warning_apple_read_failure_date = "clinician_report_warning_apple_read_failure_date"
        case warning_apple_source_failure_date = "clinician_report_warning_apple_source_failure_date"
        case warning_apple_integrity_date = "clinician_report_warning_apple_integrity_date"
        case warning_apple_summary_fallback = "clinician_report_warning_apple_summary_fallback"
        case error_prepare_android = "clinician_report_error_prepare_android"
        case error_prepare_apple = "clinician_report_error_prepare_apple"
        case error_pdf = "clinician_report_error_pdf"
        case saved = "clinician_report_saved"
        case error_save = "clinician_report_error_save"
        case error_open_destination = "clinician_report_error_open_destination"
        case workout_type_americanFootball = "clinician_report_workout_type_americanFootball"
        case workout_type_archery = "clinician_report_workout_type_archery"
        case workout_type_australianFootball = "clinician_report_workout_type_australianFootball"
        case workout_type_badminton = "clinician_report_workout_type_badminton"
        case workout_type_baseball = "clinician_report_workout_type_baseball"
        case workout_type_basketball = "clinician_report_workout_type_basketball"
        case workout_type_bowling = "clinician_report_workout_type_bowling"
        case workout_type_boxing = "clinician_report_workout_type_boxing"
        case workout_type_climbing = "clinician_report_workout_type_climbing"
        case workout_type_cricket = "clinician_report_workout_type_cricket"
        case workout_type_crossTraining = "clinician_report_workout_type_crossTraining"
        case workout_type_curling = "clinician_report_workout_type_curling"
        case workout_type_cycling = "clinician_report_workout_type_cycling"
        case workout_type_dance = "clinician_report_workout_type_dance"
        case workout_type_danceInspiredTraining = "clinician_report_workout_type_danceInspiredTraining"
        case workout_type_elliptical = "clinician_report_workout_type_elliptical"
        case workout_type_equestrianSports = "clinician_report_workout_type_equestrianSports"
        case workout_type_fencing = "clinician_report_workout_type_fencing"
        case workout_type_fishing = "clinician_report_workout_type_fishing"
        case workout_type_functionalStrengthTraining = "clinician_report_workout_type_functionalStrengthTraining"
        case workout_type_golf = "clinician_report_workout_type_golf"
        case workout_type_gymnastics = "clinician_report_workout_type_gymnastics"
        case workout_type_handball = "clinician_report_workout_type_handball"
        case workout_type_hiking = "clinician_report_workout_type_hiking"
        case workout_type_hockey = "clinician_report_workout_type_hockey"
        case workout_type_hunting = "clinician_report_workout_type_hunting"
        case workout_type_lacrosse = "clinician_report_workout_type_lacrosse"
        case workout_type_martialArts = "clinician_report_workout_type_martialArts"
        case workout_type_mindAndBody = "clinician_report_workout_type_mindAndBody"
        case workout_type_mixedMetabolicCardioTraining = "clinician_report_workout_type_mixedMetabolicCardioTraining"
        case workout_type_paddleSports = "clinician_report_workout_type_paddleSports"
        case workout_type_play = "clinician_report_workout_type_play"
        case workout_type_rolling = "clinician_report_workout_type_rolling"
        case workout_type_racquetball = "clinician_report_workout_type_racquetball"
        case workout_type_rowing = "clinician_report_workout_type_rowing"
        case workout_type_rugby = "clinician_report_workout_type_rugby"
        case workout_type_running = "clinician_report_workout_type_running"
        case workout_type_sailing = "clinician_report_workout_type_sailing"
        case workout_type_skatingSports = "clinician_report_workout_type_skatingSports"
        case workout_type_snowSports = "clinician_report_workout_type_snowSports"
        case workout_type_soccer = "clinician_report_workout_type_soccer"
        case workout_type_softball = "clinician_report_workout_type_softball"
        case workout_type_squash = "clinician_report_workout_type_squash"
        case workout_type_stairClimbing = "clinician_report_workout_type_stairClimbing"
        case workout_type_surfingSports = "clinician_report_workout_type_surfingSports"
        case workout_type_swimming = "clinician_report_workout_type_swimming"
        case workout_type_tableTennis = "clinician_report_workout_type_tableTennis"
        case workout_type_tennis = "clinician_report_workout_type_tennis"
        case workout_type_trackAndField = "clinician_report_workout_type_trackAndField"
        case workout_type_traditionalStrengthTraining = "clinician_report_workout_type_traditionalStrengthTraining"
        case workout_type_volleyball = "clinician_report_workout_type_volleyball"
        case workout_type_walking = "clinician_report_workout_type_walking"
        case workout_type_waterFitness = "clinician_report_workout_type_waterFitness"
        case workout_type_waterPolo = "clinician_report_workout_type_waterPolo"
        case workout_type_waterSports = "clinician_report_workout_type_waterSports"
        case workout_type_wrestling = "clinician_report_workout_type_wrestling"
        case workout_type_yoga = "clinician_report_workout_type_yoga"
        case workout_type_barre = "clinician_report_workout_type_barre"
        case workout_type_coreTraining = "clinician_report_workout_type_coreTraining"
        case workout_type_crossCountrySkiing = "clinician_report_workout_type_crossCountrySkiing"
        case workout_type_downhillSkiing = "clinician_report_workout_type_downhillSkiing"
        case workout_type_flexibility = "clinician_report_workout_type_flexibility"
        case workout_type_highIntensityIntervalTraining = "clinician_report_workout_type_highIntensityIntervalTraining"
        case workout_type_jumpRope = "clinician_report_workout_type_jumpRope"
        case workout_type_kickboxing = "clinician_report_workout_type_kickboxing"
        case workout_type_pilates = "clinician_report_workout_type_pilates"
        case workout_type_snowboarding = "clinician_report_workout_type_snowboarding"
        case workout_type_stairs = "clinician_report_workout_type_stairs"
        case workout_type_stepTraining = "clinician_report_workout_type_stepTraining"
        case workout_type_wheelchairWalkPace = "clinician_report_workout_type_wheelchairWalkPace"
        case workout_type_wheelchairRunPace = "clinician_report_workout_type_wheelchairRunPace"
        case workout_type_taiChi = "clinician_report_workout_type_taiChi"
        case workout_type_mixedCardio = "clinician_report_workout_type_mixedCardio"
        case workout_type_handCycling = "clinician_report_workout_type_handCycling"
        case workout_type_discSports = "clinician_report_workout_type_discSports"
        case workout_type_fitnessGaming = "clinician_report_workout_type_fitnessGaming"
        case workout_type_cardioDance = "clinician_report_workout_type_cardioDance"
        case workout_type_socialDance = "clinician_report_workout_type_socialDance"
        case workout_type_pickleball = "clinician_report_workout_type_pickleball"
        case workout_type_cooldown = "clinician_report_workout_type_cooldown"
        case workout_type_swimBikeRun = "clinician_report_workout_type_swimBikeRun"
        case workout_type_transition = "clinician_report_workout_type_transition"
        case workout_type_underwaterDiving = "clinician_report_workout_type_underwaterDiving"
        case workout_type_other = "clinician_report_workout_type_other"
        case unit_respiratory_rate = "clinician_report_unit_respiratory_rate"
        case accessibility_hint = "clinician_report_accessibility_hint"
    }

    private static let supportedLocalizations = [
        "en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"
    ]

    /// The actual resource localization used for every string and formatter in this report.
    /// Unsupported requests intentionally resolve to English rather than merely tagging an
    /// English fallback with the requested language.
    let localeIdentifier: String
    let locale: Locale
    /// Preserves the requested region for physical paper selection without mislabelling
    /// the resolved document language (for example, en-US content still resolves to en).
    let paperRegionCode: String?
    private let localizationBundlePath: String?

    init(locale requestedLocale: Locale = .current, bundle: Bundle = .main) {
        let resolved = Self.resolveLocalization(for: requestedLocale)
        localeIdentifier = resolved
        locale = Locale(identifier: resolved)
        paperRegionCode = requestedLocale.region?.identifier.uppercased()
        localizationBundlePath = bundle.path(forResource: resolved, ofType: "lproj")
    }

    var languageTag: String { localeIdentifier }

    private static func resolveLocalization(for locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier.lowercased()
        let script = locale.language.script?.identifier.lowercased()
        let region = locale.region?.identifier.uppercased()
        if let exact = supportedLocalizations.first(where: {
            $0.caseInsensitiveCompare(locale.identifier.replacingOccurrences(of: "_", with: "-")) == .orderedSame
        }) {
            return exact
        }
        if language == "pt" { return "pt-BR" }
        if language == "zh" {
            if script == "hans" || (script == nil && (region == nil || region == "CN" || region == "SG")) {
                return "zh-Hans"
            }
            return "en"
        }
        if let language, supportedLocalizations.contains(language) { return language }
        return "en"
    }

    func string(_ key: Key) -> String {
        let bundle = localizationBundlePath.flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key.rawValue, value: nil, table: "Localizable")
    }

    /// Substitutes the reviewed positional tokens without passing localized text
    /// through a printf parser. Apple string catalogs require `%n$@` for string
    /// arguments, while the cross-platform manifest uses `%n$s`.
    func format(_ key: Key, _ values: [String]) -> String {
        var result = string(key)
        for (offset, value) in values.enumerated().reversed() {
            let position = offset + 1
            result = result.replacingOccurrences(of: "%\(position)$@", with: value)
            result = result.replacingOccurrences(of: "%\(position)$s", with: value)
            result = result.replacingOccurrences(of: "%\(position)$d", with: value)
        }
        return result
    }

    func format(_ key: Key, _ values: String...) -> String { format(key, values) }

    func workoutType(_ type: WorkoutType) -> String {
        guard let key = Key(rawValue: "clinician_report_workout_type_\(type.rawValue)") else {
            assertionFailure("Missing reviewed clinician report workout localization for \(type.rawValue)")
            return string(.workout_type_other)
        }
        return string(key)
    }

    static let practiceURL: String? = "healthmd.app/practice"

    var practiceLine: String? {
        Self.practiceURL.map { format(.practice_line, $0) }
    }
}
