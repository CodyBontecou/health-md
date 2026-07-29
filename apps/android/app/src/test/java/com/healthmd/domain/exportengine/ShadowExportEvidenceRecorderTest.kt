package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ShadowExportEvidenceRecorderTest {
    @get:Rule
    val temporary = TemporaryFolder()

    @Test
    fun storePersistsOnlyClosedHealthFreeAggregateCounters() {
        val file = temporary.newFile("evidence.json")
        file.delete()
        val store = FileAndroidShadowExportEvidenceStore(file)

        store.record(comparison(matches = true))
        store.record(
            comparison(
                matches = false,
                mismatchCount = 3,
                dimensions = setOf(
                    ExportArtifactMismatchDimension.BYTES,
                    ExportArtifactMismatchDimension.SHA256,
                ),
            ),
        )
        store.record(failure(ShadowRustFailureCode.INVALID_PLAN))

        val snapshot = store.snapshot()
        assertThat(snapshot.profiles).hasSize(1)
        val profile = snapshot.profiles.single()
        assertThat(profile.comparisonCount).isEqualTo(2)
        assertThat(profile.exactMatchCount).isEqualTo(1)
        assertThat(profile.mismatchOperationCount).isEqualTo(1)
        assertThat(profile.reportedMismatchCount).isEqualTo(3)
        assertThat(profile.rustFailureCount).isEqualTo(1)
        assertThat(profile.mismatchDimensions).containsExactly("BYTES", 1L, "SHA256", 1L)
        assertThat(profile.rustFailureCodes).containsExactly("INVALID_PLAN", 1L)
        val persisted = file.readText()
        assertThat(persisted).doesNotContain("expectedSha256")
        assertThat(persisted).doesNotContain("actualSha256")
        assertThat(persisted).doesNotContain("artifactIndex")
        assertThat(persisted).doesNotContain("firstByteOffset")
        assertThat(persisted).doesNotContain("relativePath")
    }

    @Test
    fun corruptionResetsEvidenceAndConcurrentUpdatesAreSerialized() {
        val file = temporary.newFile("corrupt.json")
        file.writeText("private-health-marker")
        val store = FileAndroidShadowExportEvidenceStore(file)
        assertThat(store.snapshot()).isEqualTo(AndroidShadowExportEvidenceSnapshot.EMPTY)

        val executor = Executors.newFixedThreadPool(8)
        repeat(100) {
            executor.execute { store.record(comparison(matches = true)) }
        }
        executor.shutdown()
        assertThat(executor.awaitTermination(10, TimeUnit.SECONDS)).isTrue()

        val profile = store.snapshot().profiles.single()
        assertThat(profile.comparisonCount).isEqualTo(100)
        assertThat(profile.exactMatchCount).isEqualTo(100)
        assertThat(file.readText()).doesNotContain("private-health-marker")
    }

    @Test
    fun countersSaturateAndResetRemovesTheJournal() {
        val file = temporary.newFile("saturated.json")
        val saturated = AndroidShadowExportEvidenceSnapshot(
            profiles = listOf(
                AndroidShadowExportProfileEvidence(
                    profile = AndroidExportProfile.android_frozen_v4.name,
                    semanticProfileRevision = 1u,
                    renderProfileRevision = 1u,
                    comparisonCount = Long.MAX_VALUE,
                    exactMatchCount = Long.MAX_VALUE,
                ),
            ),
        )
        file.writeText(Json.encodeToString(saturated))
        val store = FileAndroidShadowExportEvidenceStore(file)

        store.record(comparison(matches = true))

        val profile = store.snapshot().profiles.single()
        assertThat(profile.comparisonCount).isEqualTo(Long.MAX_VALUE)
        assertThat(profile.exactMatchCount).isEqualTo(Long.MAX_VALUE)
        store.reset()
        assertThat(file.exists()).isFalse()
        assertThat(store.snapshot()).isEqualTo(AndroidShadowExportEvidenceSnapshot.EMPTY)
    }

    private fun comparison(
        matches: Boolean,
        mismatchCount: Int = if (matches) 0 else 1,
        dimensions: Set<ExportArtifactMismatchDimension> = if (matches) emptySet()
        else setOf(ExportArtifactMismatchDimension.BYTES),
    ): AndroidShadowEvidenceEvent.Comparison = AndroidShadowEvidenceEvent.Comparison(
        profile = AndroidExportProfile.android_frozen_v4,
        semanticProfileRevision = 1u,
        renderProfileRevision = 1u,
        matches = matches,
        mismatchCount = mismatchCount,
        dimensions = dimensions,
    )

    private fun failure(code: ShadowRustFailureCode): AndroidShadowEvidenceEvent.RustFailure =
        AndroidShadowEvidenceEvent.RustFailure(
            profile = AndroidExportProfile.android_frozen_v4,
            semanticProfileRevision = 1u,
            renderProfileRevision = 1u,
            code = code,
        )
}
