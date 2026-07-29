package com.healthmd.domain.exportengine

import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.HealthMdCoreReadiness
import com.healthmd.core.HealthMdCoreService
import java.util.Collections

/** Immutable render boundary. All byte arrays are defensively copied. */
class ExportRenderInput(
    val pin: ExportEnginePin,
    val requestId: String,
    val sessionId: String,
    configurationBytes: ByteArray,
    semanticResultBytes: ByteArray,
    renderBatches: List<ByteArray>,
) {
    private val storedConfiguration = configurationBytes.copyOf()
    private val storedSemanticResult = semanticResultBytes.copyOf()
    private val storedBatches = renderBatches.map(ByteArray::copyOf)

    val batchCount: Int get() = storedBatches.size

    init {
        require(requestId.isNotEmpty() && requestId.length <= 128 && requestId.none(Char::isISOControl)) {
            "render request identity is invalid"
        }
        require(sessionId.isNotEmpty() && sessionId.length <= 128 && sessionId.none(Char::isISOControl)) {
            "render session identity is invalid"
        }
        require(storedBatches.isNotEmpty()) { "render batches are empty" }
    }

    fun configurationBytes(): ByteArray = storedConfiguration.copyOf()

    fun semanticResultBytes(): ByteArray = storedSemanticResult.copyOf()

    fun renderBatches(): List<ByteArray> =
        Collections.unmodifiableList(storedBatches.map(ByteArray::copyOf))

    override fun toString(): String =
        "ExportRenderInput(pin=$pin, requestId=<redacted>, sessionId=<redacted>, " +
            "configuration=<redacted>, semanticResult=<redacted>, batchCount=$batchCount)"
}

/** A pure planning engine. Implementations must not write destinations or perform HTTP requests. */
fun interface ExportPlanEngine {
    fun render(input: ExportRenderInput): ExportArtifactPlan
}

/** Foundation boundary around the existing Kotlin renderer oracle. */
fun interface NativeExportEngine : ExportPlanEngine

/** Shared-core renderer. It produces a validated plan and performs no destination side effects. */
class RustExportEngine(
    private val service: HealthMdCoreService = HealthMdCoreService(),
    private val pinValidator: ExportEnginePinValidator = ExportEnginePinValidator(),
) : ExportPlanEngine {
    override fun render(input: ExportRenderInput): ExportArtifactPlan {
        requireRustPin(input)
        val compatibility = pinValidator.validate(input.pin, service)
        return renderValidated(input, compatibility)
    }

    /**
     * Renders against the exact readiness and registry evidence already captured for this attempt.
     * This keeps application adapters from re-fetching mutable core evidence after creating a pin.
     */
    fun render(
        input: ExportRenderInput,
        readiness: HealthMdCoreReadiness,
        registry: CoreMetricRegistrySnapshot,
    ): ExportArtifactPlan {
        requireRustPin(input)
        return renderValidated(
            input,
            pinValidator.validate(input.pin, readiness, registry),
        )
    }

    private fun requireRustPin(input: ExportRenderInput) {
        if (input.pin.engine == ExportEngineMode.legacy) {
            throw IllegalStateException("legacy pin cannot invoke the Rust export engine")
        }
    }

    private fun renderValidated(
        input: ExportRenderInput,
        compatibility: ExportEnginePinCompatibility,
    ): ExportArtifactPlan {
        if (!compatibility.isCompatible) {
            throw ExportEnginePinCompatibilityException(compatibility)
        }
        val plan = service.createRenderSession(
            input.configurationBytes(),
            input.semanticResultBytes(),
        ).use { session ->
            input.renderBatches().forEach(session::processBatch)
            ExportArtifactPlan.fromCore(session.finish())
        }
        if (plan.requestId != input.requestId) {
            throw ExportArtifactPlanValidationException(
                ExportArtifactPlanValidationIssue.REQUEST_ID,
            )
        }
        if (plan.sessionId != input.sessionId) {
            throw ExportArtifactPlanValidationException(
                ExportArtifactPlanValidationIssue.SESSION_ID,
            )
        }
        if (plan.profile != input.pin.profile) {
            throw ExportArtifactPlanValidationException(
                ExportArtifactPlanValidationIssue.PROFILE,
            )
        }
        if (plan.artifactPlanVersion != input.pin.artifactPlanVersion) {
            throw ExportArtifactPlanValidationException(
                ExportArtifactPlanValidationIssue.VERSION,
            )
        }
        return plan
    }
}

enum class ShadowRustFailureCode {
    CORE_UNAVAILABLE,
    PIN_INCOMPATIBLE,
    INVALID_PLAN,
    RENDER_FAILED,
}

/** Closed diagnostics surface: it cannot carry arbitrary messages, paths, values, or payloads. */
sealed interface ShadowExportDiagnostic {
    val profile: AndroidExportProfile
    val semanticProfileRevision: UInt
    val renderProfileRevision: UInt
}

data class ShadowComparisonDiagnostic(
    override val profile: AndroidExportProfile,
    override val semanticProfileRevision: UInt,
    override val renderProfileRevision: UInt,
    val comparison: ExportArtifactPlanComparison,
) : ShadowExportDiagnostic

data class ShadowRustFailureDiagnostic(
    override val profile: AndroidExportProfile,
    override val semanticProfileRevision: UInt,
    override val renderProfileRevision: UInt,
    val code: ShadowRustFailureCode,
) : ShadowExportDiagnostic

fun interface ShadowExportDiagnosticSink {
    fun emit(diagnostic: ShadowExportDiagnostic)
}

/**
 * Runs both planners from the identical immutable input and always returns native authority.
 * Rust/comparison/diagnostic failures cannot turn a successful native plan into export failure.
 */
class ShadowExportEngine(
    private val nativeEngine: NativeExportEngine,
    private val rustEngine: ExportPlanEngine,
    private val diagnosticSink: ShadowExportDiagnosticSink = ShadowExportDiagnosticSink { },
    private val comparator: ExportArtifactPlanComparator = ExportArtifactPlanComparator(),
    private val comparisonOptions: ExportArtifactComparisonOptions =
        ExportArtifactComparisonOptions(),
) : ExportPlanEngine {
    override fun render(input: ExportRenderInput): ExportArtifactPlan {
        require(input.pin.engine == ExportEngineMode.shadow) {
            "shadow export engine requires a shadow pin"
        }
        val nativePlan = nativeEngine.render(input)
        try {
            val rustPlan = rustEngine.render(input)
            val comparison = comparator.compare(nativePlan, rustPlan, comparisonOptions)
            emitSafely(
                ShadowComparisonDiagnostic(
                    profile = input.pin.profile,
                    semanticProfileRevision = input.pin.semanticProfileRevision,
                    renderProfileRevision = input.pin.renderProfileRevision,
                    comparison = comparison,
                ),
            )
        } catch (error: Throwable) {
            if (error.isFatalExportEngineFailure()) throw error
            emitSafely(
                ShadowRustFailureDiagnostic(
                    profile = input.pin.profile,
                    semanticProfileRevision = input.pin.semanticProfileRevision,
                    renderProfileRevision = input.pin.renderProfileRevision,
                    code = when (error) {
                        is ExportEnginePinCompatibilityException ->
                            ShadowRustFailureCode.PIN_INCOMPATIBLE
                        is ExportArtifactPlanValidationException ->
                            ShadowRustFailureCode.INVALID_PLAN
                        is LinkageError -> ShadowRustFailureCode.CORE_UNAVAILABLE
                        else -> ShadowRustFailureCode.RENDER_FAILED
                    },
                ),
            )
        }
        return nativePlan
    }

    private fun emitSafely(diagnostic: ShadowExportDiagnostic) {
        try {
            diagnosticSink.emit(diagnostic)
        } catch (error: Throwable) {
            if (error.isFatalExportEngineFailure()) throw error
            // Observability is strictly non-authoritative in shadow mode.
        }
    }
}
