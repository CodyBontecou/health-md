package com.healthmd.di

import com.healthmd.myselfclaim.MyselfClaimApi
import com.healthmd.myselfclaim.MyselfClaimVerifier
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object MyselfClaimModule {
    @Provides
    @Singleton
    fun provideMyselfClaimVerifier(): MyselfClaimVerifier = MyselfClaimApi()
}
