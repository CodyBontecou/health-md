package com.healthmd.testing

import android.os.Bundle
import com.healthmd.BuildConfig

/**
 * Launch-scoped UI test mode for automation (Argent, adb), mirroring Apple's `TestMode.swift`.
 *
 * Only the isolated `e2e` build type honors it (`BuildConfig.TEST_MODE_AVAILABLE`). That build
 * installs as `com.healthmd.android.e2e`, so a test launch never reads or rewrites the data of
 * the debug or release app on the same phone. Opt in per launch with intent extras:
 *
 * ```
 * adb shell am start -S -n com.healthmd.android.e2e/com.healthmd.presentation.MainActivity \
 *   --ez uitesting true --es UITEST_HEALTH_AUTHORIZED true --es UITEST_SHOW_ONBOARDING true
 * ```
 *
 * Values may be passed as `--es` strings or `--ez`/`--ei` primitives. Once a process enters
 * test mode it stays there until the process ends (`am start -S` restarts it), so a later
 * `launch-app` that only brings the activity forward keeps the same scenario.
 *
 * While active, Health Connect is never touched: [HealthConnectManager] reports the scenario's
 * permission state and serves [TestModeHealthFixtures] instead of real records.
 */
object TestMode {
    const val EXTRA_ENABLED = "uitesting"

    const val KEY_HEALTH_AUTHORIZED = "UITEST_HEALTH_AUTHORIZED"
    const val KEY_HEALTH_PARTIAL = "UITEST_HEALTH_PARTIAL"
    const val KEY_SHOW_ONBOARDING = "UITEST_SHOW_ONBOARDING"
    const val KEY_HAS_COMPLETED_ONBOARDING = "UITEST_HAS_COMPLETED_ONBOARDING"
    const val KEY_PURCHASE_UNLOCKED = "UITEST_PURCHASE_UNLOCKED"
    const val KEY_FREE_EXPORTS_USED = "UITEST_FREE_EXPORTS_USED"
    const val KEY_STATIC_PURCHASE_PRICES = "UITEST_STATIC_PURCHASE_PRICES"

    /** One launch's deterministic configuration. Unset optional values leave stored state alone. */
    data class Scenario(
        val healthAuthorized: Boolean = false,
        /** Only [PARTIAL_GRANT_PERMISSIONS] are granted; exports still run on that partial access. */
        val healthPartiallyAuthorized: Boolean = false,
        val showsOnboarding: Boolean = false,
        val hasCompletedOnboarding: Boolean = true,
        val purchaseUnlocked: Boolean? = null,
        val freeExportsUsed: Int? = null,
        val staticPurchasePrices: Boolean = false,
    ) {
        /** The persisted onboarding flag this launch starts from. */
        val onboardingCompleted: Boolean get() = hasCompletedOnboarding && !showsOnboarding
    }

    @Volatile
    var scenario: Scenario? = null
        private set

    val isActive: Boolean get() = scenario != null

    /** Any read access is granted: full, or the partial scenario's subset. */
    val healthAuthorized: Boolean
        get() = scenario?.let { it.healthAuthorized || it.healthPartiallyAuthorized } == true

    /** Only a fixed subset of the requested read permissions is granted. */
    val healthPartiallyAuthorized: Boolean get() = scenario?.healthPartiallyAuthorized == true

    /** Record types granted by the partial scenario; every other requested type stays denied. */
    val PARTIAL_GRANT_PERMISSIONS: Set<String> = setOf(
        "android.permission.health.READ_STEPS",
        "android.permission.health.READ_HEART_RATE",
    )

    /** The partial scenario's grants within [requested], deterministic across devices. */
    fun partialGrant(requested: Set<String>): Set<String> = requested intersect PARTIAL_GRANT_PERMISSIONS

    /**
     * Activates test mode from a launch intent's extras. Returns the scenario only when this call
     * activated it, so the caller seeds persisted state once per process.
     */
    fun configure(extras: Bundle?, available: Boolean = BuildConfig.TEST_MODE_AVAILABLE): Scenario? {
        if (!available || isActive || extras == null) return null
        @Suppress("DEPRECATION") // Typed getters would reject a mix of --es and --ez values.
        val values = extras.keySet().associateWith { key -> extras.get(key)?.toString() }
        return parse(values, available)?.also { scenario = it }
    }

    /** Pure parser, separated from [Bundle] for unit tests. Does not activate test mode. */
    fun parse(values: Map<String, String?>, available: Boolean = true): Scenario? {
        if (!available || values[EXTRA_ENABLED].asFlag() != true) return null
        return Scenario(
            healthAuthorized = values[KEY_HEALTH_AUTHORIZED].asFlag() == true,
            healthPartiallyAuthorized = values[KEY_HEALTH_PARTIAL].asFlag() == true,
            showsOnboarding = values[KEY_SHOW_ONBOARDING].asFlag() == true,
            hasCompletedOnboarding = values[KEY_HAS_COMPLETED_ONBOARDING].asFlag() != false,
            purchaseUnlocked = values[KEY_PURCHASE_UNLOCKED].asFlag(),
            freeExportsUsed = values[KEY_FREE_EXPORTS_USED]?.trim()?.toIntOrNull()?.coerceAtLeast(0),
            staticPurchasePrices = values[KEY_STATIC_PURCHASE_PRICES].asFlag() == true,
        )
    }

    /** Unit-test hooks; production code never leaves test mode inside a process. */
    internal fun activateForTesting(value: Scenario?) {
        scenario = value
    }

    private fun String?.asFlag(): Boolean? = when (this?.trim()?.lowercase()) {
        "true", "1", "yes" -> true
        "false", "0", "no" -> false
        else -> null
    }
}
