package com.healthmd.presentation.schedule

import android.text.format.DateFormat
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
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
        ExportTarget.GOOGLE_DRIVE -> "Google Drive"
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
    val (template, arguments) = automationSentenceParts(profile, entry)
    return stringResource(template, *arguments.toTypedArray())
}

/**
 * The same sentence with its values (time, day, destination) drawn as the board's underlined
 * tokens, so the schedule reads as a sentence whose parts can be changed.
 */
@Composable
internal fun automationSentenceAnnotated(
    profile: ExportProfile,
    entry: ScheduledProfileEntry?,
    tokenStyle: SpanStyle,
): AnnotatedString {
    val (template, arguments) = automationSentenceParts(profile, entry)
    return annotateTemplate(LocalContext.current.resources.getString(template), arguments, tokenStyle)
}

/** Replaces `%n$s` placeholders with [arguments], each drawn in [tokenStyle]. */
internal fun annotateTemplate(template: String, arguments: List<String>, tokenStyle: SpanStyle): AnnotatedString =
    buildAnnotatedString {
        var index = 0
        PLACEHOLDER.findAll(template).forEach { match ->
            append(template.substring(index, match.range.first).replace("%%", "%"))
            val argument = arguments.getOrNull(match.groupValues[1].toInt() - 1).orEmpty()
            withStyle(tokenStyle) { append(argument) }
            index = match.range.last + 1
        }
        append(template.substring(index).replace("%%", "%"))
    }

private val PLACEHOLDER = Regex("%(\\d+)\\\$[sd]")

@Composable
private fun automationSentenceParts(profile: ExportProfile, entry: ScheduledProfileEntry?): Pair<Int, List<String>> {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val destination = AutomationSentence.destination(profile, LocalAppFolderName.current)
        ?: stringResource(R.string.automation_destination_selected_folder)
    val time = entry?.let {
        val pattern = DateFormat.getBestDateTimePattern(locale, if (DateFormat.is24HourFormat(context)) "Hm" else "hm")
        LocalTime.of(it.hour, it.minute).format(DateTimeFormatter.ofPattern(pattern, locale))
    }.orEmpty()
    return when (AutomationSentence.kind(entry)) {
        AutomationSentenceKind.DAILY -> R.string.automation_sentence_daily to listOf(time, destination)
        AutomationSentenceKind.WEEKLY -> R.string.automation_sentence_weekly to listOf(
            DayOfWeek.of(requireNotNull(entry).weekdayIso).getDisplayName(TextStyle.FULL, locale),
            time,
            destination,
        )
        AutomationSentenceKind.MONTHLY -> R.string.automation_sentence_monthly to listOf(time, destination)
        AutomationSentenceKind.CUSTOM -> R.string.automation_sentence_custom to listOf(time, destination)
        AutomationSentenceKind.MANUAL -> R.string.automation_sentence_manual to listOf(destination)
    }
}
