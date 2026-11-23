package com.healthmd.presentation.common

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PlayStoreListingTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun opensThePlayStoreAppFirst() {
        val opened = mutableListOf<Intent>()
        assertThat(PlayStoreListing.open(context) { opened += it }).isTrue()
        assertThat(opened.map { it.dataString }).containsExactly("market://details?id=com.healthmd.android")
    }

    @Test
    fun fallsBackToTheWebListing() {
        val opened = mutableListOf<String?>()
        val result = PlayStoreListing.open(context) { intent ->
            if (intent.dataString!!.startsWith("market:")) throw ActivityNotFoundException()
            opened += intent.dataString
        }
        assertThat(result).isTrue()
        assertThat(opened).containsExactly("https://play.google.com/store/apps/details?id=com.healthmd.android")
    }

    @Test
    fun reportsWhenNothingCanOpenEither() {
        assertThat(PlayStoreListing.open(context) { throw ActivityNotFoundException() }).isFalse()
    }
}
