package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import org.junit.Assert.assertThrows
import org.junit.Test

class ShadowExportEngineTest {
    @Test
    fun rustFailureNeverChangesNativeSuccessAndUsesSameImmutableInput() {
        val configuration = "config".encodeToByteArray()
        val input = testRenderInput(configuration = configuration)
        configuration.fill('X'.code.toByte())
        val nativePlan = testPlan()
        val diagnostics = mutableListOf<ShadowExportDiagnostic>()
        var nativeInput: ExportRenderInput? = null
        var rustInput: ExportRenderInput? = null
        val engine = ShadowExportEngine(
            nativeEngine = NativeExportEngine { received ->
                nativeInput = received
                assertThat(received.configurationBytes().decodeToString()).isEqualTo("config")
                nativePlan
            },
            rustEngine = ExportPlanEngine { received ->
                rustInput = received
                throw IllegalStateException("must not escape shadow authority")
            },
            diagnosticSink = ShadowExportDiagnosticSink(diagnostics::add),
        )

        val result = engine.render(input)

        assertThat(result).isSameInstanceAs(nativePlan)
        assertThat(nativeInput).isSameInstanceAs(input)
        assertThat(rustInput).isSameInstanceAs(input)
        val failure = diagnostics.single() as ShadowRustFailureDiagnostic
        assertThat(failure.code).isEqualTo(ShadowRustFailureCode.RENDER_FAILED)
        assertThat(failure.toString()).doesNotContain("must not escape")
    }

    @Test
    fun mismatchIsDiagnosticOnlyAndNativePlanRemainsAuthoritative() {
        val nativePlan = testPlan()
        val rustPlan = testPlan(
            items = listOf(testArtifact(content = "different".encodeToByteArray())),
        )
        val diagnostics = mutableListOf<ShadowExportDiagnostic>()
        var nativeCalls = 0
        var rustCalls = 0
        val engine = ShadowExportEngine(
            nativeEngine = NativeExportEngine {
                nativeCalls += 1
                nativePlan
            },
            rustEngine = ExportPlanEngine {
                rustCalls += 1
                rustPlan
            },
            diagnosticSink = ShadowExportDiagnosticSink(diagnostics::add),
        )

        val result = engine.render(testRenderInput())

        assertThat(result).isSameInstanceAs(nativePlan)
        assertThat(nativeCalls).isEqualTo(1)
        assertThat(rustCalls).isEqualTo(1)
        val comparison = diagnostics.single() as ShadowComparisonDiagnostic
        assertThat(comparison.comparison.matches).isFalse()
        assertThat(comparison.comparison.dimensions)
            .contains(ExportArtifactMismatchDimension.BYTES)
    }

    @Test
    fun nativeFailureSkipsRustAndDiagnosticSinkFailureCannotAlterNativeSuccess() {
        var rustCalls = 0
        val nativeError = IllegalStateException("native failed")
        val failingNative = ShadowExportEngine(
            nativeEngine = NativeExportEngine { throw nativeError },
            rustEngine = ExportPlanEngine {
                rustCalls += 1
                testPlan()
            },
        )

        val thrown = assertThrows(IllegalStateException::class.java) {
            failingNative.render(testRenderInput())
        }
        assertThat(thrown).isSameInstanceAs(nativeError)
        assertThat(rustCalls).isEqualTo(0)

        val nativePlan = testPlan()
        val sinkFailure = ShadowExportEngine(
            nativeEngine = NativeExportEngine { nativePlan },
            rustEngine = ExportPlanEngine { nativePlan },
            diagnosticSink = ShadowExportDiagnosticSink { error("diagnostic sink unavailable") },
        )
        assertThat(sinkFailure.render(testRenderInput())).isSameInstanceAs(nativePlan)
    }
}
