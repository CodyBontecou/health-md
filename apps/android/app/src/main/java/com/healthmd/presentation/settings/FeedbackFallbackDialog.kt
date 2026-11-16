package com.healthmd.presentation.settings

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import com.healthmd.R
import com.healthmd.presentation.common.FeedbackFallback
import com.healthmd.presentation.common.FeedbackRoute
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.presentation.theme.Spacing

object FeedbackFallbackTestTags {
    const val DIALOG = "feedback.fallback"
    const val REPORT = "feedback.fallback.report"
    const val COPY = "feedback.fallback.copy"
}

/**
 * Explains a failed feedback handoff and lets the user edit and copy the report locally. Copying
 * needs no browser, mail app, network or account; nothing is sent or stored.
 */
@Composable
internal fun FeedbackFallbackDialog(
    fallback: FeedbackFallback,
    onDismiss: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val context = LocalContext.current
    var report by rememberSaveable(fallback) { mutableStateOf(fallback.reportText) }
    var copied by rememberSaveable(fallback) { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        modifier = Modifier.testTag(FeedbackFallbackTestTags.DIALOG),
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        tonalElevation = androidx.compose.ui.unit.Dp.Hairline,
        title = {
            Text(
                stringResource(
                    when (fallback.route) {
                        FeedbackRoute.EMAIL -> R.string.feedback_fallback_title_email
                        FeedbackRoute.GITHUB -> R.string.feedback_fallback_title_github
                        FeedbackRoute.DISCORD -> R.string.feedback_fallback_title_discord
                    },
                ),
                style = GeistType.heading20,
                color = colors.primary,
            )
        },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                Text(
                    stringResource(R.string.feedback_fallback_message),
                    style = GeistType.copy14,
                    color = colors.secondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                OutlinedTextField(
                    value = report,
                    onValueChange = {
                        report = it
                        copied = false
                    },
                    label = { Text(stringResource(R.string.feedback_fallback_report_label)) },
                    textStyle = GeistType.copy14Mono,
                    minLines = 6,
                    modifier = Modifier.fillMaxWidth().testTag(FeedbackFallbackTestTags.REPORT),
                )
                if (copied) {
                    Spacer(modifier = Modifier.height(Spacing.xs))
                    Text(
                        stringResource(R.string.feedback_fallback_copied),
                        style = GeistType.copy13,
                        color = colors.secondary,
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { copied = copyReport(context, report) },
                modifier = Modifier.testTag(FeedbackFallbackTestTags.COPY),
            ) {
                Text(stringResource(R.string.feedback_fallback_copy), style = GeistType.button14, color = colors.brandPrimary)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.close), style = GeistType.button14) }
        },
    )
}

private fun copyReport(context: Context, report: String): Boolean {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return false
    return runCatching {
        clipboard.setPrimaryClip(
            ClipData.newPlainText(context.getString(R.string.feedback_fallback_report_label), report),
        )
    }.isSuccess
}
