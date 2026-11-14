package com.healthmd.domain.repository

import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.flow.Flow

/** One committed private preference image. Revision is internal; never a public settings identity. */
data class NativeConfigurationProtectionObservation(val enabled: Boolean, val revision: String)

/** Native service subscription only. Registration and invalidation do not read preferences. */
class NativeConfigurationProtectionSource internal constructor(
    val observations: Flow<NativeConfigurationProtectionObservation?>,
) {
    private val latest = AtomicReference<String?>(null)
    private val listeners = CopyOnWriteArraySet<(String) -> Unit>()

    fun observeChanges(changed: (String) -> Unit): AutoCloseable {
        listeners.add(changed)
        return AutoCloseable { listeners.remove(changed) }
    }

    /** Also fences owners attaching after invalidation but before the matching commit is observed. */
    fun currentRevision(): String? = latest.get()

    internal fun invalidate(revision: String) {
        latest.set(revision)
        listeners.forEach { it(revision) }
    }
}
