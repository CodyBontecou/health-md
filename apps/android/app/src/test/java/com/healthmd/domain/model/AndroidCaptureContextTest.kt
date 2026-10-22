package com.healthmd.domain.model

import com.google.common.truth.Truth.assertThat
import java.time.ZoneId
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertThrows
import org.junit.Test

@OptIn(ExperimentalSerializationApi::class)
class AndroidCaptureContextTest {
    private val codec = Json { encodeDefaults = true; explicitNulls = false; ignoreUnknownKeys = false }

    @Test
    fun freshMorningCarriesExplicitSuccessorAuthorityWithoutEnablingAnUnqualifiedWriter() {
        val fresh = AndroidCaptureContext(ZoneId.of("Asia/Kathmandu"), SleepDayAttribution.MORNING_ENDS)
        assertThat(codec.encodeToString(fresh)).contains("\"exportProfileID\":\"android-sleep-v6\"")
        val restored = codec.decodeFromString<AndroidCaptureContext>(codec.encodeToString(fresh))
        assertThat(restored).isEqualTo(fresh)
        val error = assertThrows(SleepAttributionUnavailableException::class.java) { restored.requireShippedProfile() }
        assertThat(error.reason).isEqualTo(SleepCaptureAuthorityError.PROFILE_UNAVAILABLE)
    }

    @Test
    fun draftMorningRecoveryNeverManufacturesSuccessorApproval() {
        val draft = """{"calendarTimeZoneIdentifier":"America/Los_Angeles","sleepDayAttribution":"morning_ends"}"""
        val recovered = codec.decodeFromString<AndroidCaptureContext>(draft)
        assertThat(recovered.exportProfileID).isNull()
        assertThat(recovered.sleepDayAttribution).isEqualTo(SleepDayAttribution.MORNING_ENDS)
        assertThat(codec.encodeToString(recovered)).isEqualTo(draft)
        val error = assertThrows(SleepAttributionUnavailableException::class.java) { AndroidCaptureContext.recovered(recovered) }
        assertThat(error.reason).isEqualTo(SleepCaptureAuthorityError.UNVERSIONED_ATTRIBUTION)
        val missing = assertThrows(SleepAttributionUnavailableException::class.java) { AndroidCaptureContext.recovered(null) }
        assertThat(missing.reason).isEqualTo(SleepCaptureAuthorityError.MISSING_DURABLE_ATTRIBUTION)
    }

    @Test
    fun historicalNightEncodingAndAtomicProfileModePairsArePreserved() {
        val old = """{"calendarTimeZoneIdentifier":"America/Los_Angeles","sleepDayAttribution":"night_begins"}"""
        val original = AndroidCaptureContext(ZoneId.of("America/Los_Angeles"), SleepDayAttribution.NIGHT_BEGINS)
        assertThat(codec.encodeToString(original)).isEqualTo(old)
        assertThat(AndroidCaptureContext.recovered(codec.decodeFromString(old))).isEqualTo(original)
        for ((mode, profile) in listOf(
            SleepDayAttribution.NIGHT_BEGINS to "android-sleep-v6",
            SleepDayAttribution.MORNING_ENDS to "android-analytical-v5",
            SleepDayAttribution.MORNING_ENDS to "private-profile-marker",
        )) {
            val error = assertThrows(IllegalArgumentException::class.java) {
                AndroidCaptureContext(ZoneId.of("UTC"), mode, profile)
            }
            assertThat(error.message).isEqualTo("Invalid capture export profile")
        }
    }
}
