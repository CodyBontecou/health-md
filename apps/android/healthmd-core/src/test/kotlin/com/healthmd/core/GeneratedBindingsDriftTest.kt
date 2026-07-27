package com.healthmd.core

import com.google.common.truth.Truth.assertThat
import java.io.File
import org.junit.Test

class GeneratedBindingsDriftTest {
    @Test
    fun committedBindingsMatchPinnedUniffiGeneration() {
        val committed = requiredFileProperty("healthmd.core.bindings.committed")
        val generated = requiredFileProperty("healthmd.core.bindings.generated")

        assertThat(committed.readBytes()).isEqualTo(generated.readBytes())
        assertThat(committed.readText()).contains("val bindings_contract_version = 30")
    }

    private fun requiredFileProperty(name: String): File {
        val path = checkNotNull(System.getProperty(name)) { "Missing test system property: $name" }
        return File(path).also {
            check(it.isFile) { "Expected test file does not exist: $it" }
        }
    }
}
