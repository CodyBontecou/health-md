package com.healthmd.rawexport

import kotlinx.coroutines.flow.Flow

/** Streaming provider-native records; never converts records to compatibility HealthData. */
interface RawHealthRepository {
    suspend fun capabilities(): RawProviderCapabilities
    /** Complete, provider-specific report inventory. Health Connect retains its 54-entry ledger. */
    fun typeDefinitions(): List<RawProviderTypeDefinition> = RawExportTypeCatalog.definitions
    fun stream(request: RawSnapshotRequest): Flow<RawExportItem>
}
