package com.healthmd.data.billing

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.healthmd.domain.billing.ClinicSponsorshipStorage
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class EncryptedClinicSponsorshipStorage @Inject constructor(
    @ApplicationContext context: Context,
) : ClinicSponsorshipStorage {
    private val preferences by lazy {
        val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(context, "clinic_sponsorship_secure_v1", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
    }

    override fun read(): String? = preferences.getString("session", null)

    override fun write(value: String) {
        check(preferences.edit().putString("session", value).commit()) { "secure_storage_unavailable" }
    }
}
