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

/**
 * Canonical Android-origin Shared Setup v1 document for the provider-share test below, embedded
 * byte-for-byte (including the fixture file's final LF) from
 * packages/contracts/shared-setup/v1/fixtures/android-shared-setup-v1.json — SHA-256:
 * 817e30ce6c3e1c7d2a74502608b7bc0cb203058b7aa5de1c3c9bef7c6c27ede5.
 *
 * SharedSetupDocumentStore.shareIntent validates every shared document through the strict
 * versioned dispatcher (SharedSetupV2Codec.decode inside validatedVersionedBytes), so opaque
 * filler bytes such as byteArrayOf(1, 2, 3) are correctly rejected as invalid JSON. The share
 * under test must therefore carry a production-valid document. The Android-origin v1 fixture is
 * the faithful choice: this provider publishes an Android-authored export (created_by platform
 * "android" plus its mandatory Android platform extension) and the default production writer
 * remains v1. Host-side, SharedSetupShareFixtureDocumentTest pins these exact bytes and proves
 * the same decode call the store performs accepts them.
 */
private val CANONICAL_ANDROID_SHARED_SETUP_V1: ByteArray = """{"created_by":{"app_version":"2.3.4-synthetic","platform":"android"},"metric_aliases":[{"android_selection_id":"hrv","apple_selection_id":null,"equivalence":"platform_distinct","semantic_id":"android.hrv_rmssd"},{"android_selection_id":"steps","apple_selection_id":"steps","equivalence":"platform_exact_or_unavailable","semantic_id":"steps"}],"metric_registry":{"registry_sha256":"4597c2f197c25e6e6a0ec1976e3b5de930edffa2ca61fd4779d47b465075bae2","registry_version":1,"schema":"healthmd.metric_registry"},"platform_extensions":{"android":{"export":{"compatibility_profile":"analytical_v5","folder_organization":"by_month","include_android_native_fields":true,"include_legacy_aliases":true,"subfolder":"family-health"},"extension_version":1},"apple":null},"profile":{"api_endpoint":{"credentials_required":true,"host":"setup.invalid","path":"/synthetic/upload","port":null,"query_omitted":true,"scheme":"https"},"daily_notes":{"create_if_missing":true,"enabled":true,"filename_template":"{date}","folder":"Daily","inject_sections":true},"export":{"filename_template":"health-{date}","folder_template":"Health/{year}/{month}","formats":["markdown","json"],"group_by_category":true,"include_granular_data":false,"include_metadata":true,"write_mode":"update"},"individual_entries":{"enabled":true,"entries_folder":"entries","filename_template":"{metric}-{date}-{time}","metrics":{"android.hrv_rmssd":{"custom_folder":"entries/heart","enabled":true},"steps":{"custom_folder":null,"enabled":false}},"organize_by_category":true},"metrics":{"enabled_ids":["android.hrv_rmssd","steps"]},"presentation":{"date_format":"iso8601","frontmatter":{"custom_values":{"setup_label":"Synthetic family profile"},"date_key":"date","fields":[{"enabled":true,"output_key":"daily_steps","source_key":"steps"},{"enabled":true,"output_key":"average_heart_rate","source_key":"average_heart_rate"}],"include_date":true,"include_type":true,"key_style":"snake_case","placeholders":["reflection"],"type_key":"type","type_value":"health-data"},"markdown":{"bullet_style":"dash","custom_text":"# Health — {{date}}\n\n{{#activity}}\n## Activity\n{{activity_metrics}}\n{{/activity}}\n","header_level":2,"include_summary":true,"origin_dialect":"portable","style":"custom","use_emoji":false},"time_format":"hour_24","units":"metric"},"schedule":{"activation_requested":true,"cadence":{"unit":"days","value":1},"date_window":"past_complete_days","desired_target":"api_endpoint","local_time":{"hour":6,"minute":0},"lookback_days":1}},"schema":"healthmd.shared_setup","schema_version":1}
""".encodeToByteArray()

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
        val share = SharedSetupDocumentStore(context).shareIntent(CANONICAL_ANDROID_SHARED_SETUP_V1)
        val uri = requireNotNull(
            IntentCompat.getParcelableExtra(share.intent, Intent.EXTRA_STREAM, Uri::class.java)
        )
        assertEquals("content", uri.scheme)
        assertEquals("${context.packageName}.shared-setup", uri.authority)
        assertArrayEquals(
            CANONICAL_ANDROID_SHARED_SETUP_V1,
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() },
        )
    }
}
