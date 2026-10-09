package com.healthmd.domain.exportengine

import android.content.SharedPreferences
import com.healthmd.BuildConfig
import com.healthmd.core.HealthMdCoreService

/** The API-v1 target is permanently tied to frozen-v4, regardless of local profile settings. */
enum class ExportEnginePolicyTarget(
    val profile: AndroidExportProfile,
    internal val overrideKey: String,
) {
    ANDROID_FROZEN_V4(
        AndroidExportProfile.android_frozen_v4,
        "export_engine.android_frozen_v4",
    ),
    ANDROID_ANALYTICAL_V5(
        AndroidExportProfile.android_analytical_v5,
        "export_engine.android_analytical_v5",
    ),
    API_V1_FROZEN_V4(
        AndroidExportProfile.android_frozen_v4,
        "export_engine.api_v1_frozen_v4",
    ),
    ANDROID_SLEEP_V6(
        AndroidExportProfile.android_sleep_v6,
        "export_engine.android_sleep_v6",
    ),
}

data class ExportEngineBuildDefaults(
    val androidFrozenV4: String,
    val androidAnalyticalV5: String,
    val apiV1FrozenV4: String,
) {
    fun valueFor(target: ExportEnginePolicyTarget): String = when (target) {
        ExportEnginePolicyTarget.ANDROID_FROZEN_V4 -> androidFrozenV4
        ExportEnginePolicyTarget.ANDROID_ANALYTICAL_V5 -> androidAnalyticalV5
        ExportEnginePolicyTarget.API_V1_FROZEN_V4 -> apiV1FrozenV4
        ExportEnginePolicyTarget.ANDROID_SLEEP_V6 -> "unqualified"
    }

    companion object {
        fun fromBuildConfig(): ExportEngineBuildDefaults = ExportEngineBuildDefaults(
            androidFrozenV4 = BuildConfig.EXPORT_ENGINE_ANDROID_FROZEN_V4,
            androidAnalyticalV5 = BuildConfig.EXPORT_ENGINE_ANDROID_ANALYTICAL_V5,
            apiV1FrozenV4 = BuildConfig.EXPORT_ENGINE_API_V1_FROZEN_V4,
        )
    }
}

fun interface ExportEngineCompatibility {
    /** Must return false rather than guessing when packaged core evidence cannot be verified. */
    fun isCompatible(mode: ExportEngineMode, profile: AndroidExportProfile): Boolean
}

/** Production compatibility gate backed by the packaged core self-test and registry snapshot. */
class HealthMdCoreEngineCompatibility(
    private val service: HealthMdCoreService = HealthMdCoreService(),
    private val validator: ExportEnginePinValidator = ExportEnginePinValidator(),
) : ExportEngineCompatibility {
    override fun isCompatible(
        mode: ExportEngineMode,
        profile: AndroidExportProfile,
    ): Boolean {
        if (profile == AndroidExportProfile.android_sleep_v6 && mode != ExportEngineMode.rust) return false
        if (mode == ExportEngineMode.legacy) return true
        return try {
            val readiness = service.checkReadiness()
            if (!readiness.isReady) return false
            val registry = service.getMetricRegistry(profile.coreProfile, profile.contractVersions.registry)
            val pin = ExportEnginePin.create(
                engine = mode,
                profile = profile,
                ianaTimeZone = "UTC",
                readiness = readiness,
                registry = registry,
            )
            validator.validate(pin, readiness, registry).isCompatible
        } catch (error: Throwable) {
            if (error.isFatalExportEngineFailure()) throw error
            false
        }
    }
}

data class ResolvedExportEnginePolicy(
    val mode: ExportEngineMode,
    val profile: AndroidExportProfile,
    val target: ExportEnginePolicyTarget,
)

/**
 * Resolves a profile mode without mutable production controls.
 *
 * SharedPreferences is dependency-injected only for debug/unit-test builds. Release builds never
 * read it. Historical missing/malformed/incompatible settings resolve to legacy. Wake-date has
 * no historical fallback and remains unavailable to fresh production policy until native qualification.
 */
class ExportEnginePolicyResolver(
    private val defaults: ExportEngineBuildDefaults = ExportEngineBuildDefaults.fromBuildConfig(),
    private val isDebugOrTestBuild: Boolean = BuildConfig.DEBUG,
    private val debugOverrides: SharedPreferences? = null,
    private val compatibility: ExportEngineCompatibility = HealthMdCoreEngineCompatibility(),
) {
    fun resolve(target: ExportEnginePolicyTarget): ResolvedExportEnginePolicy {
        check(target != ExportEnginePolicyTarget.ANDROID_SLEEP_V6) {
            "wake-date production policy is not qualified"
        }
        val configured = configuredValue(target)
        val parsed = ExportEngineMode.fromWireValue(configured)
        val resolved = if (
            parsed == ExportEngineMode.legacy || isCompatible(parsed, target.profile)
        ) {
            parsed
        } else {
            ExportEngineMode.legacy
        }
        return ResolvedExportEnginePolicy(
            mode = resolved,
            profile = target.profile,
            target = target,
        )
    }

    fun resolveLocal(profile: AndroidExportProfile): ResolvedExportEnginePolicy = resolve(
        when (profile) {
            AndroidExportProfile.android_frozen_v4 ->
                ExportEnginePolicyTarget.ANDROID_FROZEN_V4
            AndroidExportProfile.android_analytical_v5 ->
                ExportEnginePolicyTarget.ANDROID_ANALYTICAL_V5
            AndroidExportProfile.android_sleep_v6 ->
                ExportEnginePolicyTarget.ANDROID_SLEEP_V6
        },
    )

    fun resolveApiV1(): ResolvedExportEnginePolicy =
        resolve(ExportEnginePolicyTarget.API_V1_FROZEN_V4)

    private fun configuredValue(target: ExportEnginePolicyTarget): String? {
        val buildDefault = defaults.valueFor(target)
        if (!isDebugOrTestBuild || debugOverrides == null) return buildDefault
        return try {
            debugOverrides.getString(target.overrideKey, null) ?: buildDefault
        } catch (error: Throwable) {
            if (error.isFatalExportEngineFailure()) throw error
            // A stale, wrong-typed, or unreadable preference is an explicit invalid override.
            null
        }
    }

    private fun isCompatible(mode: ExportEngineMode, profile: AndroidExportProfile): Boolean = try {
        compatibility.isCompatible(mode, profile)
    } catch (error: Throwable) {
        if (error.isFatalExportEngineFailure()) throw error
        false
    }

    companion object {
        const val DEBUG_OVERRIDE_ANDROID_FROZEN_V4 = "export_engine.android_frozen_v4"
        const val DEBUG_OVERRIDE_ANDROID_ANALYTICAL_V5 = "export_engine.android_analytical_v5"
        const val DEBUG_OVERRIDE_API_V1_FROZEN_V4 = "export_engine.api_v1_frozen_v4"
    }
}
