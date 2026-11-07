package com.healthmd.data.clinicsync

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject

/** F-Droid builds ship without Google Play services, so clinic sync requests are unavailable. */
class UnavailableClinicSyncPushTransport @Inject constructor() : ClinicSyncPushTransport {
    override val available: Boolean = false
    override suspend fun token(): String? = null
}

@Module
@InstallIn(SingletonComponent::class)
abstract class ClinicSyncPushModule {
    @Binds
    abstract fun bindPushTransport(transport: UnavailableClinicSyncPushTransport): ClinicSyncPushTransport
}
