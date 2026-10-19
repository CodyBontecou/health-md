package com.healthmd.presentation.accessibility

const val ACCESSIBILITY_MATRIX_ARGUMENT = "healthmd.accessibility.matrix"

/** Shared geometry only: fixture callbacks must never read or mutate real health/settings state. */
data class AccessibilityDisplayCase(
    val width: Int,
    val height: Int,
    val fontScale: Float,
    val language: String = "en",
    val dark: Boolean = false,
)

/**
 * The complete matrix remains the default for local runs and release qualification.
 * CI repeats every test method on the second flavor using representative baseline
 * and constrained, large-font, RTL/dark viewports; the first flavor covers all ten.
 */
fun accessibilityDisplayCases(matrix: String?): List<AccessibilityDisplayCase> {
    val full = listOf(
        AccessibilityDisplayCase(411, 720, 1f),
        AccessibilityDisplayCase(320, 640, 1f),
        AccessibilityDisplayCase(320, 480, 1.3f),
        AccessibilityDisplayCase(320, 480, 2f),
        AccessibilityDisplayCase(320, 640, 2f),
        AccessibilityDisplayCase(568, 280, 2f),
        AccessibilityDisplayCase(640, 280, 2f),
        AccessibilityDisplayCase(320, 480, 2f, language = "de", dark = true),
        AccessibilityDisplayCase(320, 480, 2f, language = "ar", dark = true),
        AccessibilityDisplayCase(320, 640, 2f, language = "ja"),
    )
    return when (matrix) {
        null, "full" -> full
        "smoke" -> listOf(full.first(), full.single { it.language == "ar" })
        else -> throw IllegalArgumentException(
            "$ACCESSIBILITY_MATRIX_ARGUMENT must be full or smoke; received '$matrix'",
        )
    }
}
