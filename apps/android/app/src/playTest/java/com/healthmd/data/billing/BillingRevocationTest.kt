package com.healthmd.data.billing

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PurchasesResponseListener
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.ProductDetailsResponseListener
import com.android.billingclient.api.QueryProductDetailsResult
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.domain.repository.PurchasePlan
import com.healthmd.export.MainDispatcherRule
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BillingRevocationTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    @Test fun successfulRestoreRemovesRevokedLifetimeFromBothDurableFlags() = runTest {
        val fixture = fixture(backgroundScope)
        val repository = fixture.repository
        assertThat(repository.isPermanentlyUnlocked.value).isTrue()
        assertThat(repository.restorePurchase()).isFalse()
        assertThat(repository.isUnlocked.value).isFalse()
        assertThat(repository.isPermanentlyUnlocked.value).isFalse()
        assertThat(fixture.prefs.getBoolean("is_unlocked", true)).isFalse()
        assertThat(fixture.purchased.value).isFalse()
    }

    @Test fun headlessVerificationRequeriesCachedLifetimeAndRemovesRevokedAccess() = runTest {
        val fixture = fixture(backgroundScope)
        assertThat(fixture.repository.verifyAccess()).isFalse()
        assertThat(fixture.purchased.value).isFalse()
        assertThat(fixture.prefs.getBoolean("is_unlocked", true)).isFalse()
    }

    @Test fun legacyBackupGrantSurvivesAnEmptySnapshotOnANewerInstallation() = runTest {
        val fixture = fixture(backgroundScope, legacyGrant = true)
        assertThat(fixture.repository.restorePurchase()).isTrue()
        assertThat(fixture.repository.isPermanentlyUnlocked.value).isTrue()
        assertThat(fixture.purchased.value).isTrue()
    }

    @Test fun originalLegacyInstallIsRecognizedEvenWithAnExistingLifetimeCache() = runTest {
        val fixture = fixture(backgroundScope, installTime = 1_770_000_000_000L)
        assertThat(fixture.repository.restorePurchase()).isTrue()
        assertThat(fixture.prefs.getBoolean("legacy_unlock_granted", false)).isTrue()
        assertThat(fixture.purchased.value).isTrue()
    }

    @Test fun failedQueriesPreserveCachedLifetimeAndItsOfflineHeadlessAdmission() = runTest {
        val fixture = fixture(backgroundScope, responseCode = BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED)
        assertThat(fixture.repository.restorePurchase()).isFalse()
        assertThat(fixture.repository.verifyAccess()).isTrue()
        assertThat(fixture.repository.isUnlocked.value).isTrue()
        assertThat(fixture.purchased.value).isTrue()
        assertThat(fixture.prefs.getBoolean("is_unlocked", false)).isTrue()
    }

    @Test fun unavailableInitialConnectionPreservesCachedLifetime() = runTest {
        val fixture = fixture(backgroundScope, setupCode = BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED)
        assertThat(fixture.repository.verifyAccess()).isTrue()
        assertThat(fixture.purchased.value).isTrue()
    }

    @Test fun partialCallbackWithoutLifetimeDoesNotRevokeCachedOwnership() = runTest {
        val fixture = fixture(backgroundScope)
        fixture.repository.onPurchasesUpdated(result(BillingClient.BillingResponseCode.OK), emptyList())
        runCurrent()
        assertThat(fixture.repository.isPermanentlyUnlocked.value).isTrue()
        assertThat(fixture.purchased.value).isTrue()
    }

    @Test fun validLifetimeStillRestoresAndPersists() = runTest {
        val fixture = fixture(backgroundScope, purchases = listOf(purchase(PurchasePlan.LIFETIME)))
        assertThat(fixture.repository.restorePurchase()).isTrue()
        assertThat(fixture.repository.isPermanentlyUnlocked.value).isTrue()
        assertThat(fixture.purchased.value).isTrue()
    }

    @Test fun subscriptionRetainsLiveAccessWithoutRetainingRefundedLifetimeFlags() = runTest {
        val fixture = fixture(backgroundScope, purchases = listOf(purchase(PurchasePlan.YEARLY)))
        assertThat(fixture.repository.restorePurchase()).isTrue()
        assertThat(fixture.repository.isUnlocked.value).isTrue()
        assertThat(fixture.repository.isPermanentlyUnlocked.value).isFalse()
        assertThat(fixture.purchased.value).isFalse()
        assertThat(fixture.prefs.getBoolean("is_unlocked", true)).isFalse()
    }

    @Test fun subscriptionOnlyRestartCannotUseAnOfflinePermanentGrant() = runTest {
        val fixture = fixture(backgroundScope, cached = false,
            setupCode = BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED)
        assertThat(fixture.repository.verifyAccess()).isFalse()
        assertThat(fixture.repository.isPermanentlyUnlocked.value).isFalse()
        assertThat(fixture.purchased.value).isFalse()
    }

    @Test fun settingsOnlyHistoricalGrantCannotBypassASuccessfulEmptyOwnershipQuery() = runTest {
        val fixture = fixture(backgroundScope, cached = false, settingsPurchased = true)
        assertThat(fixture.repository.verifyAccess()).isFalse()
        assertThat(fixture.purchased.value).isFalse()
    }

    @Test fun failedOwnershipQueryRemovesPreviouslyVerifiedSubscriptionSessionAccess() = runTest {
        val fixture = fixture(backgroundScope, cached = false,
            purchases = listOf(purchase(PurchasePlan.YEARLY)))
        assertThat(fixture.repository.verifyAccess()).isTrue()

        every { fixture.client.queryPurchasesAsync(any(), any<PurchasesResponseListener>()) } answers {
            secondArg<PurchasesResponseListener>().onQueryPurchasesResponse(
                result(BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE), emptyList(),
            )
        }

        assertThat(fixture.repository.verifyAccess()).isFalse()
        assertThat(fixture.repository.isUnlocked.value).isFalse()
        assertThat(fixture.repository.isPermanentlyUnlocked.value).isFalse()
        assertThat(fixture.purchased.value).isFalse()
        assertThat(fixture.prefs.getBoolean("is_unlocked", true)).isFalse()
    }

    @Test fun failedOwnershipQueryPreservesAnIndependentGrandfatheredGrant() = runTest {
        val fixture = fixture(backgroundScope, cached = false, legacyGrant = true,
            responseCode = BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE)

        assertThat(fixture.repository.verifyAccess()).isTrue()
        assertThat(fixture.repository.isUnlocked.value).isTrue()
        assertThat(fixture.prefs.getBoolean("legacy_unlock_granted", false)).isTrue()
    }

    @Test fun productQueryFailureBlocksCheckoutAndExplicitRecoveryDoesNotUnlockOrCharge() = runTest {
        val fixture = fixture(backgroundScope, cached = false)
        val details = mockk<ProductDetails> {
            every { productId } returns PurchasePlan.LIFETIME.productId
            every { oneTimePurchaseOfferDetails } returns mockk {
                every { formattedPrice } returns "19,99 €"
            }
        }
        fun productResponse(code: Int, products: List<ProductDetails>) {
            every { fixture.client.queryProductDetailsAsync(any(), any<ProductDetailsResponseListener>()) } answers {
                secondArg<ProductDetailsResponseListener>().onProductDetailsResponse(
                    result(code), QueryProductDetailsResult.create(products, emptyList()),
                )
            }
        }
        productResponse(BillingClient.BillingResponseCode.OK, listOf(details))
        fixture.repository.refresh()
        runCurrent()
        assertThat(fixture.repository.offers.value.single().localizedPriceText).isEqualTo("19,99 €")

        productResponse(BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE, emptyList())
        assertThat(fixture.repository.launchPurchase(mockk(relaxed = true), PurchasePlan.LIFETIME)).isFalse()
        assertThat(fixture.repository.offers.value).isEmpty()
        assertThat(fixture.repository.isUnlocked.value).isFalse()

        productResponse(BillingClient.BillingResponseCode.OK, listOf(details))
        fixture.repository.refresh()
        runCurrent()
        assertThat(fixture.repository.offers.value.single().localizedPriceText).isEqualTo("19,99 €")
        assertThat(fixture.repository.isUnlocked.value).isFalse()
        assertThat(fixture.purchased.value).isFalse()
        verify(exactly = 0) { fixture.client.launchBillingFlow(any(), any()) }
    }

    private data class Fixture(
        val repository: BillingRepositoryImpl,
        val prefs: SharedPreferences,
        val purchased: MutableStateFlow<Boolean>,
        val client: BillingClient,
    )

    private fun result(code: Int) = BillingResult.newBuilder().setResponseCode(code).build()

    private fun purchase(plan: PurchasePlan) = mockk<Purchase> {
        every { products } returns listOf(plan.productId)
        every { purchaseState } returns Purchase.PurchaseState.PURCHASED
        every { isAcknowledged } returns true
    }

    private fun fixture(
        scope: CoroutineScope,
        legacyGrant: Boolean = false,
        installTime: Long = 1_793_404_800_000L,
        responseCode: Int = BillingClient.BillingResponseCode.OK,
        setupCode: Int = BillingClient.BillingResponseCode.OK,
        purchases: List<Purchase> = emptyList(),
        cached: Boolean = true,
        settingsPurchased: Boolean = cached,
    ): Fixture {
        val app = ApplicationProvider.getApplicationContext<Context>()
        val prefs = app.getSharedPreferences("healthmd_purchase_prefs", Context.MODE_PRIVATE)
        prefs.edit().clear().putBoolean("is_unlocked", cached)
            .putBoolean("legacy_unlock_granted", legacyGrant).commit()
        val pm = mockk<PackageManager>()
        every { pm.getPackageInfo(any<String>(), any<Int>()) } returns PackageInfo().apply {
            firstInstallTime = installTime
        }
        val context = mockk<Context>()
        every { context.packageName } returns "com.healthmd.android"
        every { context.packageManager } returns pm
        every { context.getSharedPreferences("healthmd_purchase_prefs", Context.MODE_PRIVATE) } returns prefs
        val purchased = MutableStateFlow(settingsPurchased)
        val settings = mockk<SettingsRepository>()
        every { settings.isPurchased } returns purchased
        coEvery { settings.setPurchased(any()) } coAnswers { purchased.value = firstArg() }
        val client = mockk<BillingClient>(relaxed = true)
        every { client.startConnection(any()) } answers {
            firstArg<BillingClientStateListener>().onBillingSetupFinished(result(setupCode))
        }
        every { client.queryPurchasesAsync(any(), any<PurchasesResponseListener>()) } answers {
            secondArg<PurchasesResponseListener>().onQueryPurchasesResponse(result(responseCode), purchases)
        }
        return Fixture(BillingRepositoryImpl(context, settings, client, scope), prefs, purchased, client)
    }
}
