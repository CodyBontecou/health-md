package com.healthmd.localization

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.io.File

class MiscUserMessageLocalizationTest {

    @Test
    fun billingKeepsPlayDebugMessagesOutOfCustomerErrors() {
        val source = readSource("data/billing/BillingRepositoryImpl.kt")

        assertThat(source).contains("BillingError.PURCHASE_FAILED")
        assertThat(source).contains("MutableStateFlow<BillingError?>")
        assertThat(source).contains("debugMessage=%s")
        assertThat(source).doesNotContain("_purchaseError.value = \"Failed to start purchase:")
        assertThat(source).doesNotContain("_purchaseError.value = \"Purchase failed:")
        assertThat(source).doesNotContain("_purchaseError.value = \"Failed to restore:")
    }

    @Test
    fun oauthCallbackUsesTypedFailuresAndLocalizedProviderLabels() {
        val activity = readSource("presentation/oauth/OAuthCallbackActivity.kt")
        val manager = readSource("data/health/oauth/OAuthAuthorizationManager.kt")

        assertThat(activity).contains("providerDisplayName(result.providerId)")
        assertThat(activity).contains("oauthFailureMessage(failure?.reason)")
        assertThat(activity).doesNotContain("error.message ?: getString")
        assertThat(manager).contains("enum class OAuthFailureReason")
        assertThat(manager).contains("technicalMessage = \"OAuth token request failed")
    }

    @Test
    fun feedbackTemplateLocalizesLabelsWithoutChangingMarkdownStructure() {
        val source = readSource("presentation/common/FeedbackHelper.kt")

        assertThat(source).contains("R.string.feedback_diagnostic_app")
        assertThat(source).contains("R.string.feedback_issue_describe_heading")
        assertThat(source).contains("\"<!-- \${context.getString")
        assertThat(source).contains("\"1.\"")
        assertThat(source).doesNotContain("**Describe the issue**")
        assertThat(source).doesNotContain("|Platform: Android")
    }

    @Test
    fun automationKeepsResultAndPersistedWarningProtocolFieldsInvariant() {
        val source = readSource("automation/AutomationReceiver.kt")

        assertThat(source).contains("resultData is an automation protocol field")
        assertThat(source).contains("Persisted automation output is a public protocol field")
        assertThat(source).contains("result.protocolWarningSummary()")
        assertThat(source).contains("isFailure -> primaryFailureReason?.name")
        assertThat(source).doesNotContain("publishResult(RESULT_FAILURE, e.message")
        assertThat(source).doesNotContain("localizedWarningSummary")
    }

    private fun readSource(relativePath: String): String =
        File(repoRoot(), "app/src/main/java/com/healthmd/$relativePath").readText()

    private fun repoRoot(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            if (File(directory, "app/build.gradle.kts").exists()) return directory
            directory = directory.parentFile
        }
        error("Could not locate Android project root")
    }
}
