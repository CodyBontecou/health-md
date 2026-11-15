package com.healthmd.presentation

import android.content.Intent

/** A static handoff entry only; never interpret URI components as health scope or authority. */
object CloudRepairLink {
    const val URI = "healthmd://cloud/requests"

    fun matches(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_VIEW && intent.data?.toString() == URI
}
