package com.healthmd.sharedsetup

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import com.google.common.truth.Truth.assertThat
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class SharedSetupVersionedIoTest {
    @Test
    fun `outer stream reads exact four MiB closes and probes only one overflow byte`() {
        val exact = CountingInputStream(SHARED_SETUP_V2_MAX_BYTES)

        val bytes = readBoundedSharedSetupDocument { exact }

        assertThat(bytes).hasLength(SHARED_SETUP_V2_MAX_BYTES)
        assertThat(exact.bytesRead).isEqualTo(SHARED_SETUP_V2_MAX_BYTES)
        assertThat(exact.closed).isTrue()

        val overflow = CountingInputStream(SHARED_SETUP_V2_MAX_BYTES + 4_096)
        val failure = assertThrows(IllegalStateException::class.java) {
            readBoundedSharedSetupDocument { overflow }
        }
        assertThat(failure).hasMessageThat().contains("4 MiB")
        assertThat(overflow.bytesRead).isEqualTo(SHARED_SETUP_V2_MAX_BYTES + 1)
        assertThat(overflow.closed).isTrue()
    }

    @Test
    fun `outer stream closes when provider read fails`() {
        val failing = object : InputStream() {
            var closed = false
            override fun read(): Int = error("synthetic provider failure")
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
                error("synthetic provider failure")
            override fun close() {
                closed = true
            }
        }

        assertThrows(IllegalStateException::class.java) {
            readBoundedSharedSetupDocument { failing }
        }
        assertThat(failing.closed).isTrue()
    }

    @Test
    fun `retained coordinator pending import and restoration use outer bound`() {
        val coordinator = SharedSetupCoordinator(mockk(relaxed = true))
        val exact = ByteArray(SHARED_SETUP_V2_MAX_BYTES)

        coordinator.restoreExternalBytes(exact)

        assertThat(coordinator.restorableExternalBytes()).hasLength(SHARED_SETUP_V2_MAX_BYTES)
        assertThat(coordinator.imports.value?.bytes).hasLength(SHARED_SETUP_V2_MAX_BYTES)
        assertThrows(IllegalArgumentException::class.java) {
            coordinator.restoreExternalBytes(ByteArray(SHARED_SETUP_V2_MAX_BYTES + 1))
        }
        assertThrows(IllegalArgumentException::class.java) {
            PendingSharedSetupImport(
                id = 1,
                bytes = ByteArray(SHARED_SETUP_V2_MAX_BYTES + 1),
            )
        }
    }

    @Test
    fun `copy validates complete versioned bytes before opening output`() {
        val validV2 = fixtureFile(
            "packages/contracts/shared-setup/v2/fixtures/android-shared-setup-v2.json",
        ).readBytes()
        val copyContext = mockk<Context>()
        val resolver = mockk<ContentResolver>()
        val destinationUri = Uri.parse("content://synthetic/destination.healthmdconfig")
        val copied = ByteArrayOutputStream()
        every { copyContext.contentResolver } returns resolver
        every { resolver.openOutputStream(destinationUri, "w") } returns copied
        val copyStore = SharedSetupDocumentStore(
            copyContext,
            SharedSetupV2Codec(PermissiveRegistry),
        )

        assertThrows(IllegalArgumentException::class.java) {
            copyStore.copyTo(byteArrayOf(1, 2, 3), destinationUri)
        }
        verify(exactly = 0) { resolver.openOutputStream(destinationUri, "w") }
        copyStore.copyTo(validV2, destinationUri)
        assertThat(copied.toByteArray()).isEqualTo(validV2)
        verify(exactly = 1) { resolver.openOutputStream(destinationUri, "w") }
    }

    private fun fixtureFile(path: String): File {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (true) {
            val candidate = File(directory, path)
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: error("Could not locate $path")
        }
    }

    private class CountingInputStream(private val length: Int) : InputStream() {
        var bytesRead: Int = 0
            private set
        var closed: Boolean = false
            private set

        override fun read(): Int {
            if (bytesRead >= length) return -1
            bytesRead += 1
            return 0
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (bytesRead >= this.length) return -1
            val count = minOf(length, this.length - bytesRead)
            buffer.fill(0, offset, offset + count)
            bytesRead += count
            return count
        }

        override fun close() {
            closed = true
        }
    }

    private object PermissiveRegistry : SharedSetupMetricRegistry {
        override val version: Int = 1
        override val sha256: String = "0".repeat(64)
        override val bySemanticId: Map<String, SharedSetupRegistryBinding> = emptyMap()
        override val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding> = emptyMap()
    }
}
