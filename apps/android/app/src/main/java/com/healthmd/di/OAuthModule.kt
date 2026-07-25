package com.healthmd.di

import android.content.Context
import com.healthmd.data.health.oauth.EncryptedOAuthTokenStore
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthTokenStore
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object OAuthModule {
    @Provides
    @Singleton
    fun provideOAuthConfigRegistry(): OAuthConfigRegistry = OAuthConfigRegistry()

    @Provides
    @Singleton
    fun provideOAuthTokenStore(@ApplicationContext context: Context): OAuthTokenStore =
        EncryptedOAuthTokenStore(context)

    @Provides
    @Singleton
    fun provideOAuthAuthorizationManager(
        configRegistry: OAuthConfigRegistry,
        tokenStore: OAuthTokenStore,
    ): OAuthAuthorizationManager = OAuthAuthorizationManager(configRegistry, tokenStore)
}
