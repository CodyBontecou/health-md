package com.healthmd.rawexport

import kotlinx.coroutines.flow.Flow

/** Raw records are never converted to the compatibility HealthData model. */
interface RawHealthDataProvider {
    suspend fun capabilities(): RawProviderCapabilities
    fun stream(request: RawSnapshotRequest): Flow<RawExportItem>
}

/** Repository boundary used by orchestration; implementations must remain streaming. */
interface RawHealthRepository {
    suspend fun capabilities(): RawProviderCapabilities
    fun stream(request: RawSnapshotRequest): Flow<RawExportItem>
}

class DefaultRawHealthRepository(
    private val provider: RawHealthDataProvider,
) : RawHealthRepository {
    override suspend fun capabilities(): RawProviderCapabilities = provider.capabilities()
    override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = provider.stream(request)
}
