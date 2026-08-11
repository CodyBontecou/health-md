package com.healthmd.data.clinicianreport

import android.content.Context
import com.healthmd.domain.clinicianreport.ReportSource
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject

class ClinicianReportSourceLabelResolver @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    fun resolve(origin: String?, metadata: Map<String, String> = emptyMap()): ReportSource? {
        val packageName = origin?.trim()?.takeIf { it.isNotEmpty() }
            ?: return if (metadata["recording_method"] == "manual_entry") ReportSource("", true) else null
        val label = runCatching {
            val info = context.packageManager.getApplicationInfo(packageName, 0)
            context.packageManager.getApplicationLabel(info).toString().trim()
        }.getOrNull()?.takeIf { it.isNotEmpty() } ?: packageName
        return ReportSource(label, metadata["recording_method"] == "manual_entry")
    }
}
