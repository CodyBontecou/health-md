package com.healthmd.domain.model

/**
 * Public `healthmd.health_data` profile one compatibility daily record is written with.
 *
 * [CompatibilitySchemaProfile] is the stored preference; this is the resolved wire identity of a
 * single export operation. Capture, writers, engine pins, and durable snapshots all resolve it
 * through [resolve] so they cannot disagree.
 *
 * - `android-analytical-v7` is the analytical v5 grammar plus interval arrays for Health Connect
 *   records v5 only aggregates (calories, distance, floors, elevation, hydration, body records).
 *   It is selected only by an explicit `detailed` override for activity, nutrition, or body on the
 *   analytical profile ([ExportDetailSelection.analyticalExpansion]). It is rendered only by the
 *   native (legacy) Kotlin writers; the Rust registry/engine profiles never represent it.
 * - Frozen v4 never upgrades. Morning-ends wake-date exports stay `android-sleep-v6`, which does
 *   not capture or write the expansion arrays.
 * - Daily notes, scoped direct notes, and Obsidian Bases carry no sample arrays and keep the v5
 *   identity.
 */
enum class DailyRecordSchemaProfile(val publicProfileId: String, val schemaVersion: Int) {
    ANDROID_FROZEN_V4("android-frozen-v4", 4),
    ANDROID_ANALYTICAL_V5("android-analytical-v5", 5),
    ANDROID_SLEEP_V6("android-sleep-v6", 6),
    ANDROID_ANALYTICAL_V7("android-analytical-v7", 7);

    /** True when the shipped analytical v5 rules apply (v7 is a strict v5 superset). */
    val usesAnalyticalGrammar: Boolean
        get() = this == ANDROID_ANALYTICAL_V5 || this == ANDROID_ANALYTICAL_V7

    /** True when the v7 interval arrays may be captured and written. */
    val writesDetailExpansion: Boolean
        get() = this == ANDROID_ANALYTICAL_V7

    /** v7 has no Rust/UniFFI registry profile; only the native writers may render it. */
    val requiresLegacyEngine: Boolean
        get() = this == ANDROID_ANALYTICAL_V7

    companion object {
        fun resolve(
            profile: CompatibilitySchemaProfile,
            detail: ExportDetailSelection,
            sleepDayAttribution: SleepDayAttribution? = null,
        ): DailyRecordSchemaProfile = when {
            sleepDayAttribution == SleepDayAttribution.MORNING_ENDS -> ANDROID_SLEEP_V6
            profile == CompatibilitySchemaProfile.IOS_V4_FROZEN -> ANDROID_FROZEN_V4
            detail.analyticalExpansion -> ANDROID_ANALYTICAL_V7
            else -> ANDROID_ANALYTICAL_V5
        }

        /** Writer-side resolution for the local (non-wake-date) compatibility writers. */
        fun forWriter(customization: FormatCustomization, detail: ExportDetailSelection): DailyRecordSchemaProfile =
            resolve(customization.compatibilitySchemaProfile, detail)
    }
}
