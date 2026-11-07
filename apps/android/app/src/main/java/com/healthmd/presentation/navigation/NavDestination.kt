package com.healthmd.presentation.navigation

import android.net.Uri
import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.ui.graphics.vector.ImageVector
import com.healthmd.R
import java.time.LocalDate

/** Top-level destinations: Archive, Automations and Settings. Export now is a global action. */
enum class NavDestination(
    val route: String,
    val icon: ImageVector,
    @StringRes val label: Int,
) {
    ARCHIVE("archive", Icons.Outlined.CalendarMonth, R.string.nav_archive),

    // Keeps the "schedule" route so notification and recovery deep links still land here.
    AUTOMATIONS("schedule", Icons.Outlined.Autorenew, R.string.nav_automations),
    SETTINGS("settings", Icons.Outlined.Settings, R.string.nav_settings),
    ;

    companion object {
        /** The schedule controls now live in Automations. */
        val SCHEDULE: NavDestination get() = AUTOMATIONS
    }
}

// Sub-screen routes (not in bottom nav)
object SubRoutes {
    /** The full export screen, opened from the global Export now action. */
    const val EXPORT_NOW = "export"
    /**
     * Export now preset to one date, opened by Backfill and the Archive's fixes. A profile id
     * presets the automation too (iOS `ExportNowRequest(profileID:)`).
     */
    const val EXPORT_BACKFILL = "export/backfill/{date}?profileId={profileId}"
    fun exportBackfill(date: LocalDate, profileId: String? = null): String =
        "export/backfill/$date" + profileId?.let { "?profileId=${Uri.encode(it)}" }.orEmpty()
    /**
     * The day page: the file one automation wrote for an Archive date. The lane (an encoded
     * [com.healthmd.presentation.archive.ArchiveProfile]) opens that automation's tab.
     */
    const val ARCHIVE_DAY = "archive/day/{date}?lane={lane}"
    fun archiveDay(date: LocalDate, lane: String? = null): String =
        "archive/day/$date" + lane?.let { "?lane=${Uri.encode(it)}" }.orEmpty()
    const val HISTORY = "history"
    const val CLINIC_ACCESS = "clinic-access"
    const val ONBOARDING = "onboarding"
    const val METRIC_SELECTION = "metric_selection"
    const val FORMAT_CUSTOMIZATION = "format_customization"
    const val FRONTMATTER_CUSTOMIZATION = "frontmatter_customization"
    const val DAILY_NOTE_INJECTION = "daily_note_injection"
    const val INDIVIDUAL_TRACKING = "individual_tracking"
    const val ADVANCED_SETTINGS = "advanced_settings"
    const val CLINICIAN_REPORT = "clinician_report"
    const val DIRECT_CLI = "direct_cli"
    const val SHARED_SETUP = "shared_setup"
    const val EXPORT_PROFILES = "export_profiles"
    /** The profiles screen opened on one profile's detail. */
    const val EXPORT_PROFILE = "export_profiles/{profileId}"
    /** The automation detail hub on compact layouts; wide layouts show it as a pane. */
    const val AUTOMATION_DETAIL = "automation/{profileId}"
    fun exportProfile(profileId: String): String = "export_profiles/$profileId"
    fun automationDetail(profileId: String): String = "automation/$profileId"
    /** The automation composer: the profile as one editable sentence with a live file preview. */
    const val AUTOMATION_COMPOSE = "automation/{profileId}/compose"
    fun automationCompose(profileId: String): String = "automation/$profileId/compose"
    const val DIAGNOSTICS = "diagnostics"
    /** The app-wide schedule, scheduled target, permissions and history, from Automations. */
    const val SCHEDULE_SETTINGS = "schedule_settings"
    const val FOLDER_DESTINATION = "folder_destination"
    const val MYSELF_CLAIM = "myself_claim"
    const val PAYWALL = "paywall"
}

enum class PaywallEntryPoint(
    val route: String,
    @StringRes val subtitleResource: Int,
) {
    UPGRADE(SubRoutes.PAYWALL, R.string.settings_upgrade_subtitle),
    EXPORT_LIMIT("${SubRoutes.PAYWALL}/export-limit", R.string.paywall_subtitle),
    SCHEDULE("${SubRoutes.PAYWALL}/schedule", R.string.schedule_unlock_required_body),
}
