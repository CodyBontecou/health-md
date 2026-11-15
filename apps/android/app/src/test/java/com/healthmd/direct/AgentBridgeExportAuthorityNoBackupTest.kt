package com.healthmd.direct

import android.content.Context
import android.os.Process
import android.system.Os
import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.AgentBridgeErrorCode
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import io.mockk.verify
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import org.junit.Test

/** Fake Context/native UID/GID and real temp directories ONLY. Native Android OS qualification unrun. */
class AgentBridgeExportAuthorityNoBackupTest {
    @Test
    fun existingUidGidOwnedNative0771ParentIsSafeWithoutCreatingGetterOrChmod() {
        AgentBridgeExportPlanningFixture().use { f ->
            val parent = Files.createDirectory(f.parent.resolve("no_backup"), PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwxrwx--x")))
            Files.setPosixFilePermissions(parent, PosixFilePermissions.fromString("rwxrwx--x")) // TEMP fixture only, bypass fixture umask.
            withNativeContext(f.parent) { context ->
                val before = Files.getPosixFilePermissions(parent)
                val store = AgentBridgeExportAuthorityStore.forNoBackup(context, f.keys)
                assertThat(Files.exists(parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
                assertThat(f.keys.calls).isEqualTo(0)
                store.initialize(f.native)
                val leaf = parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                assertThat(Files.getPosixFilePermissions(leaf)).isEqualTo(PosixFilePermissions.fromString("rwx------"))
                assertThat(Files.getPosixFilePermissions(leaf.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isEqualTo(PosixFilePermissions.fromString("rw-------"))
                val service = AgentBridgeExportPlanningService(store, f.configuration, f.clock)
                assertThat(service.discover(f.peerContext, f.discoveryRequest()).authorityReferences).isEmpty()
                assertThat(Files.getPosixFilePermissions(parent)).isEqualTo(before)
                verify(exactly = 0) { context.noBackupFilesDir }
                verify(exactly = 0) { context.filesDir }
            }
        }
    }

    @Test
    fun absentNoBackupParentRemainsAbsentAndDoesNotLoadKeyOrCreateAnything() {
        AgentBridgeExportPlanningFixture().use { f ->
            withNativeContext(f.parent) { context ->
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeExportAuthorityStore.forNoBackup(context, f.keys) }
                assertThat(Files.exists(f.parent.resolve("no_backup"))).isFalse()
                assertThat(f.keys.calls).isEqualTo(0)
                verify(exactly = 0) { context.noBackupFilesDir }
            }
        }
    }

    @Test
    fun nativeParentOtherWriteOrNonNativeGroupWriteModesAreRejectedWithoutChmod() {
        for (mode in listOf("rwxrwx-wx", "rwxrwx---", "rwx-wx---", "rwx----w-")) {
            AgentBridgeExportPlanningFixture().use { f ->
                val parent = Files.createDirectory(f.parent.resolve("no_backup"), PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString(mode)))
                // Override umask in the TEMP fixture only, never a live native parent.
                Files.setPosixFilePermissions(parent, PosixFilePermissions.fromString(mode))
                withNativeContext(f.parent) { context ->
                    f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeExportAuthorityStore.forNoBackup(context, f.keys) }
                    assertThat(Files.getPosixFilePermissions(parent)).isEqualTo(PosixFilePermissions.fromString(mode))
                    assertThat(Files.exists(parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
                }
            }
        }
    }

    @Test
    fun uidGidMismatchAndNoBackupSymlinkFailClosed() {
        for (mismatch in listOf("uid", "gid", "symlink")) AgentBridgeExportPlanningFixture().use { f ->
            val parent = f.parent.resolve("no_backup")
            if (mismatch == "symlink") Files.createSymbolicLink(parent, f.parent)
            else Files.createDirectory(parent, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwxrwx--x")))
            withNativeContext(f.parent) { context ->
                if (mismatch == "uid") every { Process.myUid() } returns (Files.getAttribute(f.parent, "unix:uid") as Number).toInt() + 1
                if (mismatch == "gid") every { Os.getgid() } returns (Files.getAttribute(f.parent, "unix:gid") as Number).toInt() + 1
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeExportAuthorityStore.forNoBackup(context, f.keys) }
                assertThat(f.keys.calls).isEqualTo(0)
            }
        }
    }

    @Test
    fun arbitraryTestRootInjectionRemainsStrict0700EvenForNativeLooking0771() {
        for (mode in listOf("rwxrwx--x", "rwxrwx---", "rwx----w-")) AgentBridgeExportPlanningFixture().use { f ->
            Files.setPosixFilePermissions(f.parent, PosixFilePermissions.fromString(mode))
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeExportAuthorityStore.inPrivateDirectory(f.parent, f.keys) }
        }
    }

    private fun withNativeContext(data: Path, block: (Context) -> Unit) {
        mockkStatic(Process::class)
        mockkStatic(Os::class)
        try {
            every { Process.myUid() } returns (Files.getAttribute(data, "unix:uid") as Number).toInt()
            every { Os.getgid() } returns (Files.getAttribute(data, "unix:gid") as Number).toInt()
            val context = mockk<Context>()
            every { context.dataDir } returns data.toFile()
            every { context.isDeviceProtectedStorage } returns false
            every { context.noBackupFilesDir } throws AssertionError("Creating getter must not be called")
            every { context.filesDir } throws AssertionError("Creating getter must not be called")
            block(context)
        } finally { unmockkStatic(Process::class); unmockkStatic(Os::class) }
    }
}
