package com.healthmd.presentation.common

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.healthmd.R

/** The external app a feedback action hands off to. */
enum class FeedbackRoute { EMAIL, GITHUB, DISCORD }

/**
 * Shown when no app can take a feedback handoff. Nothing was sent: the user edits and copies
 * [reportText] to submit later or from another device. A successful handoff is not proof that an
 * email or GitHub issue was submitted, so success has no confirmation.
 */
data class FeedbackFallback(
    val route: FeedbackRoute,
    val reportText: String,
)

object FeedbackHelper {

    const val SUPPORT_EMAIL = "cody@isolated.tech"
    const val GITHUB_REPO = "CodyBontecou/health-md"
    const val GITHUB_NEW_ISSUE_URL = "https://github.com/$GITHUB_REPO/issues/new"
    const val DISCORD_URL = "https://discord.gg/RaQYS4t6gn"

    /** Starts [intent]; throws [ActivityNotFoundException] when no app can handle it. */
    fun interface Launcher {
        fun launch(intent: Intent)
    }

    private fun Context.defaultLauncher() = Launcher { startActivity(it) }

    private fun getDiagnosticsBlock(context: Context): String {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val versionName = packageInfo.versionName ?: "?"
        val versionCode = packageInfo.longVersionCode
        val osVersion = Build.VERSION.RELEASE
        val device = "${Build.MANUFACTURER} ${Build.MODEL}"

        return listOf(
            "---",
            context.getString(R.string.feedback_diagnostic_app, versionName, versionCode),
            context.getString(
                R.string.feedback_diagnostic_platform,
                osVersion,
                Build.VERSION.SDK_INT,
            ),
            context.getString(R.string.feedback_diagnostic_device, device),
        ).joinToString("\n")
    }

    fun sendFeedbackEmail(
        context: Context,
        launcher: Launcher = context.defaultLauncher(),
    ): FeedbackFallback? {
        val diagnostics = getDiagnosticsBlock(context)
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("mailto:")
            putExtra(Intent.EXTRA_EMAIL, arrayOf(SUPPORT_EMAIL))
            putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.feedback_email_subject))
            putExtra(Intent.EXTRA_TEXT, "\n\n$diagnostics")
        }
        return handOff(
            context,
            FeedbackRoute.EMAIL,
            Intent.createChooser(intent, context.getString(R.string.feedback_send_chooser)),
            launcher,
        )
    }

    fun openDiscordCommunity(
        context: Context,
        launcher: Launcher = context.defaultLauncher(),
    ): FeedbackFallback? = handOff(context, FeedbackRoute.DISCORD, browsableIntent(DISCORD_URL), launcher)

    fun openGitHubIssue(
        context: Context,
        launcher: Launcher = context.defaultLauncher(),
    ): FeedbackFallback? {
        val diagnostics = getDiagnosticsBlock(context)
        val body = listOf(
            "**${context.getString(R.string.feedback_issue_describe_heading)}**",
            "<!-- ${context.getString(R.string.feedback_issue_describe_hint)} -->",
            "",
            "**${context.getString(R.string.feedback_issue_steps_heading)}**",
            "1.",
            "2.",
            "3.",
            "",
            "**${context.getString(R.string.feedback_issue_expected_heading)}**",
            "<!-- ${context.getString(R.string.feedback_issue_expected_hint)} -->",
            "",
            diagnostics,
        ).joinToString("\n")

        val uri = Uri.parse(GITHUB_NEW_ISSUE_URL)
            .buildUpon()
            .appendQueryParameter("title", "")
            .appendQueryParameter("body", body)
            .build()

        return handOff(context, FeedbackRoute.GITHUB, browsableIntent(uri.toString()), launcher)
    }

    /**
     * The local report: a version line, three prompts, a privacy reminder and where to send it.
     * Like Apple, it carries no device model or identifiers, and no health data.
     */
    fun fallbackReport(
        context: Context,
        route: FeedbackRoute,
        appVersion: String = appVersion(context),
    ): String {
        val destination = when (route) {
            FeedbackRoute.EMAIL -> context.getString(R.string.feedback_fallback_destination_email, SUPPORT_EMAIL)
            FeedbackRoute.GITHUB -> context.getString(R.string.feedback_fallback_destination_github, GITHUB_NEW_ISSUE_URL)
            FeedbackRoute.DISCORD -> context.getString(R.string.feedback_fallback_destination_discord, DISCORD_URL)
        }
        return listOf(
            context.getString(R.string.feedback_fallback_version_line, appVersion, Build.VERSION.RELEASE),
            context.getString(R.string.feedback_fallback_problem),
            context.getString(R.string.feedback_fallback_expected),
            context.getString(R.string.feedback_fallback_steps),
            context.getString(R.string.feedback_fallback_private_reminder),
            "",
            destination,
        ).joinToString("\n")
    }

    private fun appVersion(context: Context): String =
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }
            .getOrNull() ?: "?"

    private fun browsableIntent(url: String) = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
        addCategory(Intent.CATEGORY_BROWSABLE)
    }

    private fun handOff(
        context: Context,
        route: FeedbackRoute,
        intent: Intent,
        launcher: Launcher,
    ): FeedbackFallback? = try {
        launcher.launch(intent)
        null
    } catch (_: ActivityNotFoundException) {
        FeedbackFallback(route, fallbackReport(context, route))
    }
}
