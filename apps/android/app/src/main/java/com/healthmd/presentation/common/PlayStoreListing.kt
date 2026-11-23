package com.healthmd.presentation.common

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Opens Health.md's Google Play listing so someone can rate it whenever they choose. This is the
 * manual path: it never calls the quota-limited In-App Review API. Tries the Play Store app, then
 * the web listing; returns false when nothing could open either.
 */
object PlayStoreListing {
    const val PACKAGE_NAME = "com.healthmd.android"
    const val MARKET_URI = "market://details?id=$PACKAGE_NAME"
    const val WEB_URL = "https://play.google.com/store/apps/details?id=$PACKAGE_NAME"

    fun open(
        context: Context,
        launcher: FeedbackHelper.Launcher = FeedbackHelper.Launcher { context.startActivity(it) },
    ): Boolean = listOf(MARKET_URI, WEB_URL).any { uri ->
        try {
            launcher.launch(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
