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
 * Canonical Android-origin Shared Setup v2 document for the provider-share test below, embedded
 * byte-for-byte (including the fixture file's final LF) from
 * packages/contracts/shared-setup/v2/fixtures/android-shared-setup-v2.json — SHA-256:
 * 1072b48321ec8a3a19c3dfd900108bac0527df62c57d0fd326ca82488ded72d0.
 *
 * SharedSetupDocumentStore.shareIntent validates every shared document through the strict
 * versioned dispatcher (SharedSetupV2Codec.decode inside validatedVersionedBytes), so opaque
 * filler bytes such as byteArrayOf(1, 2, 3) are correctly rejected as invalid JSON and the
 * pre-canonical v1 shape is rejected as unsupported. The share under test must therefore carry
 * a production-valid v2 document. The Android-origin v2 fixture is the faithful choice: this
 * provider publishes an Android-authored export (created_by platform "android" plus its
 * mandatory Android platform extensions) and the default production writer is v2. Host-side,
 * SharedSetupShareFixtureDocumentTest pins these exact bytes and proves the same decode call
 * the store performs accepts them.
 */
private val CANONICAL_ANDROID_SHARED_SETUP_V2: ByteArray = """{"active_profile":"profile-002","created_by":{"app_version":"5.0.0-synthetic","platform":"android"},"metric_aliases":[{"android_selection_id":"active_calories","apple_selection_id":"active_energy","equivalence":"mapped_alias","semantic_id":"active_energy"},{"android_selection_id":"hrv","apple_selection_id":null,"equivalence":"platform_distinct","semantic_id":"android.hrv_rmssd"},{"android_selection_id":"avg_hr","apple_selection_id":"heart_rate_avg","equivalence":"mapped_alias","semantic_id":"heart_rate_avg"},{"android_selection_id":"sleep_light","apple_selection_id":"sleep_core","equivalence":"mapped_alias","semantic_id":"sleep_core"},{"android_selection_id":"steps","apple_selection_id":"steps","equivalence":"platform_exact_or_unavailable","semantic_id":"steps"}],"metric_registry":{"registry_sha256":"4597c2f197c25e6e6a0ec1976e3b5de930edffa2ca61fd4779d47b465075bae2","registry_version":1,"schema":"healthmd.metric_registry"},"profiles":[{"bundle_id":"profile-001","daily_notes":{"create_if_missing":true,"enabled":true,"filename_template":"{date}","folder":"Daily","inject_sections":true},"destination":{"api_endpoint":{"credentials_required":true,"host":"setup.invalid","path":"/synthetic/android-compatibility","port":null,"query_omitted":true,"scheme":"https"},"kind":"api_endpoint"},"export":{"compatibility_detail":"selected_time_series","filename_template":"health-{date}","folder_template":"Health/{year}/{month}","formats":["json","markdown","obsidian_bases"],"group_by_category":true,"include_metadata":true,"write_mode":"update"},"individual_entries":{"enabled":true,"entries_folder":"entries","filename_template":"{metric}-{date}-{time}","metrics":{"heart_rate_avg":{"custom_folder":null,"enabled":false}},"organize_by_category":true},"metrics":{"enabled_ids":["active_energy","steps"]},"name":"Compatibility Export","platform_extensions":{"android":{"export":{"compatibility_profile":"frozen_v4","folder_organization":"by_year_month","include_android_native_fields":false,"include_legacy_aliases":true,"legacy_data_types":{"activity":true,"body":true,"heart":true,"medical_resources":false,"mindfulness":true,"mobility":true,"nutrition":false,"planned_workouts":false,"reproductive_health":false,"sleep":true,"vitals":true,"workouts":true},"legacy_primary_format":"markdown","mode":"compatibility","raw_snapshot":{"format":"ndjson","include_exercise_routes":true,"page_size":500,"scope":"selected_record_types"},"subfolder":"synthetic-health"},"extension_version":2},"apple":null},"presentation":{"date_format":"iso8601","frontmatter":{"custom_values":{"setup_label":"Synthetic setup"},"date_key":"date","fields":[{"enabled":true,"output_key":"average_heart_rate","source_key":"average_heart_rate"},{"enabled":true,"output_key":"daily_steps","source_key":"steps"}],"include_date":true,"include_type":true,"key_style":"snake_case","placeholders":["reflection","tag"],"type_key":"type","type_value":"health-data"},"markdown":{"bullet_style":"dash","custom_text":"# Health — {{date}}\n\n{{#activity}}\n## Activity\n{{activity_metrics}}\n{{/activity}}\n","header_level":2,"include_summary":true,"origin_dialect":"portable","style":"custom","use_emoji":false},"time_format":"hour_24","units":"metric"},"schedule":{"activation_requested":true,"cadence":{"anchor_date":"2025-02-01","unit":"days","value":1},"date_window":"past_complete_days","local_time":{"hour":6,"minute":0},"lookback_days":1,"weekday":6}},{"bundle_id":"profile-002","daily_notes":{"create_if_missing":true,"enabled":true,"filename_template":"{date}","folder":"Daily","inject_sections":true},"destination":{"api_endpoint":null,"kind":"device_folder"},"export":{"compatibility_detail":"summary","filename_template":"health-{date}","folder_template":"Health/{year}/{month}","formats":[],"group_by_category":true,"include_metadata":true,"write_mode":"update"},"individual_entries":{"enabled":true,"entries_folder":"entries","filename_template":"{metric}-{date}-{time}","metrics":{"sleep_core":{"custom_folder":"entries/sleep","enabled":false}},"organize_by_category":true},"metrics":{"enabled_ids":["android.hrv_rmssd"]},"name":"Raw Snapshot","platform_extensions":{"android":{"export":{"compatibility_profile":"analytical_v5","folder_organization":"flat","include_android_native_fields":true,"include_legacy_aliases":false,"legacy_data_types":{"activity":false,"body":false,"heart":false,"medical_resources":true,"mindfulness":false,"mobility":false,"nutrition":true,"planned_workouts":true,"reproductive_health":true,"sleep":false,"vitals":false,"workouts":false},"legacy_primary_format":"json","mode":"raw_snapshot","raw_snapshot":{"format":"json","include_exercise_routes":false,"page_size":1000,"scope":"all_authorized_supported_data"},"subfolder":"synthetic-health"},"extension_version":2},"apple":null},"presentation":{"date_format":"iso8601","frontmatter":{"custom_values":{"setup_label":"Synthetic setup"},"date_key":"date","fields":[{"enabled":true,"output_key":"average_heart_rate","source_key":"average_heart_rate"},{"enabled":true,"output_key":"daily_steps","source_key":"steps"}],"include_date":true,"include_type":true,"key_style":"snake_case","placeholders":["reflection","tag"],"type_key":"type","type_value":"health-data"},"markdown":{"bullet_style":"dash","custom_text":"# Health — {{date}}\n\n{{#activity}}\n## Activity\n{{activity_metrics}}\n{{/activity}}\n","header_level":2,"include_summary":true,"origin_dialect":"portable","style":"custom","use_emoji":false},"time_format":"hour_24","units":"metric"},"schedule":null}],"schema":"healthmd.shared_setup","schema_version":2}
""".encodeToByteArray()

@RunWith(AndroidJUnit4::class)
class SharedSetupAndroidRuntimeTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun templateTokenPatternCompilesAndValidatesOnAndroidIcu() {
        assertNull(SharedSetupTemplateSyntax.templateSyntaxProblem("{{date}}"))
        assertNull(SharedSetupTemplateSyntax.templateSyntaxProblem("{{#sleep}}- {{steps}}{{/sleep}}"))
        assertTrue(
            SharedSetupTemplateSyntax.templateSyntaxProblem("{{#sleep}}{{/other}}")
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
    fun undoneHeadingIsPoliteLiveRegionForTalkBack() {
        composeRule.setContent {
            MaterialTheme {
                Column {
                    SharedSetupV2Undone(onCancel = {})
                }
            }
        }

        composeRule.onNodeWithText("Import Undone")
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
        val share = SharedSetupDocumentStore(context).shareIntent(CANONICAL_ANDROID_SHARED_SETUP_V2)
        val uri = requireNotNull(
            IntentCompat.getParcelableExtra(share.intent, Intent.EXTRA_STREAM, Uri::class.java)
        )
        assertEquals("content", uri.scheme)
        assertEquals("${context.packageName}.shared-setup", uri.authority)
        assertArrayEquals(
            CANONICAL_ANDROID_SHARED_SETUP_V2,
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() },
        )
    }
}
