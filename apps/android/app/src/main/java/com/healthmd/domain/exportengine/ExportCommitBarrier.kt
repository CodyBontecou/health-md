package com.healthmd.domain.exportengine

import kotlinx.serialization.Serializable

/** Durable one-way phases around destination side effects. */
@Serializable
enum class ExportCommitState {
    planned,
    materialized,
    committing,
    completed,
    failed,
}

class ExportCommitBarrierException(
    val currentState: ExportCommitState,
    val requestedState: ExportCommitState? = null,
) : IllegalStateException("export commit barrier rejected an operation")

/**
 * Serializes state changes and prevents a plan from changing once destination commits can begin.
 * Guarded actions run while holding the barrier lock so commit cannot race an engine switch.
 */
class ExportCommitBarrier(
    initialState: ExportCommitState = ExportCommitState.planned,
) {
    @Volatile
    var state: ExportCommitState = initialState
        private set

    @Synchronized
    fun markMaterialized(): ExportCommitState = transition(ExportCommitState.materialized)

    @Synchronized
    fun markCommitting(): ExportCommitState = transition(ExportCommitState.committing)

    @Synchronized
    fun markCompleted(): ExportCommitState = transition(ExportCommitState.completed)

    @Synchronized
    fun markFailed(): ExportCommitState = transition(ExportCommitState.failed)

    @Synchronized
    fun transition(next: ExportCommitState): ExportCommitState {
        if (next == state) return state
        val allowed = when (state) {
            ExportCommitState.planned ->
                next == ExportCommitState.materialized || next == ExportCommitState.failed
            ExportCommitState.materialized ->
                next == ExportCommitState.committing || next == ExportCommitState.failed
            ExportCommitState.committing ->
                next == ExportCommitState.completed || next == ExportCommitState.failed
            ExportCommitState.completed,
            ExportCommitState.failed -> false
        }
        if (!allowed) throw ExportCommitBarrierException(state, next)
        state = next
        return state
    }

    @Synchronized
    fun requireEngineSwitchAllowed() {
        if (!canChangePlan()) throw ExportCommitBarrierException(state)
    }

    @Synchronized
    fun requireRerenderAllowed() {
        if (!canChangePlan()) throw ExportCommitBarrierException(state)
    }

    @Synchronized
    fun <T> withEngineSwitch(action: () -> T): T {
        requireEngineSwitchAllowed()
        return action()
    }

    @Synchronized
    fun <T> withRerender(action: () -> T): T {
        requireRerenderAllowed()
        return action()
    }

    private fun canChangePlan(): Boolean =
        state == ExportCommitState.planned || state == ExportCommitState.materialized
}
