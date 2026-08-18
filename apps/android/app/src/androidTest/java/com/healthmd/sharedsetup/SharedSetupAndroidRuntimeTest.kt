package com.healthmd.sharedsetup

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.core.content.IntentCompat
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SharedSetupAndroidRuntimeTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun templateTokenPatternCompilesAndValidatesOnAndroidIcu() {
        assertNull(SharedSetupCodec.templateSyntaxProblem("{{date}}"))
        assertNull(SharedSetupCodec.templateSyntaxProblem("{{#sleep}}- {{steps}}{{/sleep}}"))
        assertTrue(
            SharedSetupCodec.templateSyntaxProblem("{{#sleep}}{{/other}}")
                ?.contains("balanced") == true
        )
    }

    @Test
    fun reviewLineStacksWithoutOverlapAtLargeFontScale() {
        val density = ApplicationProvider.getApplicationContext<Context>()
            .resources.displayMetrics.density
        composeRule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(density, fontScale = 2f)) {
                ReviewLine("Unsupported items", "1")
            }
        }

        val label = composeRule.onNodeWithText("Unsupported items").fetchSemanticsNode().boundsInRoot
        val value = composeRule.onNodeWithText("1").fetchSemanticsNode().boundsInRoot
        assertTrue("Large-font value must follow its label: $label / $value", value.top >= label.bottom)
    }

    @Test
    fun reviewLineMirrorsLabelAndValueInRtl() {
        val density = ApplicationProvider.getApplicationContext<Context>()
            .resources.displayMetrics.density
        composeRule.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(density, fontScale = 1f),
                LocalLayoutDirection provides LayoutDirection.Rtl,
            ) {
                ReviewLine("Formats", "markdown, json")
            }
        }

        val label = composeRule.onNodeWithText("Formats").fetchSemanticsNode().boundsInRoot
        val value = composeRule.onNodeWithText("markdown, json").fetchSemanticsNode().boundsInRoot
        assertTrue("RTL label must be to the right of its value: $label / $value", label.left >= value.right)
    }

    @Test
    fun compatibilityStatusHasOneTalkBackDescription() {
        composeRule.setContent {
            MaterialTheme {
                SharedSetupCompatibilityCard(
                    SharedSetupCompatibilityItem(
                        status = SharedSetupCompatibilityStatus.REQUIRES_ACTION,
                        title = "Schedule",
                        detail = "Will remain off",
                    )
                )
            }
        }

        composeRule.onNode(
            hasContentDescription("Requires action: Schedule. Will remain off"),
            useUnmergedTree = false,
        ).assertExists()
        composeRule.onNodeWithText("Schedule", useUnmergedTree = false).assertDoesNotExist()
    }

    @Test
    fun successHeadingIsPoliteLiveRegionForTalkBack() {
        val review = SharedSetupReviewSummary(
            formats = emptyList(),
            metricCount = 0,
            filenameTemplate = "health-{date}",
            units = "metric",
            dailyNotesEnabled = false,
            individualEntriesEnabled = false,
            hasCustomContent = false,
            scheduleRequested = false,
            endpointDescription = null,
            items = emptyList(),
        )
        composeRule.setContent {
            MaterialTheme {
                Column {
                    SharedSetupSuccess(
                        result = SharedSetupApplyResult(review, canUndo = true),
                        pendingEndpoint = null,
                        onConfirmEndpoint = {},
                        onUndo = {},
                        onFinishSetup = {},
                    )
                }
            }
        }

        composeRule.onNodeWithText("Shared Setup Applied")
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
            .assert(
                SemanticsMatcher.expectValue(
                    SemanticsProperties.LiveRegion,
                    LiveRegionMode.Polite,
                )
            )
    }

    @Test
    fun registryIncludesPinnedAppleOnlyAliasEvidenceWithoutFabricatingAndroidSupport() {
        val registry = AndroidSharedSetupMetricRegistry()
        val appleHrv = requireNotNull(registry.bySemanticId["hrv"])

        assertEquals("hrv", appleHrv.appleSelectionId)
        assertNull(appleHrv.androidSelectionId)
        assertEquals("platform_exact_or_unavailable", appleHrv.equivalence)
        assertEquals("android.hrv_rmssd", registry.byAndroidSelectionId["hrv"]?.semanticId)
        assertTrue(registry.bySemanticId.size > ANDROID_SHARED_SETUP_ALIASES.size)
    }

    @Test
    fun sharedSetupProviderIsDistinctAndPublishesAReadableUniqueContentUri() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val shared = context.packageManager.resolveContentProvider(
            "${context.packageName}.shared-setup",
            0,
        )
        val clinician = context.packageManager.resolveContentProvider(
            "${context.packageName}.clinician-reports",
            0,
        )

        assertEquals(SharedSetupFileProvider::class.java.name, shared?.name)
        assertNotEquals(clinician?.name, shared?.name)
        val share = SharedSetupDocumentStore(context).shareIntent(byteArrayOf(1, 2, 3))
        val uri = requireNotNull(
            IntentCompat.getParcelableExtra(share.intent, Intent.EXTRA_STREAM, Uri::class.java)
        )
        assertEquals("content", uri.scheme)
        assertEquals("${context.packageName}.shared-setup", uri.authority)
        assertArrayEquals(
            byteArrayOf(1, 2, 3),
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() },
        )
    }
}
