package com.healthmd.presentation.oauth

import android.os.Bundle
import androidx.activity.ComponentActivity
import android.widget.Toast
import com.healthmd.R
import com.healthmd.data.health.oauth.OAuthAuthorizationException
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthFailureReason
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

@AndroidEntryPoint
class OAuthCallbackActivity : ComponentActivity() {
    @Inject lateinit var oauthAuthorizationManager: OAuthAuthorizationManager
    @Inject lateinit var settingsRepository: SettingsRepository

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val callbackUri = intent?.data
        if (callbackUri == null) {
            Timber.w("OAuth callback activity launched without a callback URI")
            Toast.makeText(this, getString(R.string.health_provider_sign_in_failed), Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        scope.launch {
            runCatching {
                val result = oauthAuthorizationManager.handleCallback(callbackUri)
                settingsRepository.setHealthProviderConnected(result.providerId, true)
                settingsRepository.setSelectedHealthProviderId(result.providerId)
                result
            }.onSuccess { result ->
                Toast.makeText(
                    this@OAuthCallbackActivity,
                    getString(
                        R.string.health_provider_connected,
                        providerDisplayName(result.providerId),
                    ),
                    Toast.LENGTH_SHORT,
                ).show()
            }.onFailure { error ->
                val failure = error as? OAuthAuthorizationException
                Timber.e(
                    error,
                    "OAuth callback failed: reason=%s",
                    failure?.reason?.name ?: "UNEXPECTED",
                )
                Toast.makeText(
                    this@OAuthCallbackActivity,
                    oauthFailureMessage(failure?.reason),
                    Toast.LENGTH_LONG,
                ).show()
            }
            finish()
        }
    }

    private fun providerDisplayName(providerId: String): String = getString(
        when (providerId) {
            "fitbit" -> R.string.health_provider_label_fitbit
            "withings" -> R.string.health_provider_label_withings
            "oura" -> R.string.health_provider_label_oura
            "polar" -> R.string.health_provider_label_polar
            "whoop" -> R.string.health_provider_label_whoop
            else -> R.string.health_provider_label_generic
        },
    )

    private fun oauthFailureMessage(reason: OAuthFailureReason?): String = getString(
        when (reason) {
            OAuthFailureReason.PROVIDER_DENIED -> R.string.health_provider_sign_in_denied
            OAuthFailureReason.INVALID_CALLBACK,
            OAuthFailureReason.INVALID_STATE,
            OAuthFailureReason.UNKNOWN_PROVIDER -> R.string.health_provider_sign_in_invalid_callback
            OAuthFailureReason.TOKEN_EXCHANGE_FAILED,
            OAuthFailureReason.INVALID_TOKEN_RESPONSE -> R.string.health_provider_sign_in_connection_failed
            null -> R.string.health_provider_sign_in_failed
        },
    )
}
