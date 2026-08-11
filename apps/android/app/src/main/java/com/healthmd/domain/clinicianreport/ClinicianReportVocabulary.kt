package com.healthmd.domain.clinicianreport

import com.healthmd.domain.model.WorkoutType
import java.util.Locale

/** Stable, renderer-neutral keys for the reviewed Clinician Report vocabulary. */
enum class ClinicianReportText(val resourceName: String) {
    TITLE("clinician_report_title"),
    ENTRY_SUBTITLE("clinician_report_entry_subtitle"),
    INTRO("clinician_report_intro"),
    PERIOD("clinician_report_period"),
    KEY_7_DAYS("clinician_report_7_days"),
    KEY_30_DAYS("clinician_report_30_days"),
    KEY_90_DAYS("clinician_report_90_days"),
    CUSTOM("clinician_report_custom"),
    SELECT_DATE("clinician_report_select_date"),
    START_DATE("clinician_report_start_date"),
    END_DATE("clinician_report_end_date"),
    METRICS("clinician_report_metrics"),
    DETAIL("clinician_report_detail"),
    SUMMARY_ONLY("clinician_report_summary_only"),
    SUMMARY_READINGS("clinician_report_summary_readings"),
    DISPLAY_NAME("clinician_report_display_name"),
    DISPLAY_NAME_HINT("clinician_report_display_name_hint"),
    PREVIEW("clinician_report_preview"),
    SELECT_METRIC("clinician_report_select_metric"),
    PREVIEW_HEADING("clinician_report_preview_heading"),
    GENERATE_PDF("clinician_report_generate_pdf"),
    SHARE_PDF("clinician_report_share_pdf"),
    SAVE_PDF("clinician_report_save_pdf"),
    SHARE_OR_SAVE_PDF("clinician_report_share_or_save_pdf"),
    PREPARING("clinician_report_preparing"),
    GENERATING("clinician_report_generating"),
    CLOSE("clinician_report_close"),
    SELECTED("clinician_report_selected"),
    NOT_SELECTED("clinician_report_not_selected"),
    METRIC_BLOOD_PRESSURE("clinician_report_metric_blood_pressure"),
    METRIC_RESTING_HEART_RATE("clinician_report_metric_resting_heart_rate"),
    METRIC_HEART_RATE("clinician_report_metric_heart_rate"),
    METRIC_WEIGHT("clinician_report_metric_weight"),
    METRIC_BLOOD_GLUCOSE("clinician_report_metric_blood_glucose"),
    METRIC_OXYGEN_SATURATION("clinician_report_metric_oxygen_saturation"),
    METRIC_RESPIRATORY_RATE("clinician_report_metric_respiratory_rate"),
    METRIC_BODY_TEMPERATURE("clinician_report_metric_body_temperature"),
    METRIC_SLEEP_DURATION("clinician_report_metric_sleep_duration"),
    METRIC_STEPS("clinician_report_metric_steps"),
    METRIC_WORKOUTS("clinician_report_metric_workouts"),
    DOCUMENT_TITLE("clinician_report_document_title"),
    NO_DATA("clinician_report_no_data"),
    DISCLAIMER("clinician_report_disclaimer"),
    ATTRIBUTION("clinician_report_attribution"),
    PRACTICE_LINE("clinician_report_practice_line"),
    MANUAL_ENTRY("clinician_report_manual_entry"),
    MANUAL_ENTRY_SOURCE("clinician_report_manual_entry_source"),
    FACT_READINGS("clinician_report_fact_readings"),
    FACT_AVAILABLE_VALUES("clinician_report_fact_available_values"),
    FACT_DAILY_VALUES("clinician_report_fact_daily_values"),
    FACT_DAYS_WITH_DATA("clinician_report_fact_days_with_data"),
    FACT_AVERAGE("clinician_report_fact_average"),
    FACT_MEDIAN("clinician_report_fact_median"),
    FACT_RANGE("clinician_report_fact_range"),
    FACT_MOST_RECENT("clinician_report_fact_most_recent"),
    FACT_FIRST("clinician_report_fact_first"),
    FACT_CHANGE("clinician_report_fact_change"),
    FACT_TOTAL("clinician_report_fact_total"),
    FACT_AVERAGE_DATA_DAYS("clinician_report_fact_average_data_days"),
    FACT_NIGHTS_WITH_DATA("clinician_report_fact_nights_with_data"),
    FACT_MEDIAN_SLEEP("clinician_report_fact_median_sleep"),
    FACT_SESSIONS("clinician_report_fact_sessions"),
    FACT_TOTAL_DURATION("clinician_report_fact_total_duration"),
    FACT_WORKOUT_TYPE("clinician_report_fact_workout_type"),
    TABLE_BLOOD_PRESSURE("clinician_report_table_blood_pressure"),
    TABLE_METRIC_READINGS("clinician_report_table_metric_readings"),
    TABLE_SLEEP("clinician_report_table_sleep"),
    TABLE_WORKOUTS("clinician_report_table_workouts"),
    COLUMN_DATE("clinician_report_column_date"),
    COLUMN_TIME("clinician_report_column_time"),
    COLUMN_SYSTOLIC("clinician_report_column_systolic"),
    COLUMN_DIASTOLIC("clinician_report_column_diastolic"),
    COLUMN_SOURCE("clinician_report_column_source"),
    COLUMN_VALUE("clinician_report_column_value"),
    COLUMN_WEIGHT("clinician_report_column_weight"),
    COLUMN_STEPS("clinician_report_column_steps"),
    COLUMN_NIGHT("clinician_report_column_night"),
    COLUMN_DURATION("clinician_report_column_duration"),
    COLUMN_TYPE("clinician_report_column_type"),
    VALUE_ON_DATE("clinician_report_value_on_date"),
    COVERAGE("clinician_report_coverage"),
    SOURCES("clinician_report_sources"),
    STEP_TOTAL("clinician_report_step_total"),
    STEP_AVERAGE("clinician_report_step_average"),
    DURATION_HOURS("clinician_report_duration_hours"),
    DURATION_MINUTES("clinician_report_duration_minutes"),
    DURATION_HOURS_MINUTES("clinician_report_duration_hours_minutes"),
    WORKOUT_BREAKDOWN_ITEM("clinician_report_workout_breakdown_item"),
    DETAIL_READINGS_COUNT("clinician_report_detail_readings_count"),
    METADATA_PERIOD("clinician_report_metadata_period"),
    METADATA_GENERATED("clinician_report_metadata_generated"),
    METADATA_TIMEZONE("clinician_report_metadata_timezone"),
    METADATA_PATIENT("clinician_report_metadata_patient"),
    AVAILABILITY_NOTE("clinician_report_availability_note"),
    ABOUT("clinician_report_about"),
    PAGE_FOOTER("clinician_report_page_footer"),
    WARNING_READ_FAILURE("clinician_report_warning_read_failure"),
    WARNING_SOURCE_FAILURE_DATE("clinician_report_warning_source_failure_date"),
    WARNING_APPLE_READ_FAILURE_DATE("clinician_report_warning_apple_read_failure_date"),
    WARNING_APPLE_SOURCE_FAILURE_DATE("clinician_report_warning_apple_source_failure_date"),
    WARNING_APPLE_INTEGRITY_DATE("clinician_report_warning_apple_integrity_date"),
    WARNING_APPLE_SUMMARY_FALLBACK("clinician_report_warning_apple_summary_fallback"),
    ERROR_PREPARE_ANDROID("clinician_report_error_prepare_android"),
    ERROR_PREPARE_APPLE("clinician_report_error_prepare_apple"),
    ERROR_PDF("clinician_report_error_pdf"),
    SAVED("clinician_report_saved"),
    ERROR_SAVE("clinician_report_error_save"),
    ERROR_OPEN_DESTINATION("clinician_report_error_open_destination"),
    ACCESSIBILITY_HINT("clinician_report_accessibility_hint"),
    WORKOUT_TYPE_RUNNING("clinician_report_workout_type_running"),
    WORKOUT_TYPE_WALKING("clinician_report_workout_type_walking"),
    WORKOUT_TYPE_CYCLING("clinician_report_workout_type_cycling"),
    WORKOUT_TYPE_SWIMMING("clinician_report_workout_type_swimming"),
    WORKOUT_TYPE_HIKING("clinician_report_workout_type_hiking"),
    WORKOUT_TYPE_YOGA("clinician_report_workout_type_yoga"),
    WORKOUT_TYPE_STRENGTH_TRAINING("clinician_report_workout_type_strength_training"),
    WORKOUT_TYPE_CORE_TRAINING("clinician_report_workout_type_core_training"),
    WORKOUT_TYPE_HIIT("clinician_report_workout_type_hiit"),
    WORKOUT_TYPE_ELLIPTICAL("clinician_report_workout_type_elliptical"),
    WORKOUT_TYPE_ROWING("clinician_report_workout_type_rowing"),
    WORKOUT_TYPE_STAIR_CLIMBING("clinician_report_workout_type_stair_climbing"),
    WORKOUT_TYPE_PILATES("clinician_report_workout_type_pilates"),
    WORKOUT_TYPE_DANCE("clinician_report_workout_type_dance"),
    WORKOUT_TYPE_COOLDOWN("clinician_report_workout_type_cooldown"),
    WORKOUT_TYPE_MIXED_CARDIO("clinician_report_workout_type_mixed_cardio"),
    WORKOUT_TYPE_PICKLEBALL("clinician_report_workout_type_pickleball"),
    WORKOUT_TYPE_TENNIS("clinician_report_workout_type_tennis"),
    WORKOUT_TYPE_BADMINTON("clinician_report_workout_type_badminton"),
    WORKOUT_TYPE_TABLE_TENNIS("clinician_report_workout_type_table_tennis"),
    WORKOUT_TYPE_GOLF("clinician_report_workout_type_golf"),
    WORKOUT_TYPE_SOCCER("clinician_report_workout_type_soccer"),
    WORKOUT_TYPE_BASKETBALL("clinician_report_workout_type_basketball"),
    WORKOUT_TYPE_BASEBALL("clinician_report_workout_type_baseball"),
    WORKOUT_TYPE_SOFTBALL("clinician_report_workout_type_softball"),
    WORKOUT_TYPE_VOLLEYBALL("clinician_report_workout_type_volleyball"),
    WORKOUT_TYPE_AMERICAN_FOOTBALL("clinician_report_workout_type_american_football"),
    WORKOUT_TYPE_RUGBY("clinician_report_workout_type_rugby"),
    WORKOUT_TYPE_HOCKEY("clinician_report_workout_type_hockey"),
    WORKOUT_TYPE_LACROSSE("clinician_report_workout_type_lacrosse"),
    WORKOUT_TYPE_SKATING("clinician_report_workout_type_skating"),
    WORKOUT_TYPE_SNOW_SPORTS("clinician_report_workout_type_snow_sports"),
    WORKOUT_TYPE_WATER_SPORTS("clinician_report_workout_type_water_sports"),
    WORKOUT_TYPE_WHEELCHAIR("clinician_report_workout_type_wheelchair"),
    WORKOUT_TYPE_MARTIAL_ARTS("clinician_report_workout_type_martial_arts"),
    WORKOUT_TYPE_BOXING("clinician_report_workout_type_boxing"),
    WORKOUT_TYPE_KICKBOXING("clinician_report_workout_type_kickboxing"),
    WORKOUT_TYPE_WRESTLING("clinician_report_workout_type_wrestling"),
    WORKOUT_TYPE_CLIMBING("clinician_report_workout_type_climbing"),
    WORKOUT_TYPE_JUMP_ROPE("clinician_report_workout_type_jump_rope"),
    WORKOUT_TYPE_FLEXIBILITY("clinician_report_workout_type_flexibility"),
    WORKOUT_TYPE_OTHER("clinician_report_workout_type_other"),
    UNIT_RESPIRATORY_RATE("clinician_report_unit_respiratory_rate"),
}

/** One resolved supported locale drives capture warnings, normalization, preview and PDF. */
interface ClinicianReportVocabulary {
    val locale: Locale
    val languageTag: String
    val paperRegionCode: String?
    val isRtl: Boolean
    fun text(key: ClinicianReportText, vararg values: String): String
}

interface ClinicianReportVocabularyFactory {
    fun current(): ClinicianReportVocabulary
    fun forLocale(requested: Locale): ClinicianReportVocabulary
}

fun ClinicianReportVocabulary.metricName(metric: ReportMetric): String = text(when (metric) {
    ReportMetric.BLOOD_PRESSURE -> ClinicianReportText.METRIC_BLOOD_PRESSURE
    ReportMetric.RESTING_HEART_RATE -> ClinicianReportText.METRIC_RESTING_HEART_RATE
    ReportMetric.HEART_RATE -> ClinicianReportText.METRIC_HEART_RATE
    ReportMetric.WEIGHT -> ClinicianReportText.METRIC_WEIGHT
    ReportMetric.BLOOD_GLUCOSE -> ClinicianReportText.METRIC_BLOOD_GLUCOSE
    ReportMetric.OXYGEN_SATURATION -> ClinicianReportText.METRIC_OXYGEN_SATURATION
    ReportMetric.RESPIRATORY_RATE -> ClinicianReportText.METRIC_RESPIRATORY_RATE
    ReportMetric.BODY_TEMPERATURE -> ClinicianReportText.METRIC_BODY_TEMPERATURE
    ReportMetric.SLEEP_DURATION -> ClinicianReportText.METRIC_SLEEP_DURATION
    ReportMetric.STEPS -> ClinicianReportText.METRIC_STEPS
    ReportMetric.WORKOUTS -> ClinicianReportText.METRIC_WORKOUTS
})

fun ClinicianReportVocabulary.workoutName(type: WorkoutType): String = text(when (type) {
    WorkoutType.RUNNING -> ClinicianReportText.WORKOUT_TYPE_RUNNING
    WorkoutType.WALKING -> ClinicianReportText.WORKOUT_TYPE_WALKING
    WorkoutType.CYCLING -> ClinicianReportText.WORKOUT_TYPE_CYCLING
    WorkoutType.SWIMMING -> ClinicianReportText.WORKOUT_TYPE_SWIMMING
    WorkoutType.HIKING -> ClinicianReportText.WORKOUT_TYPE_HIKING
    WorkoutType.YOGA -> ClinicianReportText.WORKOUT_TYPE_YOGA
    WorkoutType.STRENGTH_TRAINING -> ClinicianReportText.WORKOUT_TYPE_STRENGTH_TRAINING
    WorkoutType.CORE_TRAINING -> ClinicianReportText.WORKOUT_TYPE_CORE_TRAINING
    WorkoutType.HIIT -> ClinicianReportText.WORKOUT_TYPE_HIIT
    WorkoutType.ELLIPTICAL -> ClinicianReportText.WORKOUT_TYPE_ELLIPTICAL
    WorkoutType.ROWING -> ClinicianReportText.WORKOUT_TYPE_ROWING
    WorkoutType.STAIR_CLIMBING -> ClinicianReportText.WORKOUT_TYPE_STAIR_CLIMBING
    WorkoutType.PILATES -> ClinicianReportText.WORKOUT_TYPE_PILATES
    WorkoutType.DANCE -> ClinicianReportText.WORKOUT_TYPE_DANCE
    WorkoutType.COOLDOWN -> ClinicianReportText.WORKOUT_TYPE_COOLDOWN
    WorkoutType.MIXED_CARDIO -> ClinicianReportText.WORKOUT_TYPE_MIXED_CARDIO
    WorkoutType.PICKLEBALL -> ClinicianReportText.WORKOUT_TYPE_PICKLEBALL
    WorkoutType.TENNIS -> ClinicianReportText.WORKOUT_TYPE_TENNIS
    WorkoutType.BADMINTON -> ClinicianReportText.WORKOUT_TYPE_BADMINTON
    WorkoutType.TABLE_TENNIS -> ClinicianReportText.WORKOUT_TYPE_TABLE_TENNIS
    WorkoutType.GOLF -> ClinicianReportText.WORKOUT_TYPE_GOLF
    WorkoutType.SOCCER -> ClinicianReportText.WORKOUT_TYPE_SOCCER
    WorkoutType.BASKETBALL -> ClinicianReportText.WORKOUT_TYPE_BASKETBALL
    WorkoutType.BASEBALL -> ClinicianReportText.WORKOUT_TYPE_BASEBALL
    WorkoutType.SOFTBALL -> ClinicianReportText.WORKOUT_TYPE_SOFTBALL
    WorkoutType.VOLLEYBALL -> ClinicianReportText.WORKOUT_TYPE_VOLLEYBALL
    WorkoutType.AMERICAN_FOOTBALL -> ClinicianReportText.WORKOUT_TYPE_AMERICAN_FOOTBALL
    WorkoutType.RUGBY -> ClinicianReportText.WORKOUT_TYPE_RUGBY
    WorkoutType.HOCKEY -> ClinicianReportText.WORKOUT_TYPE_HOCKEY
    WorkoutType.LACROSSE -> ClinicianReportText.WORKOUT_TYPE_LACROSSE
    WorkoutType.SKATING -> ClinicianReportText.WORKOUT_TYPE_SKATING
    WorkoutType.SNOW_SPORTS -> ClinicianReportText.WORKOUT_TYPE_SNOW_SPORTS
    WorkoutType.WATER_SPORTS -> ClinicianReportText.WORKOUT_TYPE_WATER_SPORTS
    WorkoutType.WHEELCHAIR -> ClinicianReportText.WORKOUT_TYPE_WHEELCHAIR
    WorkoutType.MARTIAL_ARTS -> ClinicianReportText.WORKOUT_TYPE_MARTIAL_ARTS
    WorkoutType.BOXING -> ClinicianReportText.WORKOUT_TYPE_BOXING
    WorkoutType.KICKBOXING -> ClinicianReportText.WORKOUT_TYPE_KICKBOXING
    WorkoutType.WRESTLING -> ClinicianReportText.WORKOUT_TYPE_WRESTLING
    WorkoutType.CLIMBING -> ClinicianReportText.WORKOUT_TYPE_CLIMBING
    WorkoutType.JUMP_ROPE -> ClinicianReportText.WORKOUT_TYPE_JUMP_ROPE
    WorkoutType.FLEXIBILITY -> ClinicianReportText.WORKOUT_TYPE_FLEXIBILITY
    WorkoutType.OTHER -> ClinicianReportText.WORKOUT_TYPE_OTHER
})
