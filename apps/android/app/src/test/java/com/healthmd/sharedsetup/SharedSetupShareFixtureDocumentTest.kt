package com.healthmd.sharedsetup

import java.io.File
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Host-side guard for the document embedded in SharedSetupAndroidRuntimeTest's provider-share
 * test.
 *
 * SharedSetupDocumentStore.shareIntent funnels every shared byte sequence through
 * SharedSetupV2Codec.decode (see validatedVersionedBytes) and throws IllegalArgumentException on
 * any Invalid result, so the instrumentation fixture must be a production-valid Shared Setup
 * document rather than opaque filler bytes. These tests pin the frozen Android-origin v1 fixture
 * bytes, prove the exact decode the store performs accepts them, and prove share validation still
 * rejects the filler bytes the runtime test previously used.
 *
 * The native AndroidSharedSetupMetricRegistry cannot be constructed on the JVM, so the pinned
 * registry double below reproduces the production registry identity (version 1, sha256
 * 4597c2f1…). Because the identity matches, decode enforces the same metric-alias pinning as
 * production; the two aliases the fixture carries (android.hrv_rmssd platform_distinct, steps
 * platform_exact_or_unavailable) are asserted against the real registry on device by
 * SharedSetupAndroidRuntimeTest.registryIncludesPinnedAppleOnlyAliasEvidenceWithoutFabricatingAndroidSupport.
 */
class SharedSetupShareFixtureDocumentTest {
    @Test
    fun canonicalAndroidFixtureIsFrozenAndValidForShareValidation() {
        val bytes = fixtureFile().readBytes()

        assertEquals(ANDROID_FIXTURE_SHA_256, sha256(bytes))
        assertTrue(bytes.size <= SHARED_SETUP_MAX_BYTES)

        val decoded = SharedSetupV2Codec(ShareFixtureRegistry).decode(bytes)
        assertTrue(decoded is SharedSetupVersionedDecodeResult.Valid)
        assertTrue(
            (decoded as SharedSetupVersionedDecodeResult.Valid).document
                is SharedSetupDecodedDocument.V1,
        )
    }

    @Test
    fun shareValidationStillRejectsOpaqueFillerBytes() {
        val decoded = SharedSetupV2Codec(ShareFixtureRegistry).decode(byteArrayOf(1, 2, 3))

        assertTrue(decoded is SharedSetupVersionedDecodeResult.Invalid)
    }

    @Test
    fun instrumentationShareTestEmbedsTheCanonicalFixtureBytes() {
        val fixtureText = fixtureFile().readText()

        assertTrue(
            "SharedSetupAndroidRuntimeTest must embed the canonical Android v1 fixture verbatim",
            androidRuntimeTestSource().readText().contains(fixtureText),
        )
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun fixtureFile(): File = repositoryFile(
        "packages/contracts/shared-setup/v1/fixtures/android-shared-setup-v1.json",
    )

    private fun androidRuntimeTestSource(): File = repositoryFile(
        "apps/android/app/src/androidTest/java/com/healthmd/sharedsetup/SharedSetupAndroidRuntimeTest.kt",
    )

    private fun repositoryFile(path: String): File {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (true) {
            val candidate = File(directory, path)
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: error("Could not locate $path")
        }
    }

    /** Pins the production registry identity so decode enforces metric-alias pinning. */
    private object ShareFixtureRegistry : SharedSetupMetricRegistry {
        override val version: Int = 1
        override val sha256: String = "4597c2f197c25e6e6a0ec1976e3b5de930edffa2ca61fd4779d47b465075bae2"
        override val bySemanticId: Map<String, SharedSetupRegistryBinding> = listOf(
            SharedSetupRegistryBinding(
                semanticId = "android.hrv_rmssd",
                appleSelectionId = null,
                androidSelectionId = "hrv",
                equivalence = "platform_distinct",
            ),
            SharedSetupRegistryBinding(
                semanticId = "steps",
                appleSelectionId = "steps",
                androidSelectionId = "steps",
                equivalence = "platform_exact_or_unavailable",
            ),
        ).associateBy { it.semanticId }
        override val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding> =
            bySemanticId.values.mapNotNull { binding ->
                binding.androidSelectionId?.let { it to binding }
            }.toMap()
    }

    private companion object {
        const val ANDROID_FIXTURE_SHA_256 =
            "817e30ce6c3e1c7d2a74502608b7bc0cb203058b7aa5de1c3c9bef7c6c27ede5"
    }
}
