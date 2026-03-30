package com.healthmd.presentation.common

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.healthmd.R

object FeedbackHelper {

    private const val SUPPORT_EMAIL = "cody@isolated.tech"
    private const val GITHUB_REPO = "CodyBontecou/health-md"

    private fun getDiagnosticsBlock(context: Context): String {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val versionName = packageInfo.versionName ?: "?"
        val versionCode = packageInfo.longVersionCode
        val osVersion = Build.VERSION.RELEASE
        val device = "${Build.MANUFACTURER} ${Build.MODEL}"

        return """
            |---
            |App: Health.md $versionName ($versionCode)
            |Platform: Android $osVersion (API ${Build.VERSION.SDK_INT})
            |Device: $device
        """.trimMargin()
    }

    fun sendFeedbackEmail(context: Context) {
        val diagnostics = getDiagnosticsBlock(context)
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("mailto:")
            putExtra(Intent.EXTRA_EMAIL, arrayOf(SUPPORT_EMAIL))
            putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.feedback_email_subject))
            putExtra(Intent.EXTRA_TEXT, "\n\n$diagnostics")
        }
        context.startActivity(Intent.createChooser(intent, context.getString(R.string.feedback_send_chooser)))
    }

    fun openGitHubIssue(context: Context) {
        val diagnostics = getDiagnosticsBlock(context)
        val body = """
            |**Describe the issue**
            |<!-- A clear description of what happened -->
            |
            |**Steps to reproduce**
            |1.
            |2.
            |3.
            |
            |**Expected behavior**
            |<!-- What you expected to happen -->
            |
            |$diagnostics
        """.trimMargin()

        val uri = Uri.parse("https://github.com/$GITHUB_REPO/issues/new")
            .buildUpon()
            .appendQueryParameter("title", "")
            .appendQueryParameter("body", body)
            .build()

        context.startActivity(Intent(Intent.ACTION_VIEW, uri))
    }
}
