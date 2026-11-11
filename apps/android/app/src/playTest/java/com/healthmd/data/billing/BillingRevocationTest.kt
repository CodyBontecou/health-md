package com.healthmd.data.billing

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.ProductDetailsResponseListener
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsResult
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PurchasesResponseListener
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.billing.PlaySubscriptionVerifier
import com.healthmd.domain.billing.SubscriptionStatus
import com.healthmd.domain.billing.VerifiedPlaySubscription
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.domain.repository.PurchasePlan
import com.healthmd.export.MainDispatcherRule
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
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

    @Test fun freshInstallCanExportOfflineWithoutClaimingPaidAccess() = runTest {
        val fixture = fixture(backgroundScope, cached = false, freeExportsUsed = 0,
            setupCode = BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED)
        assertThat(fixture.repository.verifyAccess()).isTrue()
        assertThat(fixture.repository.isUnlocked.value).isFalse()
        assertThat(fixture.purchased.value).isFalse()
    }

    @Test fun fullSnapshotRemembersTheOwnedSubscriptionAndItsRenewalState() = runTest {
        val fixture = fixture(backgroundScope, cached = false, purchases = listOf(purchase(PurchasePlan.YEARLY)))
        assertThat(fixture.repository.restorePurchase()).isTrue()
        assertThat(fixture.repository.subscriptionStatus.value)
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = true))
        assertThat(fixture.prefs.getString(BillingRepositoryImpl.KEY_REMEMBERED_SUBSCRIPTION, null))
            .isEqualTo(PurchasePlan.YEARLY.productId)
    }

    @Test fun serverVerifiedPeriodEndIsAddedForTheOwnedToken() = runTest {
        val sent = mutableListOf<String>()
        val verifier = PlaySubscriptionVerifier { token ->
            sent += token
            VerifiedPlaySubscription(PurchasePlan.YEARLY.productId, "active", NOW + DAY, autoRenewing = true)
        }
        val fixture = fixture(backgroundScope, cached = false, purchases = listOf(purchase(PurchasePlan.YEARLY)), verifier = verifier)
        fixture.repository.restorePurchase()
        runCurrent()
        assertThat(fixture.repository.subscriptionStatus.value)
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = true, periodEndMillis = NOW + DAY))
        assertThat(sent).containsExactly("token-YEARLY")
        // A later snapshot reuses the answer instead of asking again.
        fixture.repository.restorePurchase()
        runCurrent()
        assertThat(sent).hasSize(1)
        assertThat((fixture.repository.subscriptionStatus.value as SubscriptionStatus.Subscribed).periodEndMillis)
            .isEqualTo(NOW + DAY)
    }

    @Test fun grandfatheredSubscriptionRetainsIndependentAccessThroughDateReadAndLapse() = runTest {
        val fixture = fixture(backgroundScope, cached = false, legacyGrant = true,
            purchases = listOf(purchase(PurchasePlan.YEARLY)),
            verifier = { VerifiedPlaySubscription(PurchasePlan.YEARLY.productId, "active", NOW + DAY, true) })
        fixture.repository.restorePurchase()
        runCurrent()
        assertThat(fixture.repository.subscriptionStatus.value).isEqualTo(
            SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = true,
                periodEndMillis = NOW + DAY, hasIncludedAccess = true),
        )
        every { fixture.client.queryPurchasesAsync(any(), any<PurchasesResponseListener>()) } answers {
            secondArg<PurchasesResponseListener>().onQueryPurchasesResponse(result(BillingClient.BillingResponseCode.OK), emptyList())
        }
        assertThat(fixture.repository.restorePurchase()).isTrue()
        assertThat(fixture.repository.subscriptionStatus.value).isEqualTo(SubscriptionStatus.IncludedAccess)
        assertThat(fixture.repository.isPermanentlyUnlocked.value).isTrue()
    }

    @Test fun mismatchedOrPastServerAnswersAreNeverShownAsADate() = runTest {
        for (answer in listOf(
            VerifiedPlaySubscription(PurchasePlan.WEEKLY.productId, "active", NOW + DAY, autoRenewing = true),
            VerifiedPlaySubscription(PurchasePlan.YEARLY.productId, "expired", NOW + DAY, autoRenewing = false),
            VerifiedPlaySubscription(PurchasePlan.YEARLY.productId, "active", NOW - DAY, autoRenewing = true),
        )) {
            val fixture = fixture(backgroundScope, cached = false, purchases = listOf(purchase(PurchasePlan.YEARLY)),
                verifier = { answer })
            fixture.repository.restorePurchase()
            runCurrent()
            assertThat((fixture.repository.subscriptionStatus.value as SubscriptionStatus.Subscribed).periodEndMillis).isNull()
        }
    }

    @Test fun failedServerReadsBackOffInsteadOfRetryingEveryRefresh() = runTest {
        var calls = 0
        var now = NOW
        val fixture = fixture(backgroundScope, cached = false, purchases = listOf(purchase(PurchasePlan.WEEKLY)),
            verifier = { calls++; null }, now = { now })
        fixture.repository.restorePurchase()
        runCurrent()
        fixture.repository.restorePurchase()
        runCurrent()
        assertThat(calls).isEqualTo(1)
        now += 61 * 60 * 1000L
        fixture.repository.restorePurchase()
        runCurrent()
        assertThat(calls).isEqualTo(2)
        assertThat(fixture.repository.subscriptionStatus.value)
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = true))
    }

    @Test fun unusableServerAnswersBackOffUntilAnHourThenRecover() = runTest {
        for (answer in listOf(
            VerifiedPlaySubscription(PurchasePlan.YEARLY.productId, "active", NOW + DAY, true),
            VerifiedPlaySubscription(PurchasePlan.WEEKLY.productId, "expired", NOW + DAY, false),
            VerifiedPlaySubscription(PurchasePlan.WEEKLY.productId, "active", NOW - DAY, true),
            VerifiedPlaySubscription(PurchasePlan.WEEKLY.productId, "active", NOW, true),
            VerifiedPlaySubscription(PurchasePlan.WEEKLY.productId, "active", null, true),
        )) {
            var calls = 0
            var now = NOW
            val fixture = fixture(backgroundScope, cached = false, purchases = listOf(purchase(PurchasePlan.WEEKLY)),
                verifier = {
                    calls++
                    if (calls == 1) answer else VerifiedPlaySubscription(PurchasePlan.WEEKLY.productId, "active", NOW + DAY, true)
                }, now = { now })
            fixture.repository.restorePurchase()
            runCurrent()
            assertThat((fixture.repository.subscriptionStatus.value as SubscriptionStatus.Subscribed).periodEndMillis).isNull()
            now += 60 * 60 * 1000L - 1
            fixture.repository.restorePurchase()
            runCurrent()
            assertThat(calls).isEqualTo(1)
            now++
            fixture.repository.restorePurchase()
            runCurrent()
            assertThat(calls).isEqualTo(2)
            assertThat((fixture.repository.subscriptionStatus.value as SubscriptionStatus.Subscribed).periodEndMillis).isEqualTo(NOW + DAY)
        }
    }

    @Test fun emptySnapshotAfterARememberedSubscriptionReportsALapse() = runTest {
        val fixture = fixture(backgroundScope, cached = false)
        fixture.prefs.edit().putString(BillingRepositoryImpl.KEY_REMEMBERED_SUBSCRIPTION, PurchasePlan.WEEKLY.productId).commit()
        assertThat(fixture.repository.restorePurchase()).isFalse()
        assertThat(fixture.repository.subscriptionStatus.value).isEqualTo(SubscriptionStatus.Ended(PurchasePlan.WEEKLY))
        // The memory survives so the lapse is still shown on the next launch.
        assertThat(fixture.prefs.getString(BillingRepositoryImpl.KEY_REMEMBERED_SUBSCRIPTION, null))
            .isEqualTo(PurchasePlan.WEEKLY.productId)
    }

    @Test fun emptySnapshotWithoutHistoryIsFree() = runTest {
        val fixture = fixture(backgroundScope, cached = false)
        fixture.repository.restorePurchase()
        assertThat(fixture.repository.subscriptionStatus.value).isEqualTo(SubscriptionStatus.Free)
    }

    @Test fun failedQueryNeverReportsALapse() = runTest {
        val fixture = fixture(backgroundScope, cached = false, responseCode = BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE)
        fixture.prefs.edit().putString(BillingRepositoryImpl.KEY_REMEMBERED_SUBSCRIPTION, PurchasePlan.WEEKLY.productId).commit()
        fixture.repository.restorePurchase()
        assertThat(fixture.repository.subscriptionStatus.value).isEqualTo(SubscriptionStatus.Unknown)
    }

    @Test fun yearlySwitchDoesNotLaunchAfterWeeklyOwnershipChangesDuringCatalogRead() = runTest {
        val fixture = fixture(backgroundScope, cached = false, purchases = listOf(purchase(PurchasePlan.WEEKLY)))
        fun phase(price: Long, mode: Int, cycles: Int, formatted: String) = mockk<ProductDetails.PricingPhase> {
            every { billingPeriod } returns "P1Y"
            every { priceAmountMicros } returns price
            every { priceCurrencyCode } returns "USD"
            every { recurrenceMode } returns mode
            every { billingCycleCount } returns cycles
            every { formattedPrice } returns formatted
        }
        val introductory = phase(19_990_000, ProductDetails.RecurrenceMode.FINITE_RECURRING, 1, "USD 19.99")
        val recurring = phase(29_990_000, ProductDetails.RecurrenceMode.INFINITE_RECURRING, 0, "USD 29.99")
        val offer = mockk<ProductDetails.SubscriptionOfferDetails> {
            every { basePlanId } returns YearlySwitchOfferIds.BASE_PLAN_ID
            every { offerId } returns YearlySwitchOfferIds.OFFER_ID
            every { offerTags } returns listOf(YearlySwitchOfferIds.TAG)
            every { offerToken } returns "switch-token"
            every { pricingPhases } returns mockk {
                every { pricingPhaseList } returns listOf(introductory, recurring)
            }
        }
        val details = mockk<ProductDetails>(relaxed = true) {
            every { productId } returns PurchasePlan.YEARLY.productId
            every { productType } returns BillingClient.ProductType.SUBS
            every { oneTimePurchaseOfferDetails } returns null
            every { subscriptionOfferDetails } returns listOf(offer)
        }
        val ok = result(BillingClient.BillingResponseCode.OK)
        every { fixture.client.launchBillingFlow(any(), any()) } returns ok
        val catalog = QueryProductDetailsResult.create(listOf(details), emptyList())
        var holdNextCatalogRead = false
        var pendingCatalog: ProductDetailsResponseListener? = null
        every { fixture.client.queryProductDetailsAsync(any(), any<ProductDetailsResponseListener>()) } answers {
            val listener = secondArg<ProductDetailsResponseListener>()
            if (holdNextCatalogRead) {
                holdNextCatalogRead = false
                pendingCatalog = listener
            } else {
                listener.onProductDetailsResponse(ok, catalog)
            }
        }

        fixture.repository.refresh()
        runCurrent()
        assertThat(fixture.repository.yearlySwitchOffer.value).isNotNull()
        assertThat(fixture.repository.subscriptionStatus.value)
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = true))

        holdNextCatalogRead = true
        val launch = async { fixture.repository.launchYearlySwitch(mockk<Activity>(relaxed = true)) }
        runCurrent()
        val listener = checkNotNull(pendingCatalog)
        every { fixture.client.queryPurchasesAsync(any(), any<PurchasesResponseListener>()) } answers {
            secondArg<PurchasesResponseListener>().onQueryPurchasesResponse(ok, emptyList())
        }
        assertThat(fixture.repository.restorePurchase()).isFalse()
        assertThat(fixture.repository.subscriptionStatus.value).isEqualTo(SubscriptionStatus.Ended(PurchasePlan.WEEKLY))
        listener.onProductDetailsResponse(ok, catalog)

        assertThat(launch.await()).isFalse()
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
        every { isAutoRenewing } returns true
        every { purchaseToken } returns "token-${plan.name}"
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
        freeExportsUsed: Int = 1,
        verifier: PlaySubscriptionVerifier? = null,
        now: () -> Long = { NOW },
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
        coEvery { settings.getFreeExportsUsed() } returns freeExportsUsed
        coEvery { settings.setPurchased(any()) } coAnswers { purchased.value = firstArg() }
        val client = mockk<BillingClient>(relaxed = true)
        every { client.startConnection(any()) } answers {
            firstArg<BillingClientStateListener>().onBillingSetupFinished(result(setupCode))
        }
        every { client.queryPurchasesAsync(any(), any<PurchasesResponseListener>()) } answers {
            secondArg<PurchasesResponseListener>().onQueryPurchasesResponse(result(responseCode), purchases)
        }
        return Fixture(BillingRepositoryImpl(context, settings, client, scope, verifier, now), prefs, purchased, client)
    }

    private companion object {
        const val NOW = 1_800_000_000_000L
        const val DAY = 24 * 60 * 60 * 1000L
    }
}
