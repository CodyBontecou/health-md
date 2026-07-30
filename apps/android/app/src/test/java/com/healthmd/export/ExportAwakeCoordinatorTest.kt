package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.ExportAwakeCoordinator
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.util.UUID

class ExportAwakeCoordinatorTest {
    @Test
    fun `stays active until every overlapping export ends`() {
        val coordinator = ExportAwakeCoordinator()
        val first = UUID.randomUUID()
        val second = UUID.randomUUID()

        coordinator.beginActivity(first)
        coordinator.beginActivity(second)
        coordinator.endActivity(first)

        assertThat(coordinator.isExportActive.value).isTrue()

        coordinator.endActivity(second)

        assertThat(coordinator.isExportActive.value).isFalse()
    }

    @Test
    fun `begin and end are idempotent`() {
        val coordinator = ExportAwakeCoordinator()
        val activityId = UUID.randomUUID()

        coordinator.beginActivity(activityId)
        coordinator.beginActivity(activityId)
        coordinator.endActivity(activityId)
        coordinator.endActivity(activityId)

        assertThat(coordinator.isExportActive.value).isFalse()
    }

    @Test
    fun `while exporting releases activity after failure`() = runTest {
        val coordinator = ExportAwakeCoordinator()

        runCatching {
            coordinator.whileExporting {
                assertThat(coordinator.isExportActive.value).isTrue()
                error("expected")
            }
        }

        assertThat(coordinator.isExportActive.value).isFalse()
    }
}
