package com.healthmd.testing

import com.healthmd.domain.billing.FreemiumPolicy
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.SettingsRepository

/**
 * Writes a [TestMode.Scenario]'s starting state into the e2e app's own storage, once per test
 * process, before the first screen resolves. Later in-app changes (finishing onboarding, using
 * the free export) then persist normally, as they would for a person using the app.
 */
object TestModeSeeder {
    suspend fun seed(
        scenario: TestMode.Scenario,
        settings: SettingsRepository,
        entitlements: EntitlementRepository,
    ) {
        settings.setOnboardingCompleted(scenario.onboardingCompleted)
        scenario.purchaseUnlocked?.let { unlocked ->
            settings.setPurchased(unlocked)
            entitlements.debugSetUnlocked(unlocked)
        }
        scenario.freeExportsUsed?.let { used ->
            settings.resetFreeExports()
            repeat(used.coerceAtMost(FreemiumPolicy.FREE_EXPORT_LIMIT)) { settings.recordFreeExportUse() }
        }
    }
}
