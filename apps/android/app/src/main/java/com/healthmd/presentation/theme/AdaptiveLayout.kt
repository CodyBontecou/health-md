package com.healthmd.presentation.theme

/** Layout decisions use font scale only to allocate space, never to resize the user's text. */
object GeistAdaptiveLayout {
    const val readingFontScale = 1.3f
    const val pairedActionsMinWidthDp = 256
    const val tabMinWidthDp = 64
    const val detailedControlsMinWidthDp = 336

    fun readingFirst(widthDp: Float, heightDp: Float, fontScale: Float): Boolean =
        fontScale >= readingFontScale ||
            widthDp < GeistBreakpoints.small || heightDp < GeistBreakpoints.small

    fun stackActions(widthDp: Float, fontScale: Float): Boolean =
        widthDp / fontScale < pairedActionsMinWidthDp

    fun stackDetailedControls(widthDp: Float, fontScale: Float): Boolean =
        widthDp / fontScale < detailedControlsMinWidthDp

    fun wrapNavigation(widthDp: Float, fontScale: Float, tabCount: Int): Boolean =
        widthDp / fontScale < tabCount * tabMinWidthDp
}
