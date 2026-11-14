package com.healthmd.presentation.endpoints

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.SavedAPIEndpoint
import com.healthmd.domain.model.SavedAPIEndpointError
import com.healthmd.domain.model.SavedAPIEndpointRules
import com.healthmd.presentation.settings.ConnectionTestState
import org.junit.Test

class EndpointSheetValidationTest {
    private val existing = listOf(SavedAPIEndpoint("a", "Home", "https://api.example.com/health"))

    @Test
    fun newSheetDefaultsToMyApi() {
        assertThat(EndpointSheetState().name).isEqualTo(SavedAPIEndpointRules.DEFAULT_NAME)
        assertThat(EndpointSheetState().urlValid).isFalse()
    }

    @Test
    fun validatesNameUrlDuplicateAndToken() {
        val ok = EndpointSheetState(url = "https://ingest.example.org/v1/days")
        assertThat(validateEndpointSheet(ok, existing)).isNull()
        assertThat(validateEndpointSheet(ok.copy(name = ""), existing)).isEqualTo(SavedAPIEndpointError.NAME_REQUIRED)
        assertThat(validateEndpointSheet(ok.copy(url = "not a url"), existing)).isEqualTo(SavedAPIEndpointError.INVALID_URL)
        assertThat(validateEndpointSheet(ok.copy(url = "https://user:pw@example.com"), existing)).isEqualTo(SavedAPIEndpointError.INVALID_URL)
        assertThat(validateEndpointSheet(ok.copy(url = "https://api.example.com/health"), existing))
            .isEqualTo(SavedAPIEndpointError.DUPLICATE_URL)
        assertThat(validateEndpointSheet(ok.copy(token = "bad\ntoken"), existing)).isEqualTo(SavedAPIEndpointError.INVALID_TOKEN)
    }

    @Test
    fun editingKeepsItsOwnUrlAndAFailedOrMissingTestNeverBlocksSaving() {
        val editing = EndpointSheetState(editingId = "a", name = "Home", url = "https://api.example.com/health")
        assertThat(validateEndpointSheet(editing, existing)).isNull()
        assertThat(validateEndpointSheet(editing.copy(test = ConnectionTestState.Failed), existing)).isNull()
        assertThat(validateEndpointSheet(editing.copy(test = ConnectionTestState.Finished(500)), existing)).isNull()
    }

    @Test
    fun displayUrlHidesSchemeAndQuery() {
        assertThat(SavedAPIEndpointRules.displayUrl("https://api.example.com/health?key=secret")).isEqualTo("api.example.com/health")
    }
}
