package com.healthmd.presentation.common

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import com.healthmd.R

object FeedbackHelper {

    private const val SUPPORT_EMAIL = "cody@isolated.tech"
    private const val GITHUB_REPO = "CodyBontecou/health-md"
    private const val DISCORD_URL = "https://discord.gg/RaQYS4t6gn"

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

    fun sendFeedbackEmail(context: Context) {
        val diagnostics = getDiagnosticsBlock(context)
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("mailto:")
            putExtra(Intent.EXTRA_EMAIL, arrayOf(SUPPORT_EMAIL))
            putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.feedback_email_subject))
            putExtra(Intent.EXTRA_TEXT, "\n\n$diagnostics")
        }
        try {
            context.startActivity(Intent.createChooser(intent, context.getString(R.string.feedback_send_chooser)))
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(context, context.getString(R.string.feedback_no_app_available), Toast.LENGTH_SHORT).show()
        }
    }

    fun openDiscordCommunity(context: Context) {
        openExternalUrl(context, DISCORD_URL)
    }

    fun openGitHubIssue(context: Context) {
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

        val uri = Uri.parse("https://github.com/$GITHUB_REPO/issues/new")
            .buildUpon()
            .appendQueryParameter("title", "")
            .appendQueryParameter("body", body)
            .build()

        openExternalUrl(context, uri.toString())
    }

    private fun openExternalUrl(context: Context, url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }
        try {
            context.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(context, context.getString(R.string.feedback_no_app_available), Toast.LENGTH_SHORT).show()
        }
    }
}
