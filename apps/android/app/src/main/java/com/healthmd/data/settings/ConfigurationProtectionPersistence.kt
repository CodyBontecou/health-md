package com.healthmd.data.settings

import androidx.datastore.preferences.core.booleanPreferencesKey

/** Shared key for current, serialized configuration admission at durable write boundaries. */
internal object ConfigurationProtectionPersistence {
    val enabledKey = booleanPreferencesKey("prevent_accidental_changes")
}
