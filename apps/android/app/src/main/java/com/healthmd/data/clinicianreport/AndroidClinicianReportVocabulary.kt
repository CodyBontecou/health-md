package com.healthmd.data.clinicianreport

import android.content.Context
import android.content.res.Configuration
import android.text.TextUtils
import android.view.View
import com.healthmd.R
import com.healthmd.domain.clinicianreport.ClinicianReportText
import com.healthmd.domain.clinicianreport.ClinicianReportVocabulary
import com.healthmd.domain.clinicianreport.ClinicianReportVocabularyFactory
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AndroidClinicianReportVocabularyFactory @Inject constructor(
    @ApplicationContext private val applicationContext: Context,
) : ClinicianReportVocabularyFactory {
    override fun current(): ClinicianReportVocabulary = forLocale(
        applicationContext.resources.configuration.locales[0] ?: Locale.ENGLISH,
    )

    override fun forLocale(requested: Locale): ClinicianReportVocabulary {
        val resolved = resolve(requested)
        val configuration = Configuration(applicationContext.resources.configuration).apply { setLocale(resolved) }
        val localizedContext = applicationContext.createConfigurationContext(configuration)
        return AndroidClinicianReportVocabulary(
            context = localizedContext,
            locale = resolved,
            languageTag = canonicalTag(resolved),
            paperRegionCode = requested.country.takeIf(String::isNotBlank)?.uppercase(Locale.ROOT),
            isRtl = TextUtils.getLayoutDirectionFromLocale(resolved) == View.LAYOUT_DIRECTION_RTL,
        )
    }

    private fun resolve(requested: Locale): Locale {
        val language = requested.language.lowercase(Locale.ROOT)
        val script = requested.script.lowercase(Locale.ROOT)
        val region = requested.country.uppercase(Locale.ROOT)
        val tag = when (language) {
            "ar", "bn", "de", "es", "fr", "hi", "ja", "kk", "nl", "ro", "ru", "uk" -> language
            "pt" -> "pt-BR"
            "pa" -> if (script.isEmpty() || script == "guru") "pa-Guru" else "en"
            "zh" -> if (script == "hans" || (script.isEmpty() && region in setOf("", "CN", "SG"))) "zh-Hans" else "en"
            else -> "en"
        }
        return Locale.forLanguageTag(tag)
    }

    private fun canonicalTag(locale: Locale): String = when (locale.language) {
        "pt" -> "pt-BR"
        "pa" -> "pa-Guru"
        "zh" -> "zh-Hans"
        else -> locale.language.ifBlank { "en" }
    }
}

private class AndroidClinicianReportVocabulary(
    private val context: Context,
    override val locale: Locale,
    override val languageTag: String,
    override val paperRegionCode: String?,
    override val isRtl: Boolean,
) : ClinicianReportVocabulary {
    override fun text(key: ClinicianReportText, vararg values: String): String {
        var result = context.getString(resourceId(key))
        values.indices.reversed().forEach { offset ->
            val position = offset + 1
            result = result.replace("%${position}\$s", values[offset])
            result = result.replace("%${position}\$d", values[offset])
        }
        return result
    }

    private fun resourceId(key: ClinicianReportText): Int = when (key) {
        ClinicianReportText.TITLE -> R.string.clinician_report_title
        ClinicianReportText.ENTRY_SUBTITLE -> R.string.clinician_report_entry_subtitle
        ClinicianReportText.INTRO -> R.string.clinician_report_intro
        ClinicianReportText.PERIOD -> R.string.clinician_report_period
        ClinicianReportText.KEY_7_DAYS -> R.string.clinician_report_7_days
        ClinicianReportText.KEY_30_DAYS -> R.string.clinician_report_30_days
        ClinicianReportText.KEY_90_DAYS -> R.string.clinician_report_90_days
        ClinicianReportText.CUSTOM -> R.string.clinician_report_custom
        ClinicianReportText.SELECT_DATE -> R.string.clinician_report_select_date
        ClinicianReportText.START_DATE -> R.string.clinician_report_start_date
        ClinicianReportText.END_DATE -> R.string.clinician_report_end_date
        ClinicianReportText.METRICS -> R.string.clinician_report_metrics
        ClinicianReportText.DETAIL -> R.string.clinician_report_detail
        ClinicianReportText.SUMMARY_ONLY -> R.string.clinician_report_summary_only
        ClinicianReportText.SUMMARY_READINGS -> R.string.clinician_report_summary_readings
        ClinicianReportText.DISPLAY_NAME -> R.string.clinician_report_display_name
        ClinicianReportText.DISPLAY_NAME_HINT -> R.string.clinician_report_display_name_hint
        ClinicianReportText.PREVIEW -> R.string.clinician_report_preview
        ClinicianReportText.SELECT_METRIC -> R.string.clinician_report_select_metric
        ClinicianReportText.PREVIEW_HEADING -> R.string.clinician_report_preview_heading
        ClinicianReportText.GENERATE_PDF -> R.string.clinician_report_generate_pdf
        ClinicianReportText.SHARE_PDF -> R.string.clinician_report_share_pdf
        ClinicianReportText.SAVE_PDF -> R.string.clinician_report_save_pdf
        ClinicianReportText.SHARE_OR_SAVE_PDF -> R.string.clinician_report_share_or_save_pdf
        ClinicianReportText.PREPARING -> R.string.clinician_report_preparing
        ClinicianReportText.GENERATING -> R.string.clinician_report_generating
        ClinicianReportText.CLOSE -> R.string.clinician_report_close
        ClinicianReportText.SELECTED -> R.string.clinician_report_selected
        ClinicianReportText.NOT_SELECTED -> R.string.clinician_report_not_selected
        ClinicianReportText.METRIC_BLOOD_PRESSURE -> R.string.clinician_report_metric_blood_pressure
        ClinicianReportText.METRIC_RESTING_HEART_RATE -> R.string.clinician_report_metric_resting_heart_rate
        ClinicianReportText.METRIC_HEART_RATE -> R.string.clinician_report_metric_heart_rate
        ClinicianReportText.METRIC_WEIGHT -> R.string.clinician_report_metric_weight
        ClinicianReportText.METRIC_BLOOD_GLUCOSE -> R.string.clinician_report_metric_blood_glucose
        ClinicianReportText.METRIC_OXYGEN_SATURATION -> R.string.clinician_report_metric_oxygen_saturation
        ClinicianReportText.METRIC_RESPIRATORY_RATE -> R.string.clinician_report_metric_respiratory_rate
        ClinicianReportText.METRIC_BODY_TEMPERATURE -> R.string.clinician_report_metric_body_temperature
        ClinicianReportText.METRIC_SLEEP_DURATION -> R.string.clinician_report_metric_sleep_duration
        ClinicianReportText.METRIC_STEPS -> R.string.clinician_report_metric_steps
        ClinicianReportText.METRIC_WORKOUTS -> R.string.clinician_report_metric_workouts
        ClinicianReportText.DOCUMENT_TITLE -> R.string.clinician_report_document_title
        ClinicianReportText.NO_DATA -> R.string.clinician_report_no_data
        ClinicianReportText.DISCLAIMER -> R.string.clinician_report_disclaimer
        ClinicianReportText.ATTRIBUTION -> R.string.clinician_report_attribution
        ClinicianReportText.PRACTICE_LINE -> R.string.clinician_report_practice_line
        ClinicianReportText.MANUAL_ENTRY -> R.string.clinician_report_manual_entry
        ClinicianReportText.MANUAL_ENTRY_SOURCE -> R.string.clinician_report_manual_entry_source
        ClinicianReportText.FACT_READINGS -> R.string.clinician_report_fact_readings
        ClinicianReportText.FACT_AVAILABLE_VALUES -> R.string.clinician_report_fact_available_values
        ClinicianReportText.FACT_DAILY_VALUES -> R.string.clinician_report_fact_daily_values
        ClinicianReportText.FACT_DAYS_WITH_DATA -> R.string.clinician_report_fact_days_with_data
        ClinicianReportText.FACT_AVERAGE -> R.string.clinician_report_fact_average
        ClinicianReportText.FACT_MEDIAN -> R.string.clinician_report_fact_median
        ClinicianReportText.FACT_RANGE -> R.string.clinician_report_fact_range
        ClinicianReportText.FACT_MOST_RECENT -> R.string.clinician_report_fact_most_recent
        ClinicianReportText.FACT_FIRST -> R.string.clinician_report_fact_first
        ClinicianReportText.FACT_CHANGE -> R.string.clinician_report_fact_change
        ClinicianReportText.FACT_TOTAL -> R.string.clinician_report_fact_total
        ClinicianReportText.FACT_AVERAGE_DATA_DAYS -> R.string.clinician_report_fact_average_data_days
        ClinicianReportText.FACT_NIGHTS_WITH_DATA -> R.string.clinician_report_fact_nights_with_data
        ClinicianReportText.FACT_MEDIAN_SLEEP -> R.string.clinician_report_fact_median_sleep
        ClinicianReportText.FACT_SESSIONS -> R.string.clinician_report_fact_sessions
        ClinicianReportText.FACT_TOTAL_DURATION -> R.string.clinician_report_fact_total_duration
        ClinicianReportText.FACT_WORKOUT_TYPE -> R.string.clinician_report_fact_workout_type
        ClinicianReportText.TABLE_BLOOD_PRESSURE -> R.string.clinician_report_table_blood_pressure
        ClinicianReportText.TABLE_METRIC_READINGS -> R.string.clinician_report_table_metric_readings
        ClinicianReportText.TABLE_SLEEP -> R.string.clinician_report_table_sleep
        ClinicianReportText.TABLE_WORKOUTS -> R.string.clinician_report_table_workouts
        ClinicianReportText.COLUMN_DATE -> R.string.clinician_report_column_date
        ClinicianReportText.COLUMN_TIME -> R.string.clinician_report_column_time
        ClinicianReportText.COLUMN_SYSTOLIC -> R.string.clinician_report_column_systolic
        ClinicianReportText.COLUMN_DIASTOLIC -> R.string.clinician_report_column_diastolic
        ClinicianReportText.COLUMN_SOURCE -> R.string.clinician_report_column_source
        ClinicianReportText.COLUMN_VALUE -> R.string.clinician_report_column_value
        ClinicianReportText.COLUMN_WEIGHT -> R.string.clinician_report_column_weight
        ClinicianReportText.COLUMN_STEPS -> R.string.clinician_report_column_steps
        ClinicianReportText.COLUMN_NIGHT -> R.string.clinician_report_column_night
        ClinicianReportText.COLUMN_DURATION -> R.string.clinician_report_column_duration
        ClinicianReportText.COLUMN_TYPE -> R.string.clinician_report_column_type
        ClinicianReportText.VALUE_ON_DATE -> R.string.clinician_report_value_on_date
        ClinicianReportText.COVERAGE -> R.string.clinician_report_coverage
        ClinicianReportText.SOURCES -> R.string.clinician_report_sources
        ClinicianReportText.STEP_TOTAL -> R.string.clinician_report_step_total
        ClinicianReportText.STEP_AVERAGE -> R.string.clinician_report_step_average
        ClinicianReportText.DURATION_HOURS -> R.string.clinician_report_duration_hours
        ClinicianReportText.DURATION_MINUTES -> R.string.clinician_report_duration_minutes
        ClinicianReportText.DURATION_HOURS_MINUTES -> R.string.clinician_report_duration_hours_minutes
        ClinicianReportText.WORKOUT_BREAKDOWN_ITEM -> R.string.clinician_report_workout_breakdown_item
        ClinicianReportText.DETAIL_READINGS_COUNT -> R.string.clinician_report_detail_readings_count
        ClinicianReportText.METADATA_PERIOD -> R.string.clinician_report_metadata_period
        ClinicianReportText.METADATA_GENERATED -> R.string.clinician_report_metadata_generated
        ClinicianReportText.METADATA_TIMEZONE -> R.string.clinician_report_metadata_timezone
        ClinicianReportText.METADATA_PATIENT -> R.string.clinician_report_metadata_patient
        ClinicianReportText.AVAILABILITY_NOTE -> R.string.clinician_report_availability_note
        ClinicianReportText.ABOUT -> R.string.clinician_report_about
        ClinicianReportText.PAGE_FOOTER -> R.string.clinician_report_page_footer
        ClinicianReportText.WARNING_READ_FAILURE -> R.string.clinician_report_warning_read_failure
        ClinicianReportText.WARNING_SOURCE_FAILURE_DATE -> R.string.clinician_report_warning_source_failure_date
        ClinicianReportText.WARNING_APPLE_READ_FAILURE_DATE -> R.string.clinician_report_warning_apple_read_failure_date
        ClinicianReportText.WARNING_APPLE_SOURCE_FAILURE_DATE -> R.string.clinician_report_warning_apple_source_failure_date
        ClinicianReportText.WARNING_APPLE_INTEGRITY_DATE -> R.string.clinician_report_warning_apple_integrity_date
        ClinicianReportText.WARNING_APPLE_SUMMARY_FALLBACK -> R.string.clinician_report_warning_apple_summary_fallback
        ClinicianReportText.ERROR_PREPARE_ANDROID -> R.string.clinician_report_error_prepare_android
        ClinicianReportText.ERROR_PREPARE_APPLE -> R.string.clinician_report_error_prepare_apple
        ClinicianReportText.ERROR_PDF -> R.string.clinician_report_error_pdf
        ClinicianReportText.SAVED -> R.string.clinician_report_saved
        ClinicianReportText.ERROR_SAVE -> R.string.clinician_report_error_save
        ClinicianReportText.ERROR_OPEN_DESTINATION -> R.string.clinician_report_error_open_destination
        ClinicianReportText.ACCESSIBILITY_HINT -> R.string.clinician_report_accessibility_hint
        ClinicianReportText.WORKOUT_TYPE_RUNNING -> R.string.clinician_report_workout_type_running
        ClinicianReportText.WORKOUT_TYPE_WALKING -> R.string.clinician_report_workout_type_walking
        ClinicianReportText.WORKOUT_TYPE_CYCLING -> R.string.clinician_report_workout_type_cycling
        ClinicianReportText.WORKOUT_TYPE_SWIMMING -> R.string.clinician_report_workout_type_swimming
        ClinicianReportText.WORKOUT_TYPE_HIKING -> R.string.clinician_report_workout_type_hiking
        ClinicianReportText.WORKOUT_TYPE_YOGA -> R.string.clinician_report_workout_type_yoga
        ClinicianReportText.WORKOUT_TYPE_STRENGTH_TRAINING -> R.string.clinician_report_workout_type_strength_training
        ClinicianReportText.WORKOUT_TYPE_CORE_TRAINING -> R.string.clinician_report_workout_type_core_training
        ClinicianReportText.WORKOUT_TYPE_HIIT -> R.string.clinician_report_workout_type_hiit
        ClinicianReportText.WORKOUT_TYPE_ELLIPTICAL -> R.string.clinician_report_workout_type_elliptical
        ClinicianReportText.WORKOUT_TYPE_ROWING -> R.string.clinician_report_workout_type_rowing
        ClinicianReportText.WORKOUT_TYPE_STAIR_CLIMBING -> R.string.clinician_report_workout_type_stair_climbing
        ClinicianReportText.WORKOUT_TYPE_PILATES -> R.string.clinician_report_workout_type_pilates
        ClinicianReportText.WORKOUT_TYPE_DANCE -> R.string.clinician_report_workout_type_dance
        ClinicianReportText.WORKOUT_TYPE_COOLDOWN -> R.string.clinician_report_workout_type_cooldown
        ClinicianReportText.WORKOUT_TYPE_MIXED_CARDIO -> R.string.clinician_report_workout_type_mixed_cardio
        ClinicianReportText.WORKOUT_TYPE_PICKLEBALL -> R.string.clinician_report_workout_type_pickleball
        ClinicianReportText.WORKOUT_TYPE_TENNIS -> R.string.clinician_report_workout_type_tennis
        ClinicianReportText.WORKOUT_TYPE_BADMINTON -> R.string.clinician_report_workout_type_badminton
        ClinicianReportText.WORKOUT_TYPE_TABLE_TENNIS -> R.string.clinician_report_workout_type_table_tennis
        ClinicianReportText.WORKOUT_TYPE_GOLF -> R.string.clinician_report_workout_type_golf
        ClinicianReportText.WORKOUT_TYPE_SOCCER -> R.string.clinician_report_workout_type_soccer
        ClinicianReportText.WORKOUT_TYPE_BASKETBALL -> R.string.clinician_report_workout_type_basketball
        ClinicianReportText.WORKOUT_TYPE_BASEBALL -> R.string.clinician_report_workout_type_baseball
        ClinicianReportText.WORKOUT_TYPE_SOFTBALL -> R.string.clinician_report_workout_type_softball
        ClinicianReportText.WORKOUT_TYPE_VOLLEYBALL -> R.string.clinician_report_workout_type_volleyball
        ClinicianReportText.WORKOUT_TYPE_AMERICAN_FOOTBALL -> R.string.clinician_report_workout_type_american_football
        ClinicianReportText.WORKOUT_TYPE_RUGBY -> R.string.clinician_report_workout_type_rugby
        ClinicianReportText.WORKOUT_TYPE_HOCKEY -> R.string.clinician_report_workout_type_hockey
        ClinicianReportText.WORKOUT_TYPE_LACROSSE -> R.string.clinician_report_workout_type_lacrosse
        ClinicianReportText.WORKOUT_TYPE_SKATING -> R.string.clinician_report_workout_type_skating
        ClinicianReportText.WORKOUT_TYPE_SNOW_SPORTS -> R.string.clinician_report_workout_type_snow_sports
        ClinicianReportText.WORKOUT_TYPE_WATER_SPORTS -> R.string.clinician_report_workout_type_water_sports
        ClinicianReportText.WORKOUT_TYPE_WHEELCHAIR -> R.string.clinician_report_workout_type_wheelchair
        ClinicianReportText.WORKOUT_TYPE_MARTIAL_ARTS -> R.string.clinician_report_workout_type_martial_arts
        ClinicianReportText.WORKOUT_TYPE_BOXING -> R.string.clinician_report_workout_type_boxing
        ClinicianReportText.WORKOUT_TYPE_KICKBOXING -> R.string.clinician_report_workout_type_kickboxing
        ClinicianReportText.WORKOUT_TYPE_WRESTLING -> R.string.clinician_report_workout_type_wrestling
        ClinicianReportText.WORKOUT_TYPE_CLIMBING -> R.string.clinician_report_workout_type_climbing
        ClinicianReportText.WORKOUT_TYPE_JUMP_ROPE -> R.string.clinician_report_workout_type_jump_rope
        ClinicianReportText.WORKOUT_TYPE_FLEXIBILITY -> R.string.clinician_report_workout_type_flexibility
        ClinicianReportText.WORKOUT_TYPE_OTHER -> R.string.clinician_report_workout_type_other
        ClinicianReportText.UNIT_RESPIRATORY_RATE -> R.string.clinician_report_unit_respiratory_rate
    }
}
