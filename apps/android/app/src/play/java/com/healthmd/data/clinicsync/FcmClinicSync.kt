package com.healthmd.data.clinicsync

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.healthmd.BuildConfig
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.android.AndroidEntryPoint
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * FCM transport for clinic sync requests. Firebase is initialized only from reviewed build
 * configuration and only when a token is first needed; auto-init and the init provider are
 * disabled in the Play manifest, so builds without configuration never contact Firebase.
 */
@Singleton
class FcmClinicSyncPushTransport @Inject constructor(
    @ApplicationContext private val context: Context,
) : ClinicSyncPushTransport {
    override val available: Boolean
        get() = listOf(BuildConfig.FIREBASE_PROJECT_ID, BuildConfig.FIREBASE_APPLICATION_ID,
            BuildConfig.FIREBASE_API_KEY, BuildConfig.FIREBASE_SENDER_ID).all { it.isNotBlank() }

    override suspend fun token(): String? {
        val messaging = messaging() ?: return null
        return suspendCancellableCoroutine { continuation ->
            messaging.token.addOnCompleteListener { task ->
                if (continuation.isActive) continuation.resume(task.result?.takeIf { task.isSuccessful })
            }
        }
    }

    private fun messaging(): FirebaseMessaging? {
        if (!available) return null
        synchronized(this) {
            if (FirebaseApp.getApps(context).isEmpty()) {
                FirebaseApp.initializeApp(context, FirebaseOptions.Builder()
                    .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
                    .setApplicationId(BuildConfig.FIREBASE_APPLICATION_ID)
                    .setApiKey(BuildConfig.FIREBASE_API_KEY)
                    .setGcmSenderId(BuildConfig.FIREBASE_SENDER_ID)
                    .build())
            }
        }
        return FirebaseMessaging.getInstance()
    }
}

/** Receives clinic sync request data messages and FCM token rotation. */
@AndroidEntryPoint
class HealthMdMessagingService : FirebaseMessagingService() {
    @Inject lateinit var clinicSync: ClinicSyncDoorbellManager

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMessageReceived(message: RemoteMessage) {
        ClinicSyncDoorbellMessages.requestedWakeId(message.data)?.let(clinicSync::onSyncRequestReceived)
    }

    override fun onNewToken(token: String) {
        scope.launch { clinicSync.reconcile() }
    }
}

@Module
@InstallIn(SingletonComponent::class)
abstract class ClinicSyncPushModule {
    @Binds
    abstract fun bindPushTransport(transport: FcmClinicSyncPushTransport): ClinicSyncPushTransport
}
