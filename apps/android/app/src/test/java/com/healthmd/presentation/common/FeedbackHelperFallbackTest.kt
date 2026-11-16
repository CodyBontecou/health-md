package com.healthmd.presentation.common

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Issue #169: a failed feedback handoff explains itself and offers a copyable local report. */
@RunWith(RobolectricTestRunner::class)
class FeedbackHelperFallbackTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val noHandler = FeedbackHelper.Launcher { throw ActivityNotFoundException() }

    @Test
    fun `missing mail app returns an email fallback with the support address`() {
        val fallback = FeedbackHelper.sendFeedbackEmail(context, noHandler)

        assertThat(fallback?.route).isEqualTo(FeedbackRoute.EMAIL)
        assertThat(fallback?.reportText).contains(FeedbackHelper.SUPPORT_EMAIL)
        assertThat(fallback?.reportText).contains("Problem:")
        assertThat(fallback?.reportText).contains("Steps to reproduce:")
    }

    @Test
    fun `missing browser returns GitHub and Discord fallbacks with their URLs`() {
        val github = FeedbackHelper.openGitHubIssue(context, noHandler)
        val discord = FeedbackHelper.openDiscordCommunity(context, noHandler)

        assertThat(github?.route).isEqualTo(FeedbackRoute.GITHUB)
        assertThat(github?.reportText).contains(FeedbackHelper.GITHUB_NEW_ISSUE_URL)
        assertThat(discord?.route).isEqualTo(FeedbackRoute.DISCORD)
        assertThat(discord?.reportText).contains(FeedbackHelper.DISCORD_URL)
    }

    @Test
    fun `successful handoff shows no fallback and claims no submission`() {
        val launched = mutableListOf<Intent>()
        val launcher = FeedbackHelper.Launcher { launched += it }

        assertThat(FeedbackHelper.sendFeedbackEmail(context, launcher)).isNull()
        assertThat(FeedbackHelper.openGitHubIssue(context, launcher)).isNull()
        assertThat(FeedbackHelper.openDiscordCommunity(context, launcher)).isNull()
        assertThat(launched).hasSize(3)
    }

    @Test
    fun `fallback report carries no device model`() {
        val report = FeedbackHelper.fallbackReport(context, FeedbackRoute.GITHUB, appVersion = "9.9")

        assertThat(report).startsWith("Health.md 9.9 · Android ")
        assertThat(report).doesNotContain(android.os.Build.MODEL)
    }
}
