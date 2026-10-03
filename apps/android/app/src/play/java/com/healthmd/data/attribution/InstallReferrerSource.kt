package com.healthmd.data.attribution

import android.content.Context
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

interface InstallReferrerSource {
    /** Performs one bounded connection attempt. Transient retries are owned by the orchestrator. */
    suspend fun retrieve(): InstallReferrerResult
}

sealed interface InstallReferrerResult {
    data class Referrer(
        val rawReferrer: String,
        val referrerClickTimestampSeconds: Long?,
        val installBeginTimestampSeconds: Long?,
    ) : InstallReferrerResult

    data object Organic : InstallReferrerResult
    data object Unsupported : InstallReferrerResult
    data class TransientFailure(val reason: InstallReferrerFailureReason) : InstallReferrerResult
    data class PermanentFailure(val reason: InstallReferrerFailureReason) : InstallReferrerResult
}

enum class InstallReferrerFailureReason {
    SERVICE_UNAVAILABLE,
    SERVICE_DISCONNECTED,
    DEVELOPER_ERROR,
    PERMISSION_ERROR,
    CONFIGURATION_ERROR,
    UNKNOWN_TRANSIENT,
    UNKNOWN_PERMANENT,
}

@Singleton
class PlayInstallReferrerSource @Inject constructor(
    @ApplicationContext private val context: Context,
) : InstallReferrerSource {
    private val detailsScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override suspend fun retrieve(): InstallReferrerResult = try {
        withTimeoutOrNull(CONNECTION_TIMEOUT_MILLIS) { retrieveOnce() }
            ?: InstallReferrerResult.TransientFailure(
                InstallReferrerFailureReason.SERVICE_UNAVAILABLE
            )
    } catch (error: CancellationException) {
        throw error
    } catch (_: SecurityException) {
        InstallReferrerResult.PermanentFailure(InstallReferrerFailureReason.CONFIGURATION_ERROR)
    } catch (_: IllegalArgumentException) {
        InstallReferrerResult.PermanentFailure(InstallReferrerFailureReason.CONFIGURATION_ERROR)
    } catch (_: IllegalStateException) {
        InstallReferrerResult.PermanentFailure(InstallReferrerFailureReason.CONFIGURATION_ERROR)
    } catch (_: Exception) {
        InstallReferrerResult.TransientFailure(InstallReferrerFailureReason.UNKNOWN_TRANSIENT)
    }

    private suspend fun retrieveOnce(): InstallReferrerResult =
        suspendCancellableCoroutine { continuation ->
        val client = InstallReferrerClient.newBuilder(context).build()
        val completed = AtomicBoolean(false)

        fun complete(result: InstallReferrerResult) {
            if (!completed.compareAndSet(false, true)) return
            runCatching { client.endConnection() }
            continuation.resume(result)
        }

        continuation.invokeOnCancellation {
            if (completed.compareAndSet(false, true)) {
                runCatching { client.endConnection() }
            }
        }

        val listener = object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                when (responseCode) {
                    InstallReferrerClient.InstallReferrerResponse.OK -> {
                        // Play invokes setup callbacks on the main thread. Keep the synchronous
                        // Binder details call off it so attribution cannot stall app startup.
                        detailsScope.launch {
                            val result = try {
                                val details = client.installReferrer
                                val rawReferrer = details.installReferrer.orEmpty()
                                if (rawReferrer.isBlank()) {
                                    InstallReferrerResult.Organic
                                } else {
                                    InstallReferrerResult.Referrer(
                                        rawReferrer = rawReferrer,
                                        referrerClickTimestampSeconds =
                                            details.referrerClickTimestampSeconds.takeIf { it > 0L },
                                        installBeginTimestampSeconds =
                                            details.installBeginTimestampSeconds.takeIf { it > 0L },
                                    )
                                }
                            } catch (_: SecurityException) {
                                InstallReferrerResult.PermanentFailure(
                                    InstallReferrerFailureReason.CONFIGURATION_ERROR
                                )
                            } catch (_: IllegalStateException) {
                                InstallReferrerResult.TransientFailure(
                                    InstallReferrerFailureReason.SERVICE_DISCONNECTED
                                )
                            } catch (_: Exception) {
                                InstallReferrerResult.TransientFailure(
                                    InstallReferrerFailureReason.UNKNOWN_TRANSIENT
                                )
                            }
                            complete(result)
                        }
                    }

                    InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE -> complete(
                        InstallReferrerResult.TransientFailure(
                            InstallReferrerFailureReason.SERVICE_UNAVAILABLE
                        )
                    )

                    InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED ->
                        complete(InstallReferrerResult.Unsupported)

                    InstallReferrerClient.InstallReferrerResponse.DEVELOPER_ERROR -> complete(
                        InstallReferrerResult.PermanentFailure(
                            InstallReferrerFailureReason.DEVELOPER_ERROR
                        )
                    )

                    InstallReferrerClient.InstallReferrerResponse.PERMISSION_ERROR -> complete(
                        InstallReferrerResult.PermanentFailure(
                            InstallReferrerFailureReason.PERMISSION_ERROR
                        )
                    )

                    InstallReferrerClient.InstallReferrerResponse.SERVICE_DISCONNECTED -> complete(
                        InstallReferrerResult.TransientFailure(
                            InstallReferrerFailureReason.SERVICE_DISCONNECTED
                        )
                    )

                    else -> complete(
                        InstallReferrerResult.PermanentFailure(
                            InstallReferrerFailureReason.UNKNOWN_PERMANENT
                        )
                    )
                }
            }

            override fun onInstallReferrerServiceDisconnected() {
                complete(
                    InstallReferrerResult.TransientFailure(
                        InstallReferrerFailureReason.SERVICE_DISCONNECTED
                    )
                )
            }
        }

        try {
            client.startConnection(listener)
        } catch (_: SecurityException) {
            complete(
                InstallReferrerResult.PermanentFailure(
                    InstallReferrerFailureReason.CONFIGURATION_ERROR
                )
            )
        } catch (_: IllegalArgumentException) {
            complete(
                InstallReferrerResult.PermanentFailure(
                    InstallReferrerFailureReason.CONFIGURATION_ERROR
                )
            )
        } catch (_: IllegalStateException) {
            complete(
                InstallReferrerResult.PermanentFailure(
                    InstallReferrerFailureReason.CONFIGURATION_ERROR
                )
            )
        } catch (_: Exception) {
            complete(
                InstallReferrerResult.TransientFailure(
                    InstallReferrerFailureReason.UNKNOWN_TRANSIENT
                )
            )
        }
    }

    private companion object {
        const val CONNECTION_TIMEOUT_MILLIS = 5_000L
    }
}
