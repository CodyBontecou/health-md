package com.healthmd.domain.model

fun WorkoutType.displayName(): String =
    name
        .lowercase()
        .split('_')
        .joinToString(" ") { token ->
            if (token == "hiit") "HIIT"
            else token.replaceFirstChar { it.titlecase() }
        }

fun WorkoutType.slug(): String =
    name.lowercase().replace('_', '-')
