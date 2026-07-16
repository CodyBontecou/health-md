package com.healthmd.rawexport

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class RawExportFixtureTest {
    @Test fun plannedManualCompletionFixtureDecodesNestedDiscriminator() {
        val text = requireNotNull(javaClass.getResource("/raw-export/v1/planned-manual-completion-record.json")).readText()
        val record = RawJson.codec.decodeFromString(RawRecord.serializer(), text)
        val goal = record.fields.getValue("blocks").jsonArray.single().jsonObject
            .getValue("steps").jsonArray.single().jsonObject
            .getValue("completionGoal").jsonObject
        assertThat(goal.keys).containsExactly("type")
        assertThat(goal.getValue("type").jsonPrimitive.content).isEqualTo("manual_completion")
    }

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
