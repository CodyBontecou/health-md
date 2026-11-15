package com.healthmd.receiverqa

import java.time.LocalDate

/** Receiver-side answers only. Production selection and seven-day batching stay untouched. */
internal object ReceiverQaCoverage {
    fun completedDates(candidates: List<LocalDate>, mode: String?): List<LocalDate> = when (mode) {
        "all" -> candidates
        // Ten contiguous actual missing days require two normal production batches.
        "holes" -> candidates.drop(10)
        "none" -> emptyList()
        else -> candidates.filterIndexed { index, _ -> index != 1 }
    }
}
