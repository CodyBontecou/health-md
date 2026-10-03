package com.healthmd.data.billing

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Test

class PurchaseLaunchAdmissionTest {

    @Test
    fun rejectsASecondPurchaseBeforeRunningItsPreparation() = runTest {
        val isPurchasing = MutableStateFlow(true)
        var preparationRan = false

        val result = withPurchaseLaunchAdmission(isPurchasing) {
            preparationRan = true
            true
        }

        assertThat(result).isNull()
        assertThat(preparationRan).isFalse()
        assertThat(isPurchasing.value).isTrue()
    }

    @Test
    fun preLaunchFailureReleasesAdmission() = runTest {
        val isPurchasing = MutableStateFlow(false)

        val result = withPurchaseLaunchAdmission(isPurchasing) { false }

        assertThat(result).isFalse()
        assertThat(isPurchasing.value).isFalse()
    }

    @Test
    fun successfulLaunchStaysAdmittedUntilPurchaseCallback() = runTest {
        val isPurchasing = MutableStateFlow(false)

        val result = withPurchaseLaunchAdmission(isPurchasing) { markFlowLaunched ->
            markFlowLaunched()
            true
        }

        assertThat(result).isTrue()
        assertThat(isPurchasing.value).isTrue()
    }

    @Test
    fun cancellationDuringPreparationReleasesAdmissionAndPropagates() = runTest {
        val isPurchasing = MutableStateFlow(false)
        var caught: CancellationException? = null

        try {
            withPurchaseLaunchAdmission<Boolean>(isPurchasing) {
                throw CancellationException("cancel preparation")
            }
        } catch (error: CancellationException) {
            caught = error
        }

        assertThat(caught).isNotNull()
        assertThat(caught?.message).isEqualTo("cancel preparation")
        assertThat(isPurchasing.value).isFalse()
    }
}
