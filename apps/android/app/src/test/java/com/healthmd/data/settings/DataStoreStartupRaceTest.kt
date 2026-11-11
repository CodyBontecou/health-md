package com.healthmd.data.settings

import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.okio.OkioSerializer
import androidx.datastore.core.okio.OkioStorage
import com.google.common.truth.Truth.assertThat
import java.io.FileNotFoundException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okio.BufferedSink
import okio.BufferedSource
import okio.FileSystem
import okio.ForwardingFileSystem
import okio.Path
import okio.Path.Companion.toPath
import okio.Source
import okio.buffer
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DataStoreStartupRaceTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test
    fun initialReadPreservesAFileCreatedDuringTheFirstOpen() = runBlocking {
        val path = FileSystem.SYSTEM.canonicalize(temporary.root.absolutePath.toPath()) / "startup.int"
        val createdDuringOpen = AtomicBoolean(false)
        val fileSystem = object : ForwardingFileSystem(FileSystem.SYSTEM) {
            override fun source(file: Path): Source {
                if (file == path && createdDuringOpen.compareAndSet(false, true)) {
                    // Model an open that saw ENOENT just before another writer
                    // published the first file. Returning defaults would also
                    // lose the winning writer's value.
                    FileSystem.SYSTEM.sink(file).buffer().use { it.writeInt(42) }
                    throw FileNotFoundException("Synthetic concurrent initial creation")
                }
                return super.source(file)
            }
        }
        val serializer = object : OkioSerializer<Int> {
            override val defaultValue = 0
            override suspend fun readFrom(source: BufferedSource): Int = source.readInt()
            override suspend fun writeTo(t: Int, sink: BufferedSink) { sink.writeInt(t) }
        }
        val job = SupervisorJob()
        val store = DataStoreFactory.create(
            storage = OkioStorage(fileSystem, serializer, producePath = { path }),
            scope = CoroutineScope(job + Dispatchers.IO),
        )
        try {
            assertThat(store.data.first()).isEqualTo(42)
            assertThat(createdDuringOpen.get()).isTrue()
            FileSystem.SYSTEM.source(path).buffer().use { assertThat(it.readInt()).isEqualTo(42) }
        } finally {
            job.cancelAndJoin()
        }
    }
}
