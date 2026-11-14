package com.healthmd.testing

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.export.FakeBillingRepository
import com.healthmd.export.FakeSettingsRepository
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Test

class TestModeTest {
    @After
    fun tearDown() = TestMode.activateForTesting(null)

    @Test
    fun `parse requires the uitesting flag and an e2e build`() {
        val values = mapOf(TestMode.EXTRA_ENABLED to "true", TestMode.KEY_HEALTH_AUTHORIZED to "true")

        assertThat(TestMode.parse(values, available = false)).isNull()
        assertThat(TestMode.parse(values - TestMode.EXTRA_ENABLED)).isNull()
        assertThat(TestMode.parse(values)?.healthAuthorized).isTrue()
    }

    @Test
    fun `parse mirrors Apple defaults and accepts adb string or primitive extras`() {
        val defaults = TestMode.parse(mapOf(TestMode.EXTRA_ENABLED to "1"))!!
        assertThat(defaults.healthAuthorized).isFalse()
        assertThat(defaults.onboardingCompleted).isTrue()
        assertThat(defaults.purchaseUnlocked).isNull()
        assertThat(defaults.freeExportsUsed).isNull()

        val scenario = TestMode.parse(
            mapOf(
                TestMode.EXTRA_ENABLED to "true",
                TestMode.KEY_SHOW_ONBOARDING to "TRUE",
                TestMode.KEY_PURCHASE_UNLOCKED to "false",
                TestMode.KEY_FREE_EXPORTS_USED to " 1 ",
                TestMode.KEY_STATIC_PURCHASE_PRICES to "yes",
            ),
        )!!
        assertThat(scenario.onboardingCompleted).isFalse()
        assertThat(scenario.purchaseUnlocked).isFalse()
        assertThat(scenario.freeExportsUsed).isEqualTo(1)
        assertThat(scenario.staticPurchasePrices).isTrue()

        val notCompleted = TestMode.parse(
            mapOf(TestMode.EXTRA_ENABLED to "true", TestMode.KEY_HAS_COMPLETED_ONBOARDING to "false"),
        )!!
        assertThat(notCompleted.onboardingCompleted).isFalse()
    }

    @Test
    fun `fixtures are deterministic synthetic days`() {
        val date = LocalDate.of(2026, 11, 12)
        val day = TestModeHealthFixtures.day(date)

        assertThat(day).isEqualTo(TestModeHealthFixtures.day(date))
        assertThat(day.hasAnyData).isTrue()
        assertThat(day.activity.steps).isNotEqualTo(TestModeHealthFixtures.day(date.minusDays(1)).activity.steps)
    }

    @Test
    fun `health connect manager never touches the client in test mode`() = runTest {
        // A strict mock fails on any call, proving no real Health Connect read or permission check.
        val manager = HealthConnectManager(mockk<Context>(relaxed = true), mockk<HealthConnectClient>())
        val today = LocalDate.now()

        TestMode.activateForTesting(TestMode.Scenario(healthAuthorized = true))
        assertThat(manager.isAvailable()).isTrue()
        assertThat(manager.hasAllPermissions()).isTrue()
        assertThat(manager.hasBackgroundReadPermission()).isTrue()
        assertThat(manager.getEarliestDataDate()).isEqualTo(TestModeHealthFixtures.earliestDate(today))
        assertThat(manager.fetchHealthData(today).hasAnyData).isTrue()
        val range = manager.fetchHealthDataRange(
            listOf(today.minusDays(1), today.plusDays(1)),
            DataTypeSelection(),
            includeGranularData = false,
        )
        assertThat(range.map { it.hasAnyData }).containsExactly(true, false).inOrder()

        TestMode.activateForTesting(TestMode.Scenario(healthAuthorized = false))
        assertThat(manager.hasAllPermissions()).isFalse()
        assertThat(manager.getGrantedPermissions()).isEmpty()
        assertThat(manager.fetchHealthData(today).hasAnyData).isFalse()
    }

    @Test
    fun `seeder writes the scenario's starting state`() = runTest {
        val settings = FakeSettingsRepository(initialPurchased = true)
        val entitlements = FakeBillingRepository(initialUnlocked = true)

        TestModeSeeder.seed(
            TestMode.Scenario(showsOnboarding = true, purchaseUnlocked = false, freeExportsUsed = 5),
            settings,
            entitlements,
        )

        assertThat(settings.hasCompletedOnboarding.first()).isFalse()
        assertThat(settings.isPurchased.first()).isFalse()
        assertThat(entitlements.isUnlocked.value).isFalse()
        assertThat(settings.getFreeExportsUsed()).isEqualTo(1)
    }
}
