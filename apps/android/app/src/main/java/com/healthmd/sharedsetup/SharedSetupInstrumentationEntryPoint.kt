package com.healthmd.sharedsetup

import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/** Read-only access to real Shared Setup dependencies for on-device lifecycle instrumentation. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface SharedSetupInstrumentationEntryPoint {
    fun sharedSetupService(): SharedSetupService
    fun sharedSetupDocumentStore(): SharedSetupDocumentStore
}
