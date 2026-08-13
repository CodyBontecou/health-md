package com.healthmd.data.scheduler

import javax.inject.Inject
import javax.inject.Singleton

/** Durable, restartable replacement of one scheduled-export generation with another. */
internal data class ScheduledExportTransition(
    val replacement: ScheduledExportOccurrence,
    val previousGeneration: String?,
    val previousOccurrenceId: String?,
    val cleanupScope: ScheduledExportCleanupScope,
    val phase: ScheduledExportTransitionPhase,
    val reason: String,
) {
    init {
        requireNotNull(replacement.generation) {
            "A scheduled-export transition must persist its replacement generation."
        }
        require(
            cleanupScope != ScheduledExportCleanupScope.GENERATION ||
                previousGeneration?.let(ScheduledExportGeneration::isValid) == true
        ) { "Generation cleanup requires a valid previous generation." }
        require(reason.isNotBlank() && reason.length <= MAX_REASON_LENGTH) {
            "Scheduled-export transition reason is invalid."
        }
    }

    private companion object {
        const val MAX_REASON_LENGTH = 64
    }
}

internal enum class ScheduledExportCleanupScope {
    /** Migration must remove pre-generation work, for which no narrower tag exists. */
    LEGACY,

    /** Only work tagged with [ScheduledExportTransition.previousGeneration] is destructive. */
    GENERATION,

    /** Enabling a schedule with no prior durable occurrence has nothing generation-owned to remove. */
    NONE,
}

internal enum class ScheduledExportTransitionPhase {
    /** The replacement occurrence is durable and old work is stale, but cleanup may be incomplete. */
    PREPARED,

    /** Destructive work for the previous generation completed durably. */
    OLD_WORK_CANCELLED,

    /** Exact/fallback delivery for the replacement completed durably. */
    NEW_OCCURRENCE_ARMED,
}

/** Deterministic lifecycle seam used by tests to model process death at external-state gaps. */
enum class ScheduledExportTransitionCheckpoint {
    DURABLE_TRANSITION,
    OLD_WORK_CANCELLATION,
    NEW_OCCURRENCE_ARM,
    FINALIZATION,
}

/** Production is a no-op; focused tests throw at a checkpoint to model abrupt process death. */
@Singleton
class ScheduledExportTransitionObserver @Inject constructor() {
    fun onCheckpoint(@Suppress("UNUSED_PARAMETER") checkpoint: ScheduledExportTransitionCheckpoint) = Unit
}
