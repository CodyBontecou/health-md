package com.healthmd.rawexport

import com.google.common.truth.Truth.assertThat
import java.io.ByteArrayInputStream
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Test

class RawSnapshotApiClientTest {
    @Test fun rejectsPlainHttpBeforeOpeningSensitiveArtifact() = runTest {
        var opened = false
        val artifact = CompletedRawSnapshot(RawExportFormat.JSON, 2) {
            opened = true
            ByteArrayInputStream("{}".toByteArray())
        }
        val error = try {
            RawSnapshotApiClient(OkHttpClient()).upload("http://example.com/raw", artifact)
            null
        } catch (value: RawSnapshotApiException) {
            value
        }
        assertThat(error).isNotNull()
        assertThat(error!!.retryable).isFalse()
        assertThat(opened).isFalse()
    }

    @Test fun exposesVersionedContentTypes() {
        assertThat(RawSnapshotApiClient.contentType(RawExportFormat.JSON).toString())
            .isEqualTo("application/vnd.healthmd.raw-snapshot+json; version=1; charset=utf-8")
        assertThat(RawSnapshotApiClient.contentType(RawExportFormat.NDJSON).toString())
            .isEqualTo("application/x-ndjson; charset=utf-8")
    }
}
