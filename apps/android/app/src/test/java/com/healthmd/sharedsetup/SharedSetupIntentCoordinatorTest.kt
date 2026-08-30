package com.healthmd.sharedsetup

import android.content.Intent
import android.net.Uri
import androidx.core.content.IntentCompat
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import io.mockk.mockk
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class SharedSetupIntentCoordinatorTest {
    @Test
    fun `ordinary launch has no import and accepted bytes remain until the flow finishes`() = runTest {
        val coordinator = SharedSetupCoordinator(mockk(relaxed = true))
        assertThat(coordinator.imports.first()).isNull()

        coordinator.acceptBytes(byteArrayOf(1, 2, 3))
        val first = requireNotNull(coordinator.imports.first())
        assertThat(requireNotNull(first.bytes)).isEqualTo(byteArrayOf(1, 2, 3))

        // A newer warm request replaces the retained request, but merely observing it from a
        // hidden ViewModel cannot clear it before navigation reaches Shared Setup.
        coordinator.acceptBytes(byteArrayOf(4))
        val warm = requireNotNull(coordinator.imports.first())
        assertThat(warm.id).isGreaterThan(first.id)
        assertThat(requireNotNull(warm.bytes)).isEqualTo(byteArrayOf(4))

        coordinator.finishExternalImport()
        assertThat(coordinator.imports.first()).isNull()
    }

    @Test
    fun `external read failure is routed to the shared setup error screen`() = runTest {
        val store = mockk<SharedSetupDocumentStore>()
        val uri = Uri.parse("content://synthetic/unreadable.healthmdconfig")
        io.mockk.every { store.isSharedSetupDocument(uri) } returns true
        io.mockk.every { store.read(uri) } throws IllegalStateException("Synthetic read failure")
        val coordinator = SharedSetupCoordinator(store)

        assertThat(coordinator.acceptExternalUri(uri).isFailure).isTrue()
        val pending = coordinator.imports.first()
        assertThat(pending?.bytes).isNull()
        assertThat(pending?.errorMessage).contains("Synthetic read failure")
    }

    @Test
    fun `newer async uri is not blocked by an older stalled provider read`() = runTest {
        val store = mockk<SharedSetupDocumentStore>()
        val firstUri = Uri.parse("content://synthetic/first.healthmdconfig")
        val secondUri = Uri.parse("content://synthetic/second.healthmdconfig")
        val firstStarted = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        io.mockk.every { store.isSharedSetupDocument(any()) } returns true
        io.mockk.every { store.read(firstUri) } answers {
            firstStarted.countDown()
            check(releaseFirst.await(5, TimeUnit.SECONDS))
            byteArrayOf(1)
        }
        io.mockk.every { store.read(secondUri) } returns byteArrayOf(2)
        // Publish immediately where the read completes so the test observes results
        // without idling a paused Robolectric main looper.
        val coordinator = SharedSetupCoordinator(store, publishDispatcher = Dispatchers.Unconfined)

        try {
            coordinator.acceptExternalUriAsync(firstUri)
            assertThat(firstStarted.await(5, TimeUnit.SECONDS)).isTrue()
            coordinator.acceptExternalUriAsync(secondUri)

            val newest = withTimeout(5_000) {
                coordinator.imports.filterNotNull().first { pending ->
                    pending.bytes?.contentEquals(byteArrayOf(2)) == true
                }
            }
            assertThat(requireNotNull(newest.bytes)).isEqualTo(byteArrayOf(2))

            releaseFirst.countDown()
            delay(100)
            assertThat(requireNotNull(coordinator.imports.first()?.bytes))
                .isEqualTo(byteArrayOf(2))
        } finally {
            releaseFirst.countDown()
            coordinator.finishExternalImport()
        }
    }

    @Test
    fun `finish prevents a cancelled stalled read from publishing later`() = runTest {
        val store = mockk<SharedSetupDocumentStore>()
        val uri = Uri.parse("content://synthetic/stalled.healthmdconfig")
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        io.mockk.every { store.isSharedSetupDocument(uri) } returns true
        io.mockk.every { store.read(uri) } answers {
            started.countDown()
            check(release.await(5, TimeUnit.SECONDS))
            byteArrayOf(9)
        }
        // Publishing unconfined makes this test stronger: a read that wrongly survives
        // finish() would publish immediately instead of waiting on a paused looper.
        val coordinator = SharedSetupCoordinator(store, publishDispatcher = Dispatchers.Unconfined)

        try {
            coordinator.acceptExternalUriAsync(uri)
            assertThat(started.await(5, TimeUnit.SECONDS)).isTrue()
            coordinator.finishExternalImport()
            release.countDown()
            delay(100)

            assertThat(coordinator.imports.first()).isNull()
            assertThat(coordinator.restorableExternalBytes()).isNull()
            assertThat(coordinator.isExternalImportFinished()).isTrue()
        } finally {
            release.countDown()
            coordinator.finishExternalImport()
        }
    }

    @Test
    fun `accepted external bytes survive recreation until the flow is finished`() = runTest {
        val store = mockk<SharedSetupDocumentStore>()
        val uri = Uri.parse("content://synthetic/family.healthmdconfig")
        val bytes = byteArrayOf(7, 8, 9)
        io.mockk.every { store.isSharedSetupDocument(uri) } returns true
        io.mockk.every { store.read(uri) } returns bytes
        val coordinator = SharedSetupCoordinator(store)

        assertThat(coordinator.acceptExternalUri(uri).isSuccess).isTrue()
        assertThat(coordinator.restorableExternalBytes()).isEqualTo(bytes)
        assertThat(coordinator.isExternalImportFinished()).isFalse()

        coordinator.finishExternalImport()
        assertThat(coordinator.restorableExternalBytes()).isNull()
        assertThat(coordinator.isExternalImportFinished()).isTrue()

        coordinator.restoreExternalBytes(bytes)
        assertThat(requireNotNull(coordinator.imports.first()?.bytes)).isEqualTo(bytes)
        assertThat(coordinator.restorableExternalBytes()).isEqualTo(bytes)
        assertThat(coordinator.isExternalImportFinished()).isFalse()
    }

    @Test
    fun `unrelated octet stream document fails closed before reading`() = runTest {
        val store = mockk<SharedSetupDocumentStore>()
        val uri = Uri.parse("content://synthetic/unrelated.bin")
        io.mockk.every { store.isSharedSetupDocument(uri) } returns false
        val coordinator = SharedSetupCoordinator(store)

        assertThat(coordinator.acceptExternalUri(uri).isFailure).isTrue()
        assertThat(coordinator.imports.first()?.errorMessage).contains(".healthmdconfig")
        io.mockk.verify(exactly = 0) { store.read(any()) }
    }

    @Test
    fun `share artifacts use unique uris survive recipient handoff and are pruned`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = SharedSetupDocumentStore(context)
        val directory = File(context.cacheDir, "shared-setup")
        store.clearShareArtifacts()
        val provider = context.packageManager.resolveContentProvider(
            "${context.packageName}.shared-setup",
            0,
        )
        assertThat(provider?.name).isEqualTo(SharedSetupFileProvider::class.java.name)

        val first = store.shareIntent(byteArrayOf(1, 2, 3))
        val firstUri = requireNotNull(IntentCompat.getParcelableExtra(first.intent, Intent.EXTRA_STREAM, Uri::class.java))
        val firstDirectory = requireNotNull(directory.listFiles()?.singleOrNull())
        val second = store.shareIntent(byteArrayOf(4, 5, 6))
        val secondUri = requireNotNull(IntentCompat.getParcelableExtra(second.intent, Intent.EXTRA_STREAM, Uri::class.java))
        assertThat(secondUri).isNotEqualTo(firstUri)
        assertThat(directory.listFiles()?.toList()).hasSize(2)

        assertThat(firstDirectory.setLastModified(0)).isTrue()
        val firstHandoff = System.currentTimeMillis()
        assertThat(store.markShareHandoff(first.artifactID, firstHandoff)).isTrue()
        assertThat(store.markShareHandoff(second.artifactID, firstHandoff + 10_000)).isTrue()
        store.pruneExpiredShareArtifacts(firstHandoff + SHARED_SETUP_SHARE_RETENTION_MILLIS - 1)
        assertThat(directory.listFiles()?.toList()).hasSize(2)
        store.pruneExpiredShareArtifacts(firstHandoff + SHARED_SETUP_SHARE_RETENTION_MILLIS)
        assertThat(directory.listFiles()?.toList()).hasSize(1)

        directory.listFiles()?.forEach { assertThat(it.setLastModified(0)).isTrue() }
        val third = store.shareIntent(byteArrayOf(7, 8, 9))
        val thirdUri = requireNotNull(IntentCompat.getParcelableExtra(third.intent, Intent.EXTRA_STREAM, Uri::class.java))
        assertThat(thirdUri).isNotEqualTo(firstUri)
        assertThat(thirdUri).isNotEqualTo(secondUri)
        assertThat(directory.listFiles()?.toList()).hasSize(1)

        val retainedUris = mutableListOf(thirdUri)
        repeat(SHARED_SETUP_MAX_RETAINED_SHARE_ARTIFACTS - 1) { index ->
            val share = store.shareIntent(byteArrayOf(index.toByte()))
            retainedUris += requireNotNull(
                IntentCompat.getParcelableExtra(share.intent, Intent.EXTRA_STREAM, Uri::class.java)
            )
        }
        assertThat(directory.listFiles()?.toList())
            .hasSize(SHARED_SETUP_MAX_RETAINED_SHARE_ARTIFACTS)
        retainedUris.forEach { uri ->
            assertThat(context.contentResolver.openInputStream(uri)?.use { it.readBytes() }).isNotEmpty()
        }
        val capacityFailure = runCatching { store.shareIntent(byteArrayOf(99)) }.exceptionOrNull()
        assertThat(capacityFailure?.message).contains("earlier setup share")
        assertThat(directory.listFiles()?.toList())
            .hasSize(SHARED_SETUP_MAX_RETAINED_SHARE_ARTIFACTS)

        store.clearShareArtifacts()
        assertThat(directory.exists()).isFalse()
    }

    @Test
    fun `provider metadata requires content scheme allowed mime and queried setup filename`() {
        val uri = Uri.parse("content://synthetic/document/opaque-id")

        assertThat(isSharedSetupProviderMetadata(uri, SHARED_SETUP_MIME_TYPE, "Family.healthmdconfig")).isTrue()
        assertThat(isSharedSetupProviderMetadata(uri, "application/json", "Family.healthmdconfig")).isTrue()
        assertThat(isSharedSetupProviderMetadata(uri, "application/octet-stream", "Family.HEALTHMDCONFIG")).isTrue()
        assertThat(isSharedSetupProviderMetadata(uri, "application/octet-stream", "unrelated.bin")).isFalse()
        assertThat(isSharedSetupProviderMetadata(uri, "text/plain", "Family.healthmdconfig")).isFalse()
        assertThat(isSharedSetupProviderMetadata(uri, "application/octet-stream", null)).isFalse()
        assertThat(
            isSharedSetupProviderMetadata(
                Uri.parse("file:///sdcard/Family.healthmdconfig"),
                "application/octet-stream",
                "Family.healthmdconfig",
            )
        ).isFalse()
    }

    @Test
    fun `restoration reuses bytes skips same-process IO and retries an interrupted new process`() {
        assertThat(
            SharedSetupIntentExtractor.restorationAction(
                wasHandled = false,
                wasFinished = false,
                hasRestorableBytes = false,
                sameProcess = false,
            )
        ).isEqualTo(SharedSetupIntentRestoreAction.ACCEPT_SYSTEM_URI)
        assertThat(
            SharedSetupIntentExtractor.restorationAction(
                wasHandled = true,
                wasFinished = false,
                hasRestorableBytes = true,
                sameProcess = false,
            )
        ).isEqualTo(SharedSetupIntentRestoreAction.RESTORE_BYTES)
        assertThat(
            SharedSetupIntentExtractor.restorationAction(
                wasHandled = true,
                wasFinished = false,
                hasRestorableBytes = false,
                sameProcess = true,
            )
        ).isEqualTo(SharedSetupIntentRestoreAction.SKIP)
        assertThat(
            SharedSetupIntentExtractor.restorationAction(
                wasHandled = true,
                wasFinished = false,
                hasRestorableBytes = false,
                sameProcess = false,
            )
        ).isEqualTo(SharedSetupIntentRestoreAction.ACCEPT_SYSTEM_URI)
        assertThat(
            SharedSetupIntentExtractor.restorationAction(
                wasHandled = true,
                wasFinished = true,
                hasRestorableBytes = false,
                sameProcess = false,
            )
        ).isEqualTo(SharedSetupIntentRestoreAction.SKIP)
    }

    @Test
    fun `only action view exposes an external document uri without mutating the retained intent`() {
        val uri = Uri.parse("content://synthetic/shared.healthmdconfig")
        val external = Intent(Intent.ACTION_VIEW, uri).apply {
            clipData = android.content.ClipData.newRawUri("setup", uri)
        }

        assertThat(SharedSetupIntentExtractor.uri(external)).isEqualTo(uri)
        assertThat(external.action).isEqualTo(Intent.ACTION_VIEW)
        assertThat(external.data).isEqualTo(uri)
        assertThat(external.clipData).isNotNull()
        assertThat(SharedSetupIntentExtractor.uri(Intent(Intent.ACTION_SEND).setData(uri))).isNull()
        assertThat(SharedSetupIntentExtractor.uri(null)).isNull()
    }
}
