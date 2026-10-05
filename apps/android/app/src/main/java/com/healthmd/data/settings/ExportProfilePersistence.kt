package com.healthmd.data.settings

import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.stringPreferencesKey
import com.healthmd.domain.model.ExportProfile
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.*

/** Local profile authority only; unrelated to the public Shared Setup grammar. */
internal object ExportProfilePersistence {
    val legacyProfilesKey = stringPreferencesKey("export_profiles")
    val legacyActiveKey = stringPreferencesKey("export_profiles_active_id")
    val profilesKey = stringPreferencesKey("export_profiles_v2")
    val activeKey = stringPreferencesKey("export_profiles_active_id_v2")
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }
    private val strictJson = Json { ignoreUnknownKeys = false }
    private val listSerializer = ListSerializer(ExportProfile.serializer())

    data class Decoded(
        val profiles: List<ExportProfile> = emptyList(),
        val records: List<JsonElement> = emptyList(),
        val corruptRoot: Boolean = false,
        val opaque: Boolean = false,
    ) {
        val blocksDefaultMigration: Boolean get() = corruptRoot || opaque
    }

    private fun hasEnvelope(prefs: Preferences): Boolean = prefs.asMap().containsKey(profilesKey)

    fun activeId(prefs: Preferences): String? =
        prefs.asMap()[if (hasEnvelope(prefs)) activeKey else legacyActiveKey] as? String

    fun decode(prefs: Preferences): Decoded {
        val envelope = hasEnvelope(prefs)
        val raw = prefs.asMap()[if (envelope) profilesKey else legacyProfilesKey]
        if (raw != null && raw !is String) return Decoded(corruptRoot = true)
        return decode(raw as? String, envelope)
    }

    private fun decode(raw: String?, envelope: Boolean): Decoded {
        if (raw == null) return Decoded()
        return runCatching {
            val root = json.parseToJsonElement(raw)
            val records = if (envelope) {
                val obj = root as? JsonObject ?: return Decoded(corruptRoot = true)
                // A future envelope must not be partially interpreted or fall back to legacy.
                if (obj.keys != setOf("version", "records") || obj["version"] != JsonPrimitive(2)) {
                    return Decoded(corruptRoot = true)
                }
                obj["records"] as? JsonArray ?: return Decoded(corruptRoot = true)
            } else root as? JsonArray ?: return Decoded(corruptRoot = true)
            val known = mutableListOf<ExportProfile>()
            var opaque = false
            records.forEach { record ->
                val profile = runCatching { strictJson.decodeFromJsonElement(ExportProfile.serializer(), record) }.getOrNull()
                if (profile == null || known.any { it.id == profile.id }) opaque = true else known += profile
            }
            Decoded(known, records.toList(), opaque = opaque)
        }.getOrElse { Decoded(corruptRoot = true) }
    }

    /** Transactions cannot prove preservation of future fields or undecodable records. */
    fun requireTransactionProfiles(prefs: Preferences): List<ExportProfile> {
        val decoded = decode(prefs)
        require(!decoded.blocksDefaultMigration)
        decoded.records.forEach { strictJson.decodeFromJsonElement(ExportProfile.serializer(), it) }
        return decoded.profiles
    }

    fun encode(profiles: List<ExportProfile>, envelope: Boolean, previous: Decoded? = null): String {
        if (!envelope) return json.encodeToString(listSerializer, profiles)
        val remaining = profiles.toMutableList()
        val seen = mutableSetOf<String>()
        val records = previous?.records.orEmpty().mapNotNull { record ->
            val old = runCatching { strictJson.decodeFromJsonElement(ExportProfile.serializer(), record) }.getOrNull()
            if (old == null || !seen.add(old.id)) record else {
                val index = remaining.indexOfFirst { it.id == old.id }
                if (index < 0) null else remaining.removeAt(index).let { updated ->
                    if (updated == old) record else json.encodeToJsonElement(ExportProfile.serializer(), updated)
                }
            }
        } + remaining.map { json.encodeToJsonElement(ExportProfile.serializer(), it) }
        return JsonObject(mapOf("version" to JsonPrimitive(2), "records" to JsonArray(records))).toString()
    }

    /** Append to an already validated records/list array without rewriting existing record bytes. */
    fun appendRecords(raw: String, encodedNewArray: String): String {
        val start = raw.indexOf('[')
        require(start >= 0)
        var depth = 0
        var quoted = false
        var escaped = false
        for (index in start until raw.length) {
            val char = raw[index]
            if (quoted) {
                if (escaped) escaped = false else if (char == '\\') escaped = true else if (char == '"') quoted = false
            } else when (char) {
                '"' -> quoted = true
                '[' -> depth++
                ']' -> {
                    depth--
                    if (depth == 0) {
                        val extra = encodedNewArray.trim().removePrefix("[").removeSuffix("]")
                        if (extra.isBlank()) return raw
                        val comma = if (raw.substring(start + 1, index).isBlank()) "" else ","
                        return raw.substring(0, index) + comma + extra + raw.substring(index)
                    }
                }
            }
        }
        error("Invalid profile records array")
    }

    /** Native edits lazily migrate, retaining all opaque records and the downgrade keys. */
    fun writeNative(prefs: MutablePreferences, decoded: Decoded, profiles: List<ExportProfile>) {
        check(!decoded.corruptRoot)
        val migrating = !hasEnvelope(prefs)
        val previousActive = activeId(prefs)
        prefs[profilesKey] = encode(profiles, envelope = true, previous = decoded)
        if (migrating) {
            (previousActive?.takeIf { id -> profiles.any { it.id == id } } ?: profiles.firstOrNull()?.id)
                ?.let { prefs[activeKey] = it }
        }
    }
}
