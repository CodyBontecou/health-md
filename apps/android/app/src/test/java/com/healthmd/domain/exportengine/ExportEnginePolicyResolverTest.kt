package com.healthmd.domain.exportengine

import android.content.SharedPreferences
import com.google.common.truth.Truth.assertThat
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.Test

class ExportEnginePolicyResolverTest {
    private val allowCompatible = ExportEngineCompatibility { _, _ -> true }

    @Test
    fun injectedBuildConfigDefaultsResolvePerProfileAndForceApiV1ToFrozenV4() {
        val resolver = ExportEnginePolicyResolver(
            defaults = ExportEngineBuildDefaults(
                androidFrozenV4 = "shadow",
                androidAnalyticalV5 = "rust",
                apiV1FrozenV4 = "shadow",
            ),
            isDebugOrTestBuild = false,
            compatibility = allowCompatible,
        )

        assertThat(resolver.resolveLocal(AndroidExportProfile.android_frozen_v4).mode)
            .isEqualTo(ExportEngineMode.shadow)
        assertThat(resolver.resolveLocal(AndroidExportProfile.android_analytical_v5).mode)
            .isEqualTo(ExportEngineMode.rust)
        val api = resolver.resolveApiV1()
        assertThat(api.mode).isEqualTo(ExportEngineMode.shadow)
        assertThat(api.profile).isEqualTo(AndroidExportProfile.android_frozen_v4)
        assertThat(api.target).isEqualTo(ExportEnginePolicyTarget.API_V1_FROZEN_V4)
    }

    @Test
    fun missingUnknownAndIncompatibleValuesFailClosedToLegacy() {
        val unknown = ExportEnginePolicyResolver(
            defaults = ExportEngineBuildDefaults("RUST", "rust ", ""),
            isDebugOrTestBuild = false,
            compatibility = ExportEngineCompatibility { _, _ ->
                error("unknown values must not reach compatibility")
            },
        )
        assertThat(unknown.resolve(ExportEnginePolicyTarget.ANDROID_FROZEN_V4).mode)
            .isEqualTo(ExportEngineMode.legacy)
        assertThat(unknown.resolve(ExportEnginePolicyTarget.ANDROID_ANALYTICAL_V5).mode)
            .isEqualTo(ExportEngineMode.legacy)
        assertThat(unknown.resolve(ExportEnginePolicyTarget.API_V1_FROZEN_V4).mode)
            .isEqualTo(ExportEngineMode.legacy)

        val incompatible = ExportEnginePolicyResolver(
            defaults = ExportEngineBuildDefaults("shadow", "rust", "rust"),
            isDebugOrTestBuild = false,
            compatibility = ExportEngineCompatibility { _, _ -> false },
        )
        ExportEnginePolicyTarget.entries.forEach { target ->
            assertThat(incompatible.resolve(target).mode).isEqualTo(ExportEngineMode.legacy)
        }
    }

    @Test
    fun sharedPreferencesOverrideIsDebugOnlyAndReleaseNeverReadsIt() {
        val preferences = mockk<SharedPreferences>()
        every {
            preferences.getString(
                ExportEnginePolicyResolver.DEBUG_OVERRIDE_ANDROID_FROZEN_V4,
                null,
            )
        } returns "rust"
        val defaults = ExportEngineBuildDefaults("shadow", "legacy", "legacy")

        val debug = ExportEnginePolicyResolver(
            defaults = defaults,
            isDebugOrTestBuild = true,
            debugOverrides = preferences,
            compatibility = allowCompatible,
        )
        assertThat(debug.resolve(ExportEnginePolicyTarget.ANDROID_FROZEN_V4).mode)
            .isEqualTo(ExportEngineMode.rust)

        val release = ExportEnginePolicyResolver(
            defaults = defaults,
            isDebugOrTestBuild = false,
            debugOverrides = preferences,
            compatibility = allowCompatible,
        )
        assertThat(release.resolve(ExportEnginePolicyTarget.ANDROID_FROZEN_V4).mode)
            .isEqualTo(ExportEngineMode.shadow)
        verify(exactly = 1) {
            preferences.getString(
                ExportEnginePolicyResolver.DEBUG_OVERRIDE_ANDROID_FROZEN_V4,
                null,
            )
        }
    }
}
