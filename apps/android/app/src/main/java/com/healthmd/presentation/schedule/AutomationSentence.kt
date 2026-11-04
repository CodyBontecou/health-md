package com.healthmd.presentation.schedule

import android.text.format.DateFormat
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.LocalAppFolderName
import java.net.URI
import java.time.DayOfWeek
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/** How an automation reads as a sentence. Counts other than one read as a custom schedule. */
enum class AutomationSentenceKind { DAILY, WEEKLY, MONTHLY, CUSTOM, MANUAL }

object AutomationSentence {
    fun kind(entry: ScheduledProfileEntry?): AutomationSentenceKind = when {
        entry == null || !entry.isEnabled -> AutomationSentenceKind.MANUAL
        entry.cadenceValue != 1 -> AutomationSentenceKind.CUSTOM
        entry.cadenceUnit == ScheduledProfileCadenceUnit.DAY -> AutomationSentenceKind.DAILY
        entry.cadenceUnit == ScheduledProfileCadenceUnit.WEEK -> AutomationSentenceKind.WEEKLY
        else -> AutomationSentenceKind.MONTHLY
    }

    /** A privacy-safe destination: the folder name, or only the host of an endpoint. */
    fun destination(profile: ExportProfile): String? = when (profile.target) {
        ExportTarget.DEVICE_FOLDER -> profile.folderDisplayName?.trim()?.takeIf { it.isNotEmpty() }
        ExportTarget.API_ENDPOINT -> host(profile.apiEndpointUrl)
        ExportTarget.AGENT_DATA_GATEWAY -> host(profile.agentDataGatewayUrl)
    }

    /** [destination], else the app's export folder for a device-folder profile without its own. */
    fun destination(profile: ExportProfile, appFolderName: String?): String? =
        destination(profile) ?: appFolderName?.takeIf {
            profile.target == ExportTarget.DEVICE_FOLDER && profile.folderUri == null && it.isNotBlank()
        }

    private fun host(url: String?): String? =
        url?.let { runCatching { URI(it.trim()).host }.getOrNull() }?.takeIf { it.isNotBlank() }
}

/** "Every day at 7:30, export to Vault." in the user's language, time format and calendar. */
@Composable
internal fun automationSentence(profile: ExportProfile, entry: ScheduledProfileEntry?): String {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val destination = AutomationSentence.destination(profile, LocalAppFolderName.current)
        ?: stringResource(R.string.automation_destination_selected_folder)
    val time = entry?.let {
        val pattern = DateFormat.getBestDateTimePattern(locale, if (DateFormat.is24HourFormat(context)) "Hm" else "hm")
        LocalTime.of(it.hour, it.minute).format(DateTimeFormatter.ofPattern(pattern, locale))
    }.orEmpty()
    return when (AutomationSentence.kind(entry)) {
        AutomationSentenceKind.DAILY -> stringResource(R.string.automation_sentence_daily, time, destination)
        AutomationSentenceKind.WEEKLY -> stringResource(
            R.string.automation_sentence_weekly,
            DayOfWeek.of(requireNotNull(entry).weekdayIso).getDisplayName(TextStyle.FULL, locale),
            time,
            destination,
        )
        AutomationSentenceKind.MONTHLY -> stringResource(R.string.automation_sentence_monthly, time, destination)
        AutomationSentenceKind.CUSTOM -> stringResource(R.string.automation_sentence_custom, time, destination)
        AutomationSentenceKind.MANUAL -> stringResource(R.string.automation_sentence_manual, destination)
    }
}
