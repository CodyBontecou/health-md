package com.healthmd.myselfclaim

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@Composable
fun MyselfClaimScreen(onBack: () -> Unit, viewModel: MyselfClaimViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current.applicationContext
    val cancel = { viewModel.cancel(); onBack() }
    BackHandler(onBack = cancel)
    MyselfClaimContent(state, onVerify = {
        viewModel.verify { url ->
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        }
    }, onBack = cancel)
}

@Composable
internal fun MyselfClaimContent(state: MyselfClaimState, onVerify: () -> Unit, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().background(AppColors.bgPrimary)
        .verticalScroll(rememberScrollState()).safeDrawingPadding()
        .padding(Spacing.md).testTag("myself_claim_screen"),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SecondaryButton(stringResource(R.string.close), onClick = onBack,
            modifier = Modifier.testTag("myself_claim_close"))
        Text(stringResource(R.string.myself_claim_title),
            style = MaterialTheme.typography.headlineMedium, color = AppColors.textPrimary)
        GeistCard {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                Text(stringResource(R.string.myself_claim_intro),
                    style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary)
                Text(stringResource(R.string.myself_claim_disclosure),
                    style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
                Text(stringResource(R.string.myself_claim_account),
                    style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
            }
        }
        PrimaryButton(stringResource(if (state.busy) R.string.myself_claim_verifying
            else R.string.myself_claim_verify), onClick = onVerify, enabled = !state.busy,
            modifier = Modifier.testTag("myself_claim_verify"))
        if (state.busy) {
            Text(stringResource(R.string.myself_claim_verifying),
                style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        }
        if (state.awaitingUser) {
            Text(stringResource(R.string.myself_claim_awaiting_user),
                style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary,
                modifier = Modifier.testTag("myself_claim_awaiting_user")
                    .semantics { liveRegion = LiveRegionMode.Polite })
        }
        state.failure?.let { failure ->
            val message = when (failure) {
                MyselfClaimFailure.NO_PURCHASE -> R.string.myself_claim_no_purchase
                MyselfClaimFailure.STORE_UNAVAILABLE -> R.string.myself_claim_store_unavailable
                MyselfClaimFailure.VERIFICATION_FAILED -> R.string.myself_claim_verification_failed
                MyselfClaimFailure.BROWSER_UNAVAILABLE -> R.string.myself_claim_browser_unavailable
            }
            Text(stringResource(message), style = MaterialTheme.typography.bodyMedium,
                color = AppColors.error, modifier = Modifier.testTag("myself_claim_error")
                    .semantics { liveRegion = LiveRegionMode.Polite })
        }
    }
}
