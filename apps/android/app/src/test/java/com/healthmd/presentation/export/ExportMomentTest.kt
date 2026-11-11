package com.healthmd.presentation.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.presentation.export.components.heartFilledFacets
import org.junit.Test

class ExportMomentTest {
    @Test
    fun theHeartFillsWithProgressAndIsWholeOnlyWhenDone() {
        assertThat(heartFilledFacets(0f)).isEqualTo(0)
        assertThat(heartFilledFacets(4f / 7f)).isEqualTo(5)
        assertThat(heartFilledFacets(6f / 7f)).isEqualTo(8)
        assertThat(heartFilledFacets(1f)).isEqualTo(10)
        assertThat(heartFilledFacets(2f)).isEqualTo(10)
        assertThat(heartFilledFacets(-1f)).isEqualTo(0)
    }
}

class LargeExportThresholdTest {
    @org.junit.Test
    fun onlyLongNonRawRangesAskFirst() {
        assertThat(com.healthmd.presentation.export.isLargeExport(90, com.healthmd.rawexport.ExportMode.COMPATIBILITY)).isFalse()
        assertThat(com.healthmd.presentation.export.isLargeExport(365, com.healthmd.rawexport.ExportMode.COMPATIBILITY)).isTrue()
        assertThat(com.healthmd.presentation.export.isLargeExport(365, com.healthmd.rawexport.ExportMode.RAW_SNAPSHOT)).isFalse()
    }
}
