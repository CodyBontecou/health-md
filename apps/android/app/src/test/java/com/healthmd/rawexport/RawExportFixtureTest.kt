package com.healthmd.rawexport

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class RawExportFixtureTest {
    @Test fun v1FixtureDecodesWithPinnedHonestyCapabilities() {
        val text = requireNotNull(javaClass.getResource("/raw-export/v1/minimal-snapshot.json")).readText()
        val snapshot = RawJson.codec.decodeFromString(RawSnapshotDocument.serializer(), text)
        assertThat(snapshot.header.version).isEqualTo(1)
        assertThat(snapshot.header.capabilities.nonTransactional).isTrue()
        assertThat(snapshot.header.capabilities.preservesSourceUnits).isFalse()
        assertThat(snapshot.header.capabilities.preservesUnknownSdkFields).isFalse()
        assertThat(snapshot.manifest.status).isEqualTo(RawSnapshotStatus.COMPLETE)
    }
}
