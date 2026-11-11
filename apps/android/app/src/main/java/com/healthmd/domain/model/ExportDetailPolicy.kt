package com.healthmd.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Stable, platform-neutral detail groups. Wire IDs are shared with Apple
 * (`ExportDetailGroup` in ExportSettingsSnapshot.swift) and documented in
 * docs/features/per-group-export-detail.md; never rename one in place.
 *
 * A group selects which existing optional detail sections a compatibility export emits. It
 * never changes daily summary values, metric selection, file organization, or raw snapshots.
 */
@Serializable
enum class ExportDetailGroup(val wireId: String) {
    @SerialName("sleep") SLEEP("sleep"),
    @SerialName("activity") ACTIVITY("activity"),
    @SerialName("heart") HEART("heart"),
    @SerialName("vitals") VITALS("vitals"),
    @SerialName("nutrition") NUTRITION("nutrition"),
    @SerialName("mobility") MOBILITY("mobility"),
    @SerialName("reproductive_health") REPRODUCTIVE_HEALTH("reproductive_health"),
    @SerialName("mindfulness") MINDFULNESS("mindfulness"),
    @SerialName("workouts") WORKOUTS("workouts"),
    /** Body measurements. Only `android-analytical-v7` has a detail projection for it. */
    @SerialName("body") BODY("body");

    /** Choices this group can honor on Android, ordered from least to most detail. */
    val supportedChoices: List<ExportDetailChoice>
        get() = when (this) {
            SLEEP -> listOf(ExportDetailChoice.SUMMARY, ExportDetailChoice.SESSIONS, ExportDetailChoice.DETAILED)
            else -> listOf(ExportDetailChoice.SUMMARY, ExportDetailChoice.DETAILED)
        }

    companion object {
        fun fromWireId(id: String): ExportDetailGroup? = entries.firstOrNull { it.wireId == id }
    }
}

/**
 * Per-group detail request.
 *
 * - [SUMMARY]: daily aggregates only.
 * - [SESSIONS]: individual source sessions/events without their nested samples (sleep only:
 *   Health Connect sleep sessions without stage intervals).
 * - [DETAILED]: every detail section the group supports, including nested samples.
 */
@Serializable
enum class ExportDetailChoice(val wireId: String) {
    @SerialName("summary") SUMMARY("summary"),
    @SerialName("sessions") SESSIONS("sessions"),
    @SerialName("detailed") DETAILED("detailed");

    companion object {
        fun fromWireId(id: String): ExportDetailChoice? = entries.firstOrNull { it.wireId == id }
    }
}

/**
 * Resolved detail for one export operation. Capture and every compatibility writer read these
 * flags instead of the historical global Boolean.
 */
data class ExportDetailSelection(
    val sleepSessions: Boolean = false,
    val sleepStages: Boolean = false,
    val activity: Boolean = false,
    val heart: Boolean = false,
    val vitals: Boolean = false,
    val nutrition: Boolean = false,
    val mobility: Boolean = false,
    val reproductiveHealth: Boolean = false,
    val mindfulness: Boolean = false,
    val workouts: Boolean = false,
    val body: Boolean = false,
    /**
     * Readable sleep-session list in Markdown/Bases. Only an explicit sleep override enables it, so
     * historical global-detail Markdown stays byte-identical; JSON keeps using [sleepSessions].
     */
    val sleepSessionList: Boolean = false,
    /**
     * An explicit `detailed` override exists for a group whose new interval records the shipped
     * analytical v5 grammar cannot represent (activity, nutrition, body). With the analytical
     * profile this selects `android-analytical-v7`; see [DailyRecordSchemaProfile]. The uniform
     * default never sets it, so historical global-detail exports stay byte-identical v5.
     */
    val analyticalExpansion: Boolean = false,
) {
    /** True when any group emits detail; replaces legacy `includeGranularData` reads. */
    val any: Boolean
        get() = sleepSessions || sleepStages || activity || heart || vitals || nutrition ||
            mobility || reproductiveHealth || mindfulness || workouts || body

    /** True when every group emits full detail, i.e. the historical global-on behavior. */
    val isUniformDetailed: Boolean
        get() = copy(sleepSessionList = false, analyticalExpansion = false) == UNIFORM_DETAILED

    fun choice(group: ExportDetailGroup): ExportDetailChoice = when (group) {
        ExportDetailGroup.SLEEP -> when {
            sleepStages -> ExportDetailChoice.DETAILED
            sleepSessions -> ExportDetailChoice.SESSIONS
            else -> ExportDetailChoice.SUMMARY
        }
        else -> if (flag(group)) ExportDetailChoice.DETAILED else ExportDetailChoice.SUMMARY
    }

    /** Union used when internal processing (individual tracking) needs source detail. */
    infix fun union(other: ExportDetailSelection): ExportDetailSelection = ExportDetailSelection(
        sleepSessions = sleepSessions || other.sleepSessions,
        sleepStages = sleepStages || other.sleepStages,
        sleepSessionList = sleepSessionList || other.sleepSessionList,
        activity = activity || other.activity,
        heart = heart || other.heart,
        vitals = vitals || other.vitals,
        nutrition = nutrition || other.nutrition,
        mobility = mobility || other.mobility,
        reproductiveHealth = reproductiveHealth || other.reproductiveHealth,
        mindfulness = mindfulness || other.mindfulness,
        workouts = workouts || other.workouts,
        body = body || other.body,
        analyticalExpansion = analyticalExpansion || other.analyticalExpansion,
    )

    private fun flag(group: ExportDetailGroup): Boolean = when (group) {
        ExportDetailGroup.SLEEP -> sleepSessions || sleepStages
        ExportDetailGroup.ACTIVITY -> activity
        ExportDetailGroup.HEART -> heart
        ExportDetailGroup.VITALS -> vitals
        ExportDetailGroup.NUTRITION -> nutrition
        ExportDetailGroup.MOBILITY -> mobility
        ExportDetailGroup.REPRODUCTIVE_HEALTH -> reproductiveHealth
        ExportDetailGroup.MINDFULNESS -> mindfulness
        ExportDetailGroup.WORKOUTS -> workouts
        ExportDetailGroup.BODY -> body
    }

    companion object {
        val SUMMARY = ExportDetailSelection()

        /** Groups whose explicit `detailed` override requests `android-analytical-v7`. */
        val ANALYTICAL_EXPANSION_GROUPS: Set<ExportDetailGroup> = setOf(
            ExportDetailGroup.ACTIVITY,
            ExportDetailGroup.NUTRITION,
            ExportDetailGroup.BODY,
        )
        val UNIFORM_DETAILED = ExportDetailSelection(
            sleepSessions = true,
            sleepStages = true,
            activity = true,
            heart = true,
            vitals = true,
            nutrition = true,
            mobility = true,
            reproductiveHealth = true,
            mindfulness = true,
            workouts = true,
            body = true,
        )

        /** Exact projection of the historical global Boolean. */
        fun uniform(includeGranularData: Boolean): ExportDetailSelection =
            if (includeGranularData) UNIFORM_DETAILED else SUMMARY

        /**
         * Resolves a default level plus overrides. Unknown or unsupported overrides are rejected by
         * [ExportDetailOverrides.validated]; this function assumes validated input.
         */
        fun resolve(
            includeGranularDataByDefault: Boolean,
            overrides: Map<ExportDetailGroup, ExportDetailChoice>,
        ): ExportDetailSelection {
            fun choice(group: ExportDetailGroup): ExportDetailChoice = overrides[group]
                ?: if (includeGranularDataByDefault) ExportDetailChoice.DETAILED else ExportDetailChoice.SUMMARY
            fun detailed(group: ExportDetailGroup) = choice(group) == ExportDetailChoice.DETAILED
            val sleep = choice(ExportDetailGroup.SLEEP)
            return ExportDetailSelection(
                sleepSessions = sleep != ExportDetailChoice.SUMMARY,
                sleepStages = sleep == ExportDetailChoice.DETAILED,
                sleepSessionList = overrides[ExportDetailGroup.SLEEP]?.let { it != ExportDetailChoice.SUMMARY } == true,
                activity = detailed(ExportDetailGroup.ACTIVITY),
                heart = detailed(ExportDetailGroup.HEART),
                vitals = detailed(ExportDetailGroup.VITALS),
                nutrition = detailed(ExportDetailGroup.NUTRITION),
                mobility = detailed(ExportDetailGroup.MOBILITY),
                reproductiveHealth = detailed(ExportDetailGroup.REPRODUCTIVE_HEALTH),
                mindfulness = detailed(ExportDetailGroup.MINDFULNESS),
                workouts = detailed(ExportDetailGroup.WORKOUTS),
                body = detailed(ExportDetailGroup.BODY),
                analyticalExpansion = ANALYTICAL_EXPANSION_GROUPS.any { overrides[it] == ExportDetailChoice.DETAILED },
            )
        }
    }
}

/** Validation and normalization for persisted override maps keyed by wire IDs. */
object ExportDetailOverrides {
    /** Bounded: one entry per known group. */
    const val MAX_ENTRIES: Int = 16

    /**
     * Returns typed overrides, or null when any key/value is unknown or unsupported for its group.
     * Callers treat null as corrupt durable state and fail closed rather than guessing.
     */
    fun validated(raw: Map<String, String>): Map<ExportDetailGroup, ExportDetailChoice>? {
        if (raw.size > MAX_ENTRIES) return null
        val result = sortedMapOf<ExportDetailGroup, ExportDetailChoice>()
        for ((key, value) in raw) {
            val group = ExportDetailGroup.fromWireId(key) ?: return null
            val choice = ExportDetailChoice.fromWireId(value) ?: return null
            if (choice !in group.supportedChoices) return null
            result[group] = choice
        }
        return result
    }

    /**
     * Canonical wire map: sorted keys, unsupported entries removed. Explicit choices equal to the
     * default are kept: an explicit sleep choice also enables the readable session list, so
     * dropping it would make a scheduled retry render differently from the accepted export.
     */
    fun normalized(overrides: Map<ExportDetailGroup, ExportDetailChoice>): Map<String, String> =
        overrides
            .filter { (group, choice) -> choice in group.supportedChoices }
            .toSortedMap()
            .entries
            .associate { (group, choice) -> group.wireId to choice.wireId }
}
