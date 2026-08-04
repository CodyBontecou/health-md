package com.healthmd.data.scheduler

import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Creates opaque identities for independently configured scheduled-export chains. */
@Singleton
class ScheduledExportGeneration @Inject constructor() {
    fun create(): String = UUID.randomUUID().toString()

    companion object {
        private const val MAX_LENGTH = 128
        private const val DIAGNOSTIC_LENGTH = 8

        fun isValid(value: String): Boolean = value.length in 1..MAX_LENGTH &&
            value.all { character ->
                character.isLetterOrDigit() || character == '-' || character == '_'
            }

        /** A health-free, bounded token suitable for local diagnostics. */
        fun diagnosticId(value: String?): String = value
            ?.takeIf(::isValid)
            ?.take(DIAGNOSTIC_LENGTH)
            ?: "none"
    }
}
