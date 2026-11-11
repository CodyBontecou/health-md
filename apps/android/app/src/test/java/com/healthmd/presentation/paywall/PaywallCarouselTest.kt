package com.healthmd.presentation.paywall

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchasePlan
import org.junit.Test

class PaywallCarouselTest {
    private val weekly = PurchaseOffer("w", "$0.99", PurchasePlan.WEEKLY, hasSevenDayTrial = true)
    private val yearly = PurchaseOffer("y", "$29.99", PurchasePlan.YEARLY, hasSevenDayTrial = true)
    private val lifetime = PurchaseOffer("l", "$49.99", PurchasePlan.LIFETIME)

    @Test
    fun plansShowYearlyThenWeeklyThenLifetime() {
        assertThat(paywallPlanOrder(listOf(lifetime, weekly, yearly))).containsExactly(yearly, weekly, lifetime).inOrder()
    }

    @Test
    fun theTrialSlideNeedsAPlayTrialOffer() {
        assertThat(paywallShowsTrialSlide(listOf(lifetime))).isFalse()
        assertThat(paywallShowsTrialSlide(listOf(lifetime, weekly))).isTrue()
        assertThat(paywallShowsTrialSlide(emptyList())).isFalse()
    }
}
